# cga-deploy-sentry

Deploy sentry on cloud.gov.au kubernetes



helmoutput:

```
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace sentry-ci -l "app=sentry-ci,role=web" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward --namespace sentry-ci $POD_NAME 8080:9000

2. Log in with

  USER: admin@sentry.local
  Get login password with
    kubectl get secret --namespace sentry-ci sentry-ci -o jsonpath="{.data.user-password}" | base64 --decode

```