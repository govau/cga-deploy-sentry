#!/bin/bash

set -eu
set -o pipefail

: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo $KUBECONFIG > k
export KUBECONFIG=k

set -x

ci_user=ci-user

export NAMESPACE="sentry-${DEPLOY_ENV}"

kubectl -n ${NAMESPACE} get po # just a test

# Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &
helm init --client-only --service-account "${ci_user}" --wait

# The redis included with sentry is a bit old, so we install our own
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/values/redis.yml \
  redis-${DEPLOY_ENV} charts/stable/redis

# Wait for redis to be ready
kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
  --watch deployment/redis-${DEPLOY_ENV}-slave

helm dependency update charts/stable/sentry/

helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f <($SCRIPT_DIR/../values/gen-sentry.sh) \
  sentry-${DEPLOY_ENV} charts/stable/sentry/

# Waiting for rollout to finish
DEPLOYMENTS="$(kubectl -n ${NAMESPACE} get deployments -o json | jq -r .items[].metadata.name)"
for DEPLOYMENT in $DEPLOYMENTS; do
    kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
        --watch deployment/${DEPLOYMENT}
done

