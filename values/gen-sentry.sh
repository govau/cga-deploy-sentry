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
: "${OIDC_CLIENT_ID:?Need to set OIDC_CLIENT_ID}"
: "${OIDC_CLIENT_SECRET:?Need to set OIDC_CLIENT_SECRET}"
: "${OIDC_DOMAIN:?Need to set OIDC_DOMAIN}"
: "${OIDC_SCOPE:?Need to set OIDC_SCOPE}"
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

REDIS_BINDING_JSON="$(kubectl -n ${NAMESPACE} get secret sentry-redis-binding -o json)"
REDIS_HOSTNAME="$(echo ${REDIS_BINDING_JSON} | jq -r '.data.hostname' | base64 -d)"
REDIS_PORT="$(echo ${REDIS_BINDING_JSON} | jq -r '.data.port' | base64 -d)"
REDIS_PASSWORD="$(echo ${REDIS_BINDING_JSON} | jq -r '.data.password' | base64 -d)"
REDIS_SCHEME="$(echo ${REDIS_BINDING_JSON} | jq -r '.data.scheme' | base64 -d)"
REDIS_URL="$(echo ${REDIS_BINDING_JSON} | jq -r '.data.url' | base64 -d)"

cat <<EOF
cron:
  resources:
    limits:
      # Increased to avoid CPUThrottlingHigh alerts
      cpu: 500m
      memory: 200Mi
    requests:
      # cpu: 300m
      memory: 200Mi
web:
  resources:
    limits:
      # cpu: 500m
      memory: 800Mi
    requests:
      # cpu: 300m
      memory: 500Mi
  env:
    - name: GITHUB_APP_ID
      value: "${GITHUB_APP_ID}"
    - name: GITHUB_API_SECRET
      value: "${GITHUB_API_SECRET}"
    - name: GOOGLE_CLIENT_ID
      value: "${GOOGLE_CLIENT_ID}"
    - name: GOOGLE_CLIENT_SECRET
      value: "${GOOGLE_CLIENT_SECRET}"
    - name: OIDC_CLIENT_ID
      value: "${OIDC_CLIENT_ID}"
    - name: OIDC_CLIENT_SECRET
      value: "${OIDC_CLIENT_SECRET}"
    - name: OIDC_SCOPE
      value: "${OIDC_SCOPE}"
    - name: OIDC_DOMAIN
      value: "${OIDC_DOMAIN}"
    - name: GITHUB_REQUIRE_VERIFIED_EMAIL
      value: "True"
    - name: SENTRY_USE_SSL
      value: "True"
    - name: SENTRY_SINGLE_ORGANIZATION
      value: "False"
    - name: REDIS_SSL
      value: "True"
worker:
  env:
    - name: REDIS_SSL
      value: "True"
  resources:
    limits:
    #   cpu: 300m
      memory: 500Mi
    requests:
      # cpu: 100m
      memory: 300Mi
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
  enabled: false # dont use internal redis chart
  password: "${REDIS_PASSWORD}"
  host: "${REDIS_HOSTNAME}"
  port: "${REDIS_PORT}"
image:
  repository: docker.io/govau/cga-sentry
  tag: "9.1.1-20190607"
  pullPolicy: Always
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

    if 'OIDC_CLIENT_ID' in os.environ:
        OIDC_CLIENT_ID = env('OIDC_CLIENT_ID')
        OIDC_CLIENT_SECRET = env('OIDC_CLIENT_SECRET')
        OIDC_DOMAIN = env('OIDC_DOMAIN')
        OIDC_SCOPE = env('OIDC_SCOPE')

    SENTRY_FEATURES['auth:register'] = False
    SENTRY_BEACON = True

metrics:
  enabled: true
  service:
    type: ClusterIP
  resources:
    limits:
      cpu: 200m
      memory: 200Mi
    requests:
      cpu: 100m
      memory: 100Mi
  serviceMonitor:
    enabled: true
    namespace: "${NAMESPACE}"
    selector:
      release: prometheus-operator

EOF

if [[ ${USER_CREATE} == "true" ]]; then
cat <<EOF
user:
  create: ${USER_CREATE}
  email: ${BOOTSTRAP_USER_EMAIL}
  password: ${BOOTSTRAP_USER_PASSWORD}
EOF
fi
