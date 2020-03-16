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
: "${OIDC_AUTHORIZATION_ENDPOINT:?Need to set OIDC_AUTHORIZATION_ENDPOINT}"
: "${OIDC_CLIENT_ID:?Need to set OIDC_CLIENT_ID}"
: "${OIDC_CLIENT_SECRET:?Need to set OIDC_CLIENT_SECRET}"
: "${OIDC_ISSUER:?Need to set OIDC_ISSUER}"
: "${OIDC_SCOPE:?Need to set OIDC_SCOPE}"
: "${OIDC_TOKEN_ENDPOINT:?Need to set OIDC_TOKEN_ENDPOINT}"
: "${OIDC_USERINFO_ENDPOINT:?Need to set OIDC_USERINFO_ENDPOINT}"
: "${POSTGRES_DB_NAME:?Need to set POSTGRES_DB_NAME}"
: "${POSTGRES_ENDPOINT_ADDRESS:?Need to set POSTGRES_ENDPOINT_ADDRESS}"
: "${POSTGRES_MASTER_PASSWORD:?Need to set POSTGRES_MASTER_PASSWORD}"
: "${POSTGRES_MASTER_USERNAME:?Need to set POSTGRES_MASTER_USERNAME}"
: "${POSTGRES_PORT:?Need to set POSTGRES_PORT}"
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

cat <<EOF
cron:
  resources:
    limits:
      # Increased to avoid CPUThrottlingHigh alerts
      cpu: 500m
      memory: 200Mi
web:
  replicacount: 3
  env:
    - name: GITHUB_APP_ID
      value: "${GITHUB_APP_ID}"
    - name: GITHUB_API_SECRET
      value: "${GITHUB_API_SECRET}"
    - name: OIDC_AUTHORIZATION_ENDPOINT
      value: "${OIDC_AUTHORIZATION_ENDPOINT}"
    - name: OIDC_CLIENT_ID
      value: "${OIDC_CLIENT_ID}"
    - name: OIDC_CLIENT_SECRET
      value: "${OIDC_CLIENT_SECRET}"
    - name: OIDC_ISSUER
      value: "${OIDC_ISSUER}"
    - name: OIDC_SCOPE
      value: "${OIDC_SCOPE}"
    - name: OIDC_TOKEN_ENDPOINT
      value: "${OIDC_TOKEN_ENDPOINT}"
    - name: OIDC_USERINFO_ENDPOINT
      value: "${OIDC_USERINFO_ENDPOINT}"
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
  tag: "9.1.1-20190603"
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

    if 'OIDC_CLIENT_ID' in os.environ:
        OIDC_AUTHORIZATION_ENDPOINT = env('OIDC_AUTHORIZATION_ENDPOINT')
        OIDC_CLIENT_ID = env('OIDC_CLIENT_ID')
        OIDC_CLIENT_SECRET = env('OIDC_CLIENT_SECRET')
        OIDC_ISSUER = env('OIDC_ISSUER')
        OIDC_SCOPE = env('OIDC_SCOPE')
        OIDC_TOKEN_ENDPOINT = env('OIDC_TOKEN_ENDPOINT')
        OIDC_USERINFO_ENDPOINT = env('OIDC_USERINFO_ENDPOINT')

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
