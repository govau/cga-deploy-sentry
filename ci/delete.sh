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

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

# https://github.com/helm/charts/tree/master/stable/sentry#uninstalling-the-chart
helm delete ${NAMESPACE} && \
kubectl -n ${NAMESPACE} delete job/${NAMESPACE}-db-init job/${NAMESPACE}-user-create

# in ci we dont use pvcs, so no need to delete them anymore
# kubectl -n ${NAMESPACE} delete pvc redis-data-${NAMESPACE}-redis-master-0 && \
# kubectl -n ${NAMESPACE} delete pvc ${NAMESPACE}-postgresql
