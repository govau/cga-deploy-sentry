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

# First user

The first time Sentry is installed, you must login to the web pod and create a root user using `sentry createuser`.
