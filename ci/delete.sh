#!/bin/bash

set -eu
set -o pipefail

: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAME:?Need to set NAME}"
: "${NAMESPACE:?Need to set NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

set -x

echo "Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm delete --name ${NAME}
