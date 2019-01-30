#!/bin/bash

set -eu
set -o pipefail

: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

set -x

kubectl get pods # just a test

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm dependency update src/stable/sentry/

# helm does not allow the same deployment name across two different workspaces, so we use the workspace name as the deployment name
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  ${NAMESPACE} src/stable/sentry/
