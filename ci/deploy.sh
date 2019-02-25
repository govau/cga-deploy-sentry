#!/bin/bash

set -eu
set -o pipefail

: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${TILLER_NAMESPACE:?Need to set TILLER_NAMESPACE}"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo $KUBECONFIG > k
export KUBECONFIG=k

ci_user=ci-user

case ${DEPLOY_ENV} in
  ci)
    RELEASE_NAME=sentry-ci
    NAMESPACE=sentry-ci
    ;;
  prod)
    RELEASE_NAME=sentry
    NAMESPACE=sentry
    ;;
  *)
    echo "Bad DEPLOY_ENV: ${DEPLOY_ENV}"
    exit 1
    ;;
esac

# Starting tiller in the background"
export HELM_HOST=:44134
tiller --storage=secret --listen "$HELM_HOST" >/dev/null 2>&1 &

helm init --client-only --service-account "${ci_user}" --wait

# The redis included with sentry is a bit old, so we install our own
helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f deploy-src/values/redis.yml \
  redis-${NAMESPACE} charts/stable/redis

# Wait for redis to be ready
kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
  --watch deployment/redis-${NAMESPACE}-slave

# POSTGRES_DB_NAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.DB_NAME' | base64 -d)"
# POSTGRES_ENDPOINT_ADDRESS="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.ENDPOINT_ADDRESS' | base64 -d)"
# POSTGRES_MASTER_PASSWORD="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_PASSWORD' | base64 -d)"
# POSTGRES_MASTER_USERNAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_USERNAME' | base64 -d)"
# POSTGRES_PORT="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.PORT' | base64 -d)"

# REDIS_SECRET="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-redis-binding -o json)"
# REDIS_HOSTNAME="$(echo ${REDIS_SECRET} | jq -r '.data.HOSTNAME' | base64 -d)"
# REDIS_PASSWORD="$(echo ${REDIS_SECRET} | jq -r '.data.PASSWORD' | base64 -d)"
# REDIS_PORT="$(echo ${REDIS_SECRET} | jq -r '.data.PORT' | base64 -d)"
# REDIS_SCHEME="$(echo ${REDIS_SECRET} | jq -r '.data.SCHEME' | base64 -d)"
# REDIS_URL="$(echo ${REDIS_SECRET} | jq -r '.data.URL' | base64 -d)"
# REDIS_HOST="redis-${DEPLOY_ENV}-master"
# REDIS_PASSWORD is already set in k8s-bootstrap.sh and values

# SECRET_VALUES_FILE=secret-values.yml
# cat << EOF > ${SECRET_VALUES_FILE}
# web:
#   env:
#     - name: GITHUB_APP_ID
#       value: "${GITHUB_APP_ID}"
#     - name: GITHUB_API_SECRET
#       value: "${GITHUB_API_SECRET}"
#     - name: GOOGLE_CLIENT_ID
#       value: "${GOOGLE_CLIENT_ID}"
#     - name: GOOGLE_CLIENT_SECRET
#       value: "${GOOGLE_CLIENT_SECRET}"
#     - name: GITHUB_REQUIRE_VERIFIED_EMAIL
#       value: "True"
#     # - name: SENTRY_REDIS_PASSWORD
#     #   valueFrom:
#     #     secretKeyRef:
#     #       name: redis
#     #       key: redis-password
# email:
#   from_address: ${EMAIL_FROM_ADDRESS}
#   host: ${EMAIL_HOST}
#   port: ${EMAIL_PORT}
#   user: ${EMAIL_USER}
#   password: ${EMAIL_PASSWORD}
#   use_tls: ${EMAIL_USE_TLS}
# user:
#   email: ${DEFAULT_ADMIN_USER}
# postgresql:
#   enabled: false
#   postgresDatabase: "${POSTGRES_DB_NAME}"
#   postgresHost: "${POSTGRES_ENDPOINT_ADDRESS}"
#   postgresPassword: "${POSTGRES_MASTER_PASSWORD}"
#   postgresUser: "${POSTGRES_MASTER_USERNAME}"
#   postgresPort: "${POSTGRES_PORT}"
# redis:
#   existingSecret: redis # created in k8s-bootstrap.sh
#   enabled: false
#   host: "redis-${DEPLOY_ENV}-master"
#   port: "6379"
# EOF

helm dependency update charts/stable/sentry/

helm upgrade --install --wait \
  --namespace ${NAMESPACE} \
  -f <($SCRIPT_DIR/../values/gen-sentry.sh) \
  ${RELEASE_NAME} charts/stable/sentry/

# Waiting for rollout to finish
DEPLOYMENTS="$(kubectl -n ${NAMESPACE} get deployments -o json | jq -r .items[].metadata.name)"
for DEPLOYMENT in $DEPLOYMENTS; do
    kubectl rollout status --namespace=${NAMESPACE} --timeout=2m \
        --watch deployment/${DEPLOYMENT}
done

