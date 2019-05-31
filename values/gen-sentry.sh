#!/bin/bash

set -eu
set -o pipefail

: "${ADMIN_EMAIL:?Need to set ADMIN_EMAIL}"
: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${EMAIL_FROM_ADDRESS:?Need to set EMAIL_FROM_ADDRESS}"
: "${EMAIL_HOST:?Need to set EMAIL_HOST}"
: "${EMAIL_PORT:?Need to set EMAIL_PORT}"
: "${EMAIL_USER:?Need to set EMAIL_USER}"
: "${EMAIL_PASSWORD:?Need to set EMAIL_PASSWORD}"
: "${GOOGLE_CLIENT_ID:?Need to set GOOGLE_CLIENT_ID}"
: "${GOOGLE_CLIENT_SECRET:?Need to set GOOGLE_CLIENT_SECRET}"
: "${GITHUB_APP_ID:?Need to set GITHUB_APP_ID}"
: "${GITHUB_API_SECRET:?Need to set GITHUB_API_SECRET}"

case ${DEPLOY_ENV} in
  ci)
    : "${BOOTSTRAP_USER_EMAIL:?Need to set BOOTSTRAP_USER_EMAIL}"
    : "${BOOTSTRAP_USER_PASSWORD:?Need to set BOOTSTRAP_USER_PASSWORD}"
    HOSTNAME=sentry-ci.kapps.l.cld.gov.au
    USER_CREATE=true
    ;;
  prod)
    HOSTNAME=sentry.cloud.gov.au
    USER_CREATE=false
    ;;
  *)
    echo "Unknown DEPLOY_ENV: ${DEPLOY_ENV}"
    exit 1
    ;;
esac

export NAMESPACE="sentry-${DEPLOY_ENV}"

TLS_SECRET_NAME="${HOSTNAME//./-}-tls"

POSTGRES_DB_NAME="$(kubectl -n ${NAMESPACE} get secret sentry-db-binding -o json | jq -r '.data.DB_NAME' | base64 -d)"
POSTGRES_ENDPOINT_ADDRESS="$(kubectl -n ${NAMESPACE} get secret sentry-db-binding -o json | jq -r '.data.ENDPOINT_ADDRESS' | base64 -d)"
POSTGRES_MASTER_PASSWORD="$(kubectl -n ${NAMESPACE} get secret sentry-db-binding -o json | jq -r '.data.MASTER_PASSWORD' | base64 -d)"
POSTGRES_MASTER_USERNAME="$(kubectl -n ${NAMESPACE} get secret sentry-db-binding -o json | jq -r '.data.MASTER_USERNAME' | base64 -d)"
POSTGRES_PORT="$(kubectl -n ${NAMESPACE} get secret sentry-db-binding -o json | jq -r '.data.PORT' | base64 -d)"

cat <<EOF
cron:
  resources:
    limits:
      # Increased to avoid CPUThrottlingHigh alerts
      cpu: 500m
      memory: 200Mi
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
    - name: SENTRY_USE_SSL
      value: "True"
    - name: SENTRY_SINGLE_ORGANIZATION
      value: "False"
email:
  from_address: ${EMAIL_FROM_ADDRESS}
  host: ${EMAIL_HOST}
  port: ${EMAIL_PORT}
  user: ${EMAIL_USER}
  password: ${EMAIL_PASSWORD}
  use_tls: "True"
postgresql:
  enabled: false
  postgresDatabase: "${POSTGRES_DB_NAME}"
  postgresHost: "${POSTGRES_ENDPOINT_ADDRESS}"
  postgresPassword: "${POSTGRES_MASTER_PASSWORD}"
  postgresUser: "${POSTGRES_MASTER_USERNAME}"
  postgresPort: "${POSTGRES_PORT}"
redis:
  password: "notused" # this is needed to get the chart to use the below existingSecret
  existingSecret: redis # created in k8s-bootstrap.sh
  enabled: false
  host: "redis-${DEPLOY_ENV}-master"
  port: "6379"
image:
  repository: docker.io/govau/cga-sentry
  tag: "9.1.1-20190515"
service:
  type: ClusterIP
ingress:
  enabled: true
  hostname: "${HOSTNAME}"
  annotations:
    kubernetes.io/tls-acme: "true"
    certmanager.k8s.io/cluster-issuer: "letsencrypt-prod"
    ingress.kubernetes.io/force-ssl-redirect: "true"
  tls:
    - secretName: "${TLS_SECRET_NAME}"
      hosts:
      - ${HOSTNAME}
config:
  configYml: |
    system.url-prefix: https://${HOSTNAME}
    system.admin-email: ${ADMIN_EMAIL}
  sentryConfPy: |
    if 'GITHUB_APP_ID' in os.environ:
        GITHUB_REQUIRE_VERIFIED_EMAIL = True

    if 'GOOGLE_CLIENT_ID' in os.environ:
        GOOGLE_CLIENT_ID = env('GOOGLE_CLIENT_ID')
        GOOGLE_CLIENT_SECRET = env('GOOGLE_CLIENT_SECRET')

    SENTRY_FEATURES['auth:register'] = False
    SENTRY_BEACON = True

metrics:
  enabled: true
  service:
    type: ClusterIP
    labels:
      monitor: me
  resources:
    limits:
      cpu: 200m
      memory: 200Mi
    requests:
      cpu: 100m
      memory: 100Mi

EOF

if [[ ${USER_CREATE} == "true" ]]; then
cat <<EOF
user:
  create: ${USER_CREATE}
  email: ${BOOTSTRAP_USER_EMAIL}
  password: ${BOOTSTRAP_USER_PASSWORD}
EOF
fi
