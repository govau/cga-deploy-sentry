#!/usr/bin/env bash

# Sets the secrets needed by this pipeline.

PIPELINE=sentry

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

set_credhub_value() {
  KEY="$1"
  VALUE="$2"
  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/main/$PIPELINE/$KEY" -t value -v "${VALUE}"
}

assert_credhub_value() {
  KEY="$1"
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/main/${PIPELINE}/${KEY}" > /dev/null 2>&1 ; then
    echo "${KEY} not set in credhub. Add it to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi

}

echo "Ensuring you are logged in to credhub"
if ! https_proxy=socks5://localhost:8112 credhub find > /dev/null; then
  https_proxy=socks5://localhost:8112 credhub login --sso
fi

# secrets for https://github.com/siemens/sentry-auth-oidc
echo "Ensuring oidc auth secrets are set if they are in our env"
if [[ -n ${OIDC_CLIENT_ID_CI} ]]; then
  set_credhub_value oidc_authorization_endpoint "${OIDC_AUTHORIZATION_ENDPOINT}"
  set_credhub_value oidc_client_id_ci "${OIDC_CLIENT_ID_CI}"
  set_credhub_value oidc_client_secret_ci "${OIDC_CLIENT_SECRET_CI}"
  set_credhub_value oidc_client_id_prod "${OIDC_CLIENT_ID_PROD}"
  set_credhub_value oidc_client_secret_prod "${OIDC_CLIENT_SECRET_PROD}"
  set_credhub_value oidc_issuer "${OIDC_ISSUER}"
  set_credhub_value oidc_scope "${OIDC_SCOPE}"
  set_credhub_value oidc_token_endpoint "${OIDC_TOKEN_ENDPOINT}"
  set_credhub_value oidc_userinfo_endpoint "${OIDC_USERINFO_ENDPOINT}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/main/${PIPELINE}/oidc_client_id_ci" > /dev/null 2>&1 ; then
    echo "OIDC auth secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

echo "Ensuring github auth secrets are set if they are in our env"
if [[ -n ${GITHUB_APP_ID} ]]; then
  set_credhub_value github_app_id "${GITHUB_APP_ID}"
  set_credhub_value github_api_secret "${GITHUB_API_SECRET}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/main/${PIPELINE}/github_app_id" > /dev/null 2>&1 ; then
    echo "Github auth secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

echo "Ensuring email secrets are set if they are in our env"
if [[ -n ${EMAIL_FROM_ADDRESS} ]]; then
  set_credhub_value email_from_address "${EMAIL_FROM_ADDRESS}"
  set_credhub_value email_host "${EMAIL_HOST}"
  set_credhub_value email_port "${EMAIL_PORT}"
  set_credhub_value email_user "${EMAIL_USER}"
  set_credhub_value email_password "${EMAIL_PASSWORD}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/main/${PIPELINE}/email_from_address" > /dev/null 2>&1 ; then
    echo "Email secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

if [[ -n ${ADMIN_EMAIL} ]]; then
  set_credhub_value ADMIN_EMAIL "${ADMIN_EMAIL}"
else
  assert_credhub_value ADMIN_EMAIL
fi

if [[ -n ${BOOTSTRAP_USER_EMAIL} ]]; then
  set_credhub_value BOOTSTRAP_USER_EMAIL "${BOOTSTRAP_USER_EMAIL}"
  set_credhub_value BOOTSTRAP_USER_PASSWORD "${BOOTSTRAP_USER_PASSWORD}"
else
  assert_credhub_value BOOTSTRAP_USER_EMAIL
  assert_credhub_value BOOTSTRAP_USER_PASSWORD
fi

# The CI environment uses the aws servicebroker to create a db, which can then
# be destroyed at the end of the day, but in prod we use a db managed in
# terraform. Specify the details for the prod db here.
if [[ -n ${POSTGRES_DB_NAME_PROD} ]]; then
  set_credhub_value POSTGRES_DB_NAME_PROD "${POSTGRES_DB_NAME_PROD}"
  set_credhub_value POSTGRES_ENDPOINT_ADDRESS_PROD "${POSTGRES_ENDPOINT_ADDRESS_PROD}"
  set_credhub_value POSTGRES_MASTER_PASSWORD_PROD "${POSTGRES_MASTER_PASSWORD_PROD}"
  set_credhub_value POSTGRES_MASTER_USERNAME_PROD "${POSTGRES_MASTER_USERNAME_PROD}"
  set_credhub_value POSTGRES_PORT_PROD "${POSTGRES_PORT_PROD}"
fi
