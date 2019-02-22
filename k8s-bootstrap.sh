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

set_credhub_value() {
  KEY="$1"
  VALUE="$2"
  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/apps/$APP_NAME/$KEY" -t value -v "${VALUE}"
}
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

  set_credhub_value google_client_id "${GOOGLE_CLIENT_ID}"
  set_credhub_value google_client_secret "${GOOGLE_CLIENT_SECRET}"
fi

echo "Ensuring email secrets are set if they are in our env"
if [ -n "$EMAIL_FROM_ADDRESS" ]; then
  set_credhub_value default_admin_user "${DEFAULT_ADMIN_USER}"
  set_credhub_value email_from_address "${EMAIL_FROM_ADDRESS}"
  set_credhub_value email_host "${EMAIL_HOST}"
  set_credhub_value email_port "${EMAIL_PORT}"
  set_credhub_value email_user "${EMAIL_USER}"
  set_credhub_value email_password "${EMAIL_PASSWORD}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${APP_NAME}/email_from_address" > /dev/null 2>&1 ; then
    echo "Email secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

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

# Create rds database
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
---
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

set_credhub_value kubeconfig "$(cat secret-kubeconfig)"

echo "Removing secret-kubeconfig"
rm secret-kubeconfig

echo "Use in concourse:"
echo "echo \$KUBECONFIG > k"
echo "export KUBECONFIG=k"
echo "kubectl get all"
