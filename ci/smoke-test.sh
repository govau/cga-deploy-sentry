#!/bin/bash

set -eu
set -o pipefail

: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${NAMESPACE:?Need to set NAMESPACE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

kubectl version

kubectl -n ${NAMESPACE}  get pods

# Get pods that aren't running
# '--field-selector=status.phase=Running' confusingly includes pods that are crashed and stopped, so has to be combined
# with some jq
badpods="$(kubectl -n ${NAMESPACE}  get pods  --field-selector=status.phase='Running' -o json | jq '.items[] | select(.status.containerStatuses[].ready!=true)')"
if [[ $badpods ]]; then
  echo "There are bad pods"
  exit 1
fi

# Try to connect to the web pod port
POD_NAME=$(kubectl -n ${NAMESPACE} get pods -l role=web -o jsonpath="{.items[0].metadata.name}")
kubectl -n ${NAMESPACE} port-forward $POD_NAME 9000:9000 &

attempt_counter=0
max_attempts=20
until $(curl --output /dev/null --silent --head --fail http://127.0.0.1:9000); do
    if [ ${attempt_counter} -eq ${max_attempts} ];then
      echo "Max attempts reached"
      exit 1
    fi
    printf '.'
    attempt_counter=$(($attempt_counter+1))
    sleep 5
done
