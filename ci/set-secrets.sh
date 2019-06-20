#!/usr/bin/env bash

# Sets the secrets needed by this pipeline.
# Where possible, credentials are rotated each time this script is run.

PIPELINE=sentry

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function trim_to_one_access_key() {
    iam_user=$1
    key_count=$(aws iam list-access-keys --user-name "${iam_user}" | jq '.AccessKeyMetadata | length')
    if [[ $key_count > 1 ]]; then
        oldest_key_id=$(aws iam list-access-keys --user-name "${iam_user}" | jq -r '.AccessKeyMetadata |= sort_by(.CreateDate) | .AccessKeyMetadata | first | .AccessKeyId')
        aws iam delete-access-key --user-name "${iam_user}" --access-key-id "${oldest_key_id}"
    fi
}

set_credhub_value() {
  KEY="$1"
  VALUE="$2"
  https_proxy=socks5://localhost:8112 \
  credhub set -n "/concourse/apps/$PIPELINE/$KEY" -t value -v "${VALUE}"
}

assert_credhub_value() {
  KEY="$1"
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/${KEY}" > /dev/null 2>&1 ; then
    echo "${KEY} not set in credhub. Add it to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi

}

echo "Ensuring you are logged in to credhub"
if ! https_proxy=socks5://localhost:8112 credhub find > /dev/null; then
  https_proxy=socks5://localhost:8112 credhub login --sso
fi

echo "Setting iam user creds used to access ECR"
iam_user=${PIPELINE}-ecr-pusher
export AWS_PROFILE=l-cld
trim_to_one_access_key $iam_user
output="$(aws iam create-access-key --user-name ${iam_user})"
aws_access_key_id="$(echo $output | jq -r .AccessKey.AccessKeyId)"
aws_secret_access_key="$(echo $output | jq -r .AccessKey.SecretAccessKey)"
aws_repository="$(aws ecr describe-repositories | jq -r '.repositories[] | select( .repositoryName == "sentry") | .repositoryUri')"

export https_proxy=socks5://localhost:8112
credhub s -n /concourse/apps/${PIPELINE}/aws_access_key_id --type value --value "${aws_access_key_id}"
credhub s -n /concourse/apps/${PIPELINE}/aws_secret_access_key --type value --value "${aws_secret_access_key}"
credhub s -n /concourse/apps/${PIPELINE}/aws_repository --type value --value "${aws_repository}"
unset https_proxy

trim_to_one_access_key $iam_user
unset AWS_PROFILE

echo "Ensuring google auth secrets are set"
GOOGLE_CREDS_FILE="$SCRIPT_DIR/../google_client_secret.json"
if [ ! -e $GOOGLE_CREDS_FILE ]; then
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/google_client_id" > /dev/null 2>&1 ; then
    echo $GOOGLE_CREDS_FILE not found

    cat <<EOF
    You must manually create a Google Client ID for sentry sso.

    Go to the DTA SSO project: <https://console.developers.google.com/apis/credentials?project=dta-single-sign-on&organizationId=110492363159>"

    Create an OAuth Client ID credential:
    - Type: Web application
    - Name: Sentry ENV_NAME-cld (not important)
    - Redirect URIs:
        - https://sentry.cloud.gov.au/auth/sso/

    Click the Download JSON link.

    Move the json file to $GOOGLE_CREDS_FILE

    mv ~/Downloads/client_secret_xxxx.json $GOOGLE_CREDS_FILE
EOF
    exit 1
  fi
else
  GOOGLE_CLIENT_ID="$(yq -r .web.client_id ${GOOGLE_CREDS_FILE})"
  GOOGLE_CLIENT_SECRET="$(yq -r .web.client_secret ${GOOGLE_CREDS_FILE})"

  set_credhub_value google_client_id "${GOOGLE_CLIENT_ID}"
  set_credhub_value google_client_secret "${GOOGLE_CLIENT_SECRET}"
fi

# secrets for https://github.com/siemens/sentry-auth-oidc
echo "Ensuring oidc auth secrets are set if they are in our env"
if [[ -v OIDC_CLIENT_ID_CI ]]; then
  set_credhub_value oidc_client_id_ci "${OIDC_CLIENT_ID_CI}"
  set_credhub_value oidc_client_secret_ci "${OIDC_CLIENT_SECRET_CI}"
  set_credhub_value oidc_client_id_prod "${OIDC_CLIENT_ID_PROD}"
  set_credhub_value oidc_client_secret_prod "${OIDC_CLIENT_SECRET_PROD}"
  set_credhub_value oidc_domain "${OIDC_DOMAIN}"
  set_credhub_value oidc_scope "${OIDC_SCOPE}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/oidc_client_id_ci" > /dev/null 2>&1 ; then
    echo "OIDC auth secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

echo "Ensuring github auth secrets are set if they are in our env"
if [[ -v GITHUB_APP_ID ]]; then
  set_credhub_value github_app_id "${GITHUB_APP_ID}"
  set_credhub_value github_api_secret "${GITHUB_API_SECRET}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/github_app_id" > /dev/null 2>&1 ; then
    echo "Github auth secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

echo "Ensuring email secrets are set if they are in our env"
if [[ -v EMAIL_FROM_ADDRESS ]]; then
  set_credhub_value email_from_address "${EMAIL_FROM_ADDRESS}"
  set_credhub_value email_host "${EMAIL_HOST}"
  set_credhub_value email_port "${EMAIL_PORT}"
  set_credhub_value email_user "${EMAIL_USER}"
  set_credhub_value email_password "${EMAIL_PASSWORD}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/email_from_address" > /dev/null 2>&1 ; then
    echo "Email secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

if [[ -v ADMIN_EMAIL ]]; then
  set_credhub_value ADMIN_EMAIL "${ADMIN_EMAIL}"
else
  assert_credhub_value ADMIN_EMAIL
fi

if [[ -v BOOTSTRAP_USER_EMAIL ]]; then
  set_credhub_value BOOTSTRAP_USER_EMAIL "${BOOTSTRAP_USER_EMAIL}"
  set_credhub_value BOOTSTRAP_USER_PASSWORD "${BOOTSTRAP_USER_PASSWORD}"
else
  assert_credhub_value BOOTSTRAP_USER_EMAIL
  assert_credhub_value BOOTSTRAP_USER_PASSWORD
fi

# The CI environment uses the aws servicebroker to create a db, which can then
# be destroyed at the end of the day, but in prod we use a db managed in
# terraform. Specify the details for the prod db here.
if [[ -v POSTGRES_DB_NAME_PROD ]]; then
  set_credhub_value POSTGRES_DB_NAME_PROD "${POSTGRES_DB_NAME_PROD}"
  set_credhub_value POSTGRES_ENDPOINT_ADDRESS_PROD "${POSTGRES_ENDPOINT_ADDRESS_PROD}"
  set_credhub_value POSTGRES_MASTER_PASSWORD_PROD "${POSTGRES_MASTER_PASSWORD_PROD}"
  set_credhub_value POSTGRES_MASTER_USERNAME_PROD "${POSTGRES_MASTER_USERNAME_PROD}"
  set_credhub_value POSTGRES_PORT_PROD "${POSTGRES_PORT_PROD}"
fi
