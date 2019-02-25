#!/usr/bin/env bash

# Sets the secrets needed by this pipeline.
# Where possible, credentials are rotated each time this script is run.

PIPELINE=sentry

set -euxo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function trim_to_one_access_key(){
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

echo "Ensuring github auth secrets are set if they are in our env"
if [ -n "$GITHUB_APP_ID" ]; then
  set_credhub_value github_app_id "${GITHUB_APP_ID}"
  set_credhub_value github_api_secret "${GITHUB_API_SECRET}"
else
  if ! https_proxy=socks5://localhost:8112 credhub get -n "/concourse/apps/${PIPELINE}/github_app_id" > /dev/null 2>&1 ; then
    echo "Github auth secrets are not set. Add them to your environment (e.g. use .envrc) and re-run this script"
    exit 1
  fi
fi

echo "Ensuring email secrets are set if they are in our env"
if [ -n "$EMAIL_FROM_ADDRESS" ]; then
  set_credhub_value default_admin_user "${DEFAULT_ADMIN_USER}"
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
