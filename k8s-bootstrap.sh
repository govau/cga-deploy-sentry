#!/usr/bin/env bash

# This script is run outside of CI with elevated priviledges mainly to
# configure CI prequisities such as ci service account and secrets

set -eu
set -o pipefail

APP_NAME=sentry

# We use two namespaces - one for CI testing, and the other for prod deployment
# The ci-user will be created in the CI namespace, but will also have access
# to the other namespace
NAMESPACE_PROD="${APP_NAME}-prod"
NAMESPACE_CI="${APP_NAME}-ci"
NAMESPACES="${NAMESPACE_CI} ${NAMESPACE_PROD}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Create namespaces
for NAMESPACE in ${NAMESPACES}; do
  kubectl apply -f <(cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: "${NAMESPACE}"
EOF
)
done

# Create service account for CI to use
kubectl apply -f <(cat <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "ci-user"
  namespace: "${NAMESPACE_CI}"
EOF
)

for NAMESPACE in ${NAMESPACES}; do
  # Grant service account access to all namespaces
  kubectl apply -f <(cat <<EOF
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
  namespace: "${NAMESPACE}"
subjects:
- kind: ServiceAccount
  name: "ci-user"
  namespace: "${NAMESPACE_CI}"
roleRef:
  kind: Role
  name: "tiller-manager"
  apiGroup: rbac.authorization.k8s.io
EOF
)

  # Create service instances
  kubectl apply -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceInstance
metadata:
  name: "sentry-db"
  namespace: "${NAMESPACE}"
spec:
  clusterServiceClassExternalName: rdspostgresql
  clusterServicePlanExternalName: dev
EOF
)
done

# todo wait for instances to be created, then we can bind to them
# exit 0

for NAMESPACE in ${NAMESPACES}; do
  # Create service binding
  kubectl apply -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceBinding
metadata:
  name: sentry-db-binding
  namespace: "${NAMESPACE}"
spec:
  instanceRef:
    name: "sentry-db"
EOF
)
  # Create a random password for redis
  if ! kubectl -n ${NAMESPACE} get secret redis > /dev/null 2>&1 ; then
    REDIS_PASSWORD="$(openssl rand -base64 12)"
    kubectl -n "${NAMESPACE}" create secret generic redis \
      --from-literal "redis-password=${REDIS_PASSWORD}"
  fi
done

secret="$(kubectl get "serviceaccount/ci-user" --namespace "${NAMESPACE_CI}" -o=jsonpath='{.secrets[0].name}')"
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
        "user": "ci-user",
        "namespace": "${NAMESPACE_CI}"
      },
      "name": "${NAMESPACE_CI}"
    },
    {
      "context": {
        "cluster": "kubernetes",
        "user": "ci-user",
        "namespace": "${NAMESPACE_PROD}"
      },
      "name": "${NAMESPACE_PROD}"
    }
  ],
  "current-context": "${NAMESPACE_CI}",
  "kind": "Config",
  "users": [
    {
      "name": "ci-user",
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
