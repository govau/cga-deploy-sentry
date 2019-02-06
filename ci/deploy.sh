#!/bin/bash

set -eu
set -o pipefail

: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"
: "${GOOGLE_CLIENT_ID:?Need to set GOOGLE_CLIENT_ID}"
: "${GOOGLE_CLIENT_SECRET:?Need to set GOOGLE_CLIENT_SECRET}"
: "${VALUES_FILE:?Need to set VALUES_FILE}"

echo $KUBECONFIG > k
export KUBECONFIG=k
export TILLER_NAMESPACE=sentry-ci

ci_user=ci-user

SECRET_VALUES_FILE=secret-values.yml
cat << EOF > ${SECRET_VALUES_FILE}
web:
  env:
    - name: GOOGLE_CLIENT_ID
      value: "${GOOGLE_CLIENT_ID}"
    - name: GOOGLE_CLIENT_SECRET
      value: "${GOOGLE_CLIENT_SECRET}"
EOF

set -x

kubectl get pods -n ${NAMESPACE} # just a test

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm dependency update src/stable/sentry/

# helm does not allow the same deployment name across two different workspaces,
# so we use the workspace name as the deployment name.
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/${VALUES_FILE} \
  -f ${SECRET_VALUES_FILE} \
  ${NAMESPACE} src/stable/sentry/
