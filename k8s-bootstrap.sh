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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "Ensuring you are logged in to credhub"
if ! https_proxy=socks5://localhost:8112 credhub find > /dev/null; then
  https_proxy=socks5://localhost:8112 credhub login --sso
fi

echo "Ensuring google auth secrets are set"
GOOGLE_CREDS_FILE="$SCRIPT_DIR/google_client_secret.json"
if [ ! -e $GOOGLE_CREDS_FILE ]; then
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${APP_NAME}/google_client_id" > /dev/null 2>&1 ; then
    echo $GOOGLE_CREDS_FILE not found

    cat <<EOF
    You must manually create a Google Client ID for sentry sso.

    Go to the DTA SSO project: <https://console.developers.google.com/apis/credentials?project=dta-single-sign-on&organizationId=110492363159>"

    Create an OAuth Client ID credential:
    - Type: Web application
    - Name: Sentry ENV_NAME-cld (not important)
    - Redirect URIs:
        - https://sentry.kapps.l.cld.gov.au/auth/sso/

    Click the Download JSON link.

    Move the json file to $GOOGLE_CREDS_FILE

    mv ~/Downloads/client_secret_xxxx.json $GOOGLE_CREDS_FILE
EOF
    exit 1
  fi
else
  GOOGLE_CLIENT_ID="$(yq -r .web.client_id ${GOOGLE_CREDS_FILE})"
  GOOGLE_CLIENT_SECRET="$(yq -r .web.client_secret ${GOOGLE_CREDS_FILE})"

  # TODO decide whether to just keep the secrets in credhub or k8s secrets - no need for both
  kubectl create secret generic -n "${NAMESPACE}" sentry-google-auth \
  --from-literal=GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
  --from-literal=GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET} \
  --dry-run -o yaml | kubectl apply -f -

  kubectl create secret generic -n "${NAMESPACE_CI}" sentry-google-auth \
  --from-literal=GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID} \
  --from-literal=GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET} \
  --dry-run -o yaml | kubectl apply -f -

  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/apps/$APP_NAME/google_client_id" -t value -v "${GOOGLE_CLIENT_ID}"

  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/apps/$APP_NAME/google_client_secret" -t value -v "${GOOGLE_CLIENT_SECRET}"
fi

# We may as well rotate the service account creds if it already exists
if kubectl get serviceaccount ${ci_user} > /dev/null 2>&1 ; then
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

echo "Removing secret-kubeconfig"
rm secret-kubeconfig

echo "Use in concourse:"
echo "echo \$KUBECONFIG > k"
echo "export KUBECONFIG=k"
echo "kubectl get all"

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
