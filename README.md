# cga-deploy-sentry

Deploy sentry on cloud.gov.au kubernetes

TODO 
- set https://docs.sentry.io/server/config/ SENTRY_ALLOW_ORIGIN?

## Setup

```bash
# Create kubernetes namespaces (requires cluster admin and access to CI credhub)
./k8s-bootstrap.sh

# set the secrets in CI
./ci/set-secrets.sh

# Upload/update pipeline to CI
./ci/create-pipeline.sh
```

## Database

The pipeline supports using an existing postgres db in prod, or it will create one with the aws servicebroker.

To use the existing db, specify the secrets in environment variables and run `ci/set-secrets.sh` to set these in CI credhub.

```
POSTGRES_DB_NAME_PROD:
POSTGRES_ENDPOINT_ADDRESS_PROD:
POSTGRES_MASTER_PASSWORD_PROD:
POSTGRES_MASTER_USERNAME_PROD:
POSTGRES_PORT_PROD:
```

# First user

The first time Sentry is installed, you must login to the web pod and create a root user using `sentry createuser`.
