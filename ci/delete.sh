#!/bin/bash

set -eu
set -o pipefail

: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

export NAMESPACE="sentry-${DEPLOY_ENV}"

ci_user=ci-user

set -x

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

# https://github.com/helm/charts/tree/master/stable/sentry#uninstalling-the-chart
helm delete "sentry-${DEPLOY_ENV}" --purge || true
kubectl -n ${NAMESPACE} delete job/${NAMESPACE}-db-init || true
kubectl -n ${NAMESPACE} delete job/${NAMESPACE}-user-create || true

helm delete "redis-${DEPLOY_ENV}" --purge || true

kubectl -n ${NAMESPACE} delete pvc redis-data-redis-${DEPLOY_ENV}-master-0 || true
kubectl -n ${NAMESPACE} delete pvc redis-data-sentry-${DEPLOY_ENV}-redis-master-0 || true
kubectl -n ${NAMESPACE} delete pvc ${NAMESPACE}-postgresql || true

kubectl -n ${NAMESPACE} delete ServiceBinding sentry-db-binding || true
kubectl -n ${NAMESPACE} delete ServiceInstance sentry-db || true
