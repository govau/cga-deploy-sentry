#!/bin/bash

set -eu
set -o pipefail

: "${DB_PLAN:?Need to set DB_PLAN}"
: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo $KUBECONFIG > k
export KUBECONFIG=k

set -x

export NAMESPACE="sentry-${DEPLOY_ENV}"

kubectl -n ${NAMESPACE} get po # just a test

# Create a db for sentry if one doesnt already exist
if ! kubectl -n ${NAMESPACE} get serviceinstance sentry-db > /dev/null 2>&1 ; then
  kubectl apply -n "${NAMESPACE}" -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceInstance
metadata:
  name: sentry-db
spec:
  clusterServiceClassExternalName: rdspostgresql
  clusterServicePlanExternalName: ${DB_PLAN}
EOF
)
fi

echo "Wait for ${NAMESPACE} sentry-db to be ready"
kubectl -n "${NAMESPACE}" wait --for=condition=Ready --timeout=30m "ServiceInstance/sentry-db"

kubectl apply -n "${NAMESPACE}" -f <(cat <<EOF
apiVersion: servicecatalog.k8s.io/v1beta1
kind: ServiceBinding
metadata:
  name: sentry-db-binding
spec:
  instanceRef:
    name: "sentry-db"
EOF
)

# Create a new random password for redis if one doesnt already exist
if ! kubectl -n ${NAMESPACE} get secret redis > /dev/null 2>&1 ; then
  REDIS_PASSWORD="$(openssl rand -base64 12)"
  kubectl -n "${NAMESPACE}" create secret generic redis \
    --from-literal "redis-password=${REDIS_PASSWORD}"
fi

# Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &
helm init --client-only --service-account "ci-user" --wait

# The redis included with sentry is a bit old, so we install our own
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f <($SCRIPT_DIR/../values/gen-redis.sh) \
  redis-${DEPLOY_ENV} redis-chart/stable/redis

# Wait for redis to be ready
kubectl rollout status --namespace=${NAMESPACE} \
  --timeout=2m \
  --watch statefulset/redis-${DEPLOY_ENV}-master

kubectl rollout status --namespace=${NAMESPACE} \
  --timeout=2m \
  --watch deployment/redis-${DEPLOY_ENV}-slave

# Add prometheus rule for monitoring redis
kubectl apply -n "${NAMESPACE}" -f <(cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    app: prometheus-operator
    release: prometheus-operator
  name: redis-${DEPLOY_ENV}-rules
  namespace: ${NAMESPACE}
spec:
  groups:
  - name: redis-exporter
    rules:
    - alert: RedisExporterLastScrapeError
      annotations:
        summary: Redis exporter scrape error
        message: The last redis exporter scrape showed an error
      expr: redis_exporter_last_scrape_error > 0
      labels:
        severity: error
EOF
)

helm dependency update sentry-chart/stable/sentry/

SENTRY_VALUES_FILE="$(mktemp)"
$SCRIPT_DIR/../values/gen-sentry.sh > ${SENTRY_VALUES_FILE}

helm upgrade --install --wait --recreate-pods \
  --namespace ${NAMESPACE} \
  -f ${SENTRY_VALUES_FILE} \
  sentry-${DEPLOY_ENV} sentry-chart/stable/sentry

# Waiting for rollout to finish
DEPLOYMENTS="$(kubectl -n ${NAMESPACE} get deployments -o json | jq -r .items[].metadata.name)"
for DEPLOYMENT in $DEPLOYMENTS; do
    kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
        --watch deployment/${DEPLOYMENT}
done

# Add prometheus servicemonitor for monitoring sentry
kubectl apply -n "${NAMESPACE}" -f <(cat <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: "sentry"
  labels:
    release: prometheus-operator
spec:
  selector:
    matchLabels:
      monitor: me
  endpoints:
  - port: metrics
    path: /metrics
EOF
)
