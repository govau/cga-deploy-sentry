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
: "${GITHUB_APP_ID:?Need to set GITHUB_APP_ID}"
: "${GITHUB_API_SECRET:?Need to set GITHUB_API_SECRET}"
: "${VALUES_FILE:?Need to set VALUES_FILE}"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

# Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/redis-values.yml \
  redis-${NAMESPACE} charts/stable/redis

# Wait for redis to be ready
kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
  --watch deployment/redis-${NAMESPACE}-slave

POSTGRES_DB_NAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.DB_NAME' | base64 -d)"
POSTGRES_ENDPOINT_ADDRESS="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.ENDPOINT_ADDRESS' | base64 -d)"
POSTGRES_MASTER_PASSWORD="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_PASSWORD' | base64 -d)"
POSTGRES_MASTER_USERNAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_USERNAME' | base64 -d)"
POSTGRES_PORT="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.PORT' | base64 -d)"

# REDIS_SECRET="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-redis-binding -o json)"
# REDIS_HOSTNAME="$(echo ${REDIS_SECRET} | jq -r '.data.HOSTNAME' | base64 -d)"
# REDIS_PASSWORD="$(echo ${REDIS_SECRET} | jq -r '.data.PASSWORD' | base64 -d)"
# REDIS_PORT="$(echo ${REDIS_SECRET} | jq -r '.data.PORT' | base64 -d)"
# REDIS_SCHEME="$(echo ${REDIS_SECRET} | jq -r '.data.SCHEME' | base64 -d)"
# REDIS_URL="$(echo ${REDIS_SECRET} | jq -r '.data.URL' | base64 -d)"
REDIS_HOST="redis-${NAMESPACE}-master"
REDIS_PASSWORD=$(kubectl get secret --namespace ${NAMESPACE} redis-${NAMESPACE} -o jsonpath="{.data.redis-password}" | base64 --decode)
REDIS_PORT="6379"

SECRET_VALUES_FILE=secret-values.yml
cat << EOF > ${SECRET_VALUES_FILE}
web:
  env:
    - name: GITHUB_APP_ID
      value: "${GITHUB_APP_ID}"
    - name: GITHUB_API_SECRET
      value: "${GITHUB_API_SECRET}"
    - name: GOOGLE_CLIENT_ID
      value: "${GOOGLE_CLIENT_ID}"
    - name: GOOGLE_CLIENT_SECRET
      value: "${GOOGLE_CLIENT_SECRET}"
    - name: GITHUB_REQUIRE_VERIFIED_EMAIL
      value: "True"
email:
  from_address: ${EMAIL_FROM_ADDRESS}
  host: ${EMAIL_HOST}
  port: ${EMAIL_PORT}
  user: ${EMAIL_USER}
  password: ${EMAIL_PASSWORD}
  use_tls: ${EMAIL_USE_TLS}
user:
  email: ${DEFAULT_ADMIN_USER}
postgresql:
  enabled: false
  postgresDatabase: "${POSTGRES_DB_NAME}"
  postgresHost: "${POSTGRES_ENDPOINT_ADDRESS}"
  postgresPassword: "${POSTGRES_MASTER_PASSWORD}"
  postgresUser: "${POSTGRES_MASTER_USERNAME}"
  postgresPort: "${POSTGRES_PORT}"
redis:
  enabled: false
  host: "${REDIS_HOST}"
  password: "${REDIS_PASSWORD}"
  port: "${REDIS_PORT}"
EOF

helm dependency update charts/stable/sentry/

# helm does not allow the same deployment name across two different workspaces,
# so we use the workspace name as the deployment name.
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/${VALUES_FILE} \
  -f ${SECRET_VALUES_FILE} \
  ${NAMESPACE} charts/stable/sentry/

# Waiting for rollout to finish
DEPLOYMENTS="$(kubectl -n ${NAMESPACE} get deployments -o json | jq -r .items[].metadata.name)"
for DEPLOYMENT in $DEPLOYMENTS; do
    kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
        --watch deployment/${DEPLOYMENT}
done

