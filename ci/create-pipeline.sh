#!/usr/bin/env bash

set -eux

TARGET=${TARGET:-mcld}
PIPELINE=sentry

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

export https_proxy=socks5://localhost:8112

fly validate-pipeline --config "${SCRIPT_DIR}/pipeline.yml"

fly -t ${TARGET} set-pipeline -n \
  --config "${SCRIPT_DIR}/pipeline.yml" \
  --pipeline "${PIPELINE}"

# We have pinned redis, so force concourse to fetch it
fly -t ${TARGET} check-resource \
  --resource "${PIPELINE}/redis-chart" \
  --from  "ref:a83f5be3b228389177271ffb6c74c4308f8d678c"

# Check all resources for errors
RESOURCES="$(fly -t "${TARGET}" get-pipeline -p "${PIPELINE}" | yq -r '.resources[].name')"
for RESOURCE in $RESOURCES; do
  fly -t ${TARGET} check-resource --resource "${PIPELINE}/${RESOURCE}"
done


fly -t mcld unpause-pipeline -p $PIPELINE

fly -t mcld trigger-job -j $PIPELINE/deploy-ci

unset https_proxy
