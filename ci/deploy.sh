#!/bin/bash

set -eu
set -o pipefail

: "${DEFAULT_ADMIN_USER:?Need to set DEFAULT_ADMIN_USER}"
: "${EMAIL_FROM_ADDRESS:?Need to set EMAIL_FROM_ADDRESS}"
: "${EMAIL_HOST:?Need to set EMAIL_HOST}"
: "${EMAIL_PORT:?Need to set EMAIL_PORT}"
: "${EMAIL_USER:?Need to set EMAIL_USER}"
: "${EMAIL_PASSWORD:?Need to set EMAIL_PASSWORD}"
: "${EMAIL_USE_TLS:?Need to set EMAIL_USE_TLS}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"
: "${GOOGLE_CLIENT_ID:?Need to set GOOGLE_CLIENT_ID}"
: "${GOOGLE_CLIENT_SECRET:?Need to set GOOGLE_CLIENT_SECRET}"
: "${VALUES_FILE:?Need to set VALUES_FILE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

SECRET_VALUES_FILE=secret-values.yml
cat << EOF > ${SECRET_VALUES_FILE}
web:
  env:
    - name: GOOGLE_CLIENT_ID
      value: "${GOOGLE_CLIENT_ID}"
    - name: GOOGLE_CLIENT_SECRET
      value: "${GOOGLE_CLIENT_SECRET}"
email:
  from_address: ${EMAIL_FROM_ADDRESS}
  host: ${EMAIL_HOST}
  port: ${EMAIL_PORT}
  user: ${EMAIL_USER}
  password: ${EMAIL_PASSWORD}
  use_tls: ${EMAIL_USE_TLS}
user:
  email: ${DEFAULT_ADMIN_USER}
EOF

set -x

kubectl get pods -n ${NAMESPACE} # just a test

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm dependency update charts/stable/sentry/

# helm does not allow the same deployment name across two different workspaces,
# so we use the workspace name as the deployment name.
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/${VALUES_FILE} \
  -f ${SECRET_VALUES_FILE} \
  ${NAMESPACE} charts/stable/sentry/

echo "Waiting for rollout to finish"
DEPLOYMENTS="$(kubectl -n ${NAMESPACE} get deployments -o json | jq -r .items[].metadata.name)"
for DEPLOYMENT in $DEPLOYMENTS; do
    kubectl rollout status --namespace=${NAMESPACE} --timeout=1m \
        --watch deployment/${DEPLOYMENT}
done

