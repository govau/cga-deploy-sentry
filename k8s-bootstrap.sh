#!/usr/bin/env bash

set -eu
set -o pipefail

APP_NAME=sentry

# We use two namespaces - one for CI testing, and the other for the actual deployment
# The ci-user will be created in the CI namespace, but will also have access
# to the deployment namespace
NAMESPACE="${APP_NAME}"
NAMESPACE_CI="${APP_NAME}-ci"

ci_user="ci-user"

echo "Checking you are logged in to credhub"
https_proxy=socks5://localhost:8112 credhub find > /dev/null

# We may as well rotate the service account creds if it already exists
kubectl --namespace ${NAMESPACE_CI} delete serviceaccount ${ci_user} || true

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

echo "${kubeconfig}" > secret-kubeconfig
echo "kubeconfig for ci has been saved into secret-kubeconfig"
https_proxy=socks5://localhost:8112 \
credhub set -n "/concourse/apps/$APP_NAME/kubeconfig" -t value -v "$(cat secret-kubeconfig)"

echo "Use in concourse:"
echo "echo \$KUBECONFIG > k"
echo "export KUBECONFIG=k"
echo "kubectl get all"

rm secret-kubeconfig

############
# Test the creds (remove the above `rm`)

# export TILLER_NAMESPACE="${NAMESPACE_CI}"
# set -x

# echo "Starting tiller in the background. It is then killed at the end."
# pkill tiller || true
# export HELM_HOST=:44134
# # KUBECONFIG=secret-kubeconfig tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

# KUBECONFIG=secret-kubeconfig tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

# helm init --client-only --service-account "${ci_user}" --wait

# helm repo update

# helm upgrade --install --wait \
#   --namespace ${NAMESPACE_CI} \
#   mysql-ci stable/mysql

# helm upgrade --install --wait \
#   --namespace ${NAMESPACE} \
#   mysql stable/mysql

# echo "Killing tiller"
# pkill tiller
