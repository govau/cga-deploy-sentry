#!/usr/bin/env bash

# This script is run outside of CI with elevated priviledges mainly to
# configure CI prequisities such as ci service account and secrets

set -eu
set -o pipefail

APP_NAME=sentry

# We use two namespaces - one for CI testing, and the other for the actual deployment
# The ci-user will be created in the CI namespace, but will also have access
# to the deployment namespace
NAMESPACE="${APP_NAME}"
NAMESPACE_CI="${APP_NAME}-ci"

ci_user="ci-user"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# We may as well rotate the service account creds if it already exists
if kubectl --namespace ${NAMESPACE_CI} get serviceaccount ${ci_user} > /dev/null 2>&1 ; then
  kubectl --namespace ${NAMESPACE_CI} delete serviceaccount ${ci_user} || true
fi

kubectl apply -f <(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: "${NAMESPACE_CI}"
---
apiVersion: v1
kind: Namespace
metadata:
  name: "${NAMESPACE}"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: "tiller-manager"
  namespace: "${NAMESPACE_CI}"
rules:
- apiGroups: ["", "batch", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: "tiller-manager"
  namespace: "${NAMESPACE}"
rules:
- apiGroups: ["", "batch", "extensions", "apps"]
  resources: ["*"]
  verbs: ["*"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller-binding
  namespace: "${NAMESPACE_CI}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "tiller-manager"
  apiGroup: rbac.authorization.k8s.io
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller-binding
  namespace: "${NAMESPACE}"
subjects:
- kind: ServiceAccount
  name: "${ci_user}"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "tiller-manager"
  apiGroup: rbac.authorization.k8s.io
EOF
)

# Create service instances
# To start while testing we use rds in ci, but later can probably
# just use the embedded postgres
kubectl apply -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceInstance
metadata:
  name: "${NAMESPACE}-db"
  namespace: "${NAMESPACE}"
spec:
  clusterServiceClassExternalName: rdspostgresql
  clusterServicePlanExternalName: production
---
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceInstance
metadata:
  name: "${NAMESPACE_CI}-db"
  namespace: "${NAMESPACE_CI}"
spec:
  clusterServiceClassExternalName: rdspostgresql
  clusterServicePlanExternalName: dev
EOF
)

# todo wait for instances to be created, then we can bind to them

kubectl apply -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceBinding
metadata:
  name: ${NAMESPACE}-db-binding
  namespace: "${NAMESPACE}"
spec:
  instanceRef:
    name: "${NAMESPACE}-db"
---
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceBinding
metadata:
  name: ${NAMESPACE_CI}-db-binding
  namespace: "${NAMESPACE_CI}"
spec:
  instanceRef:
    name: "${NAMESPACE_CI}-db"
EOF
)

# Create a random password for redis
REDIS_SECRET_NAME=redis
if ! kubectl -n ${NAMESPACE} get secret ${REDIS_SECRET_NAME} > /dev/null 2>&1 ; then
  REDIS_PASSWORD="$(openssl rand -base64 12)"
  kubectl -n "${NAMESPACE}" create secret generic ${REDIS_SECRET_NAME} \
    --from-literal "redis-password=${REDIS_PASSWORD}"
fi
if ! kubectl -n ${NAMESPACE_CI} get secret ${REDIS_SECRET_NAME} > /dev/null 2>&1 ; then
  REDIS_PASSWORD="$(openssl rand -base64 12)"
  kubectl -n "${NAMESPACE_CI}" create secret generic ${REDIS_SECRET_NAME} \
    --from-literal "redis-password=${REDIS_PASSWORD}"
fi

secret="$(kubectl get "serviceaccount/${ci_user}" --namespace "${NAMESPACE_CI}" -o=jsonpath='{.secrets[0].name}')"
token="$(kubectl get secret "${secret}" --namespace "${NAMESPACE_CI}" -o=jsonpath='{.data.token}' | base64 --decode)"

cur_context="$(kubectl config view -o=jsonpath='{.current-context}' --flatten=true)"
cur_cluster="$(kubectl config view -o=jsonpath="{.contexts[?(@.name==\"${cur_context}\")].context.cluster}" --flatten=true)"
cur_api_server="$(kubectl config view -o=jsonpath="{.clusters[?(@.name==\"${cur_cluster}\")].cluster.server}" --flatten=true)"
cur_crt="$(kubectl config view -o=jsonpath="{.clusters[?(@.name==\"${cur_cluster}\")].cluster.certificate-authority-data}" --flatten=true)"

kubeconfig="$(cat <<EOF
{
  "apiVersion": "v1",
  "clusters": [
    {
      "cluster": {
        "certificate-authority-data": "${cur_crt}",
        "server": "${cur_api_server}"
      },
      "name": "kubernetes"
    }
  ],
  "contexts": [
    {
      "context": {
        "cluster": "kubernetes",
        "user": "${ci_user}",
        "namespace": "${NAMESPACE_CI}"
      },
      "name": "${NAMESPACE_CI}"
    },
    {
      "context": {
        "cluster": "kubernetes",
        "user": "${ci_user}",
        "namespace": "${NAMESPACE}"
      },
      "name": "${NAMESPACE}"
    }
  ],
  "current-context": "${NAMESPACE}-ci",
  "kind": "Config",
  "users": [
    {
      "name": "${ci_user}",
      "user": {
        "token": "${token}"
      }
    }
  ]
}
EOF
)"

echo "Ensuring you are logged in to credhub"
if ! https_proxy=socks5://localhost:8112 credhub find > /dev/null; then
  https_proxy=socks5://localhost:8112 credhub login --sso
fi

https_proxy=socks5://localhost:8112 \
credhub set -n "/concourse/apps/sentry/kubeconfig" -t value -v "${kubeconfig}"

echo "Use in concourse:"
echo "echo \$KUBECONFIG > k"
echo "export KUBECONFIG=k"
echo "kubectl get all"
