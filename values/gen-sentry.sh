#!/bin/bash

set -eu
set -o pipefail

: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"
: "${EMAIL_FROM_ADDRESS:?Need to set EMAIL_FROM_ADDRESS}"
: "${EMAIL_HOST:?Need to set EMAIL_HOST}"
: "${EMAIL_PORT:?Need to set EMAIL_PORT}"
: "${EMAIL_USER:?Need to set EMAIL_USER}"
: "${EMAIL_PASSWORD:?Need to set EMAIL_PASSWORD}"
: "${EMAIL_USE_TLS:?Need to set EMAIL_USE_TLS}"
: "${KUBECONFIG:?Need to set KUBECONFIG}"
: "${GOOGLE_CLIENT_ID:?Need to set GOOGLE_CLIENT_ID}"
: "${GOOGLE_CLIENT_SECRET:?Need to set GOOGLE_CLIENT_SECRET}"
: "${GITHUB_APP_ID:?Need to set GITHUB_APP_ID}"
: "${GITHUB_API_SECRET:?Need to set GITHUB_API_SECRET}"
: "${NAMESPACE:?Need to set NAMESPACE}"

HOSTNAME=sentry.cloud.gov.au
CLUSTER_ISSUER=letsencrypt-prod

case ${DEPLOY_ENV} in
  ci)
    HOSTNAME=sentry-ci.kapps.l.cld.gov.au
    CLUSTER_ISSUER=letsencrypt-staging
esac

TLS_SECRET_NAME="${HOSTNAME//./-}-tls"

POSTGRES_DB_NAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.DB_NAME' | base64 -d)"
POSTGRES_ENDPOINT_ADDRESS="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.ENDPOINT_ADDRESS' | base64 -d)"
POSTGRES_MASTER_PASSWORD="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_PASSWORD' | base64 -d)"
POSTGRES_MASTER_USERNAME="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.MASTER_USERNAME' | base64 -d)"
POSTGRES_PORT="$(kubectl -n ${NAMESPACE} get secret ${NAMESPACE}-db-binding -o json | jq -r '.data.PORT' | base64 -d)"

cat <<EOF
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
postgresql:
  enabled: false
  postgresDatabase: "${POSTGRES_DB_NAME}"
  postgresHost: "${POSTGRES_ENDPOINT_ADDRESS}"
  postgresPassword: "${POSTGRES_MASTER_PASSWORD}"
  postgresUser: "${POSTGRES_MASTER_USERNAME}"
  postgresPort: "${POSTGRES_PORT}"
redis:
  existingSecret: redis # created in k8s-bootstrap.sh
  enabled: false
  host: "redis-${DEPLOY_ENV}-master"
  port: "6379"
image:
  repository: docker.io/govau/cga-sentry
  tag: latest
service:
  type: ClusterIP
ingress:
  enabled: true
  hostname: "${HOSTNAME}"
  annotations:
    kubernetes.io/tls-acme: "true"
    certmanager.k8s.io/cluster-issuer: "CLUSTER_ISSUER"
    ingress.kubernetes.io/force-ssl-redirect: "true"
  tls:
    - secretName: "${TLS_SECRET_NAME}"
      hosts:
      - ${HOSTNAME}
user:
  create: false # only needed the first time, or you can ssh to the container and run `sentry createuser`
config:
  configYml: |
    system.url-prefix: https://${HOSTNAME}
  sentryConfPy: |
    SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
    SESSION_COOKIE_SECURE = True
    CSRF_COOKIE_SECURE = True
    GOOGLE_CLIENT_ID = env('GOOGLE_CLIENT_ID')
    GOOGLE_CLIENT_SECRET = env('GOOGLE_CLIENT_SECRET')
    GITHUB_APP_ID = env('GITHUB_APP_ID')
    GITHUB_API_SECRET = env('GITHUB_API_SECRET')
    GITHUB_REQUIRE_VERIFIED_EMAIL = True
EOF