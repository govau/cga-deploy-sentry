#!/bin/bash

set -eu
set -o pipefail

: "${DEPLOY_ENV:?Need to set DEPLOY_ENV}"

export NAMESPACE="sentry-${DEPLOY_ENV}"

cat <<EOF
## Cluster settings
cluster:
  enabled: true
  slaveCount: 3

# we do not have a networking plugin that supports network policy
networkPolicy:
  enabled: false

serviceAccount:
  create: false
# rbac:
#   ## Specifies whether RBAC resources should be created
#   ##
#   create: false

#   role:
#     ## Rules to create. It follows the role specification
#     # rules:
#     #  - apiGroups:
#     #    - extensions
#     #    resources:
#     #      - podsecuritypolicies
#     #    verbs:
#     #      - use
#     #    resourceNames:
#     #      - gce.unprivileged
#     rules: []

## Use password authentication
usePassword: true
## Redis password (both master and slave)
## Defaults to a random 10-character alphanumeric string if not set and usePassword is true
## ref: https://github.com/bitnami/bitnami-docker-redis#setting-the-server-password-on-first-run
##
password:
## Use existing secret (ignores previous password)
existingSecret: redis # Created in deploy.sh

## Mount secrets as files instead of environment variables
usePasswordFile: false

## Persist data to a persistent volume
persistence: {}
  ## A manually managed Persistent Volume and Claim
  ## Requires persistence.enabled: true
  ## If defined, PVC must be created manually before volume will be bound
  # existingClaim:

##
## Redis Master parameters
##
master:
  ## Redis port
  port: 6379
  ## Redis command arguments
  ##
  ## Can be used to specify command line arguments, for example:
  ##
  command: "/run.sh"
  ## Redis additional command line flags
  ##
  ## Can be used to specify command line flags, for example:
  ##
  ## extraFlags:
  ##  - "--maxmemory-policy volatile-ttl"
  ##  - "--repl-backlog-size 1024mb"
  extraFlags: []
  ## Comma-separated list of Redis commands to disable
  ##
  ## Can be used to disable Redis commands for security reasons.
  ## Commands will be completely disabled by renaming each to an empty string.
  ## ref: https://redis.io/topics/security#disabling-of-specific-commands
  ##
  # disableCommands:
  # - FLUSHDB
  # - FLUSHALL

  ## Redis Master additional pod labels and annotations
  ## ref: https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/
  podLabels: {}
  podAnnotations: {}

  ## Redis Master resource requests and limits
  ## ref: http://kubernetes.io/docs/user-guide/compute-resources/
  # resources:
  #   requests:
  #     memory: 256Mi
  #     cpu: 100m
  ## Use an alternate scheduler, e.g. "stork".
  ## ref: https://kubernetes.io/docs/tasks/administer-cluster/configure-multiple-schedulers/
  ##
  # schedulerName:

  ## Configure extra options for Redis Master liveness and readiness probes
  ## ref: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/#configure-probes)
  ##
  livenessProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    timeoutSeconds: 5
    successThreshold: 1
    failureThreshold: 5
  readinessProbe:
    enabled: true
    initialDelaySeconds: 5
    periodSeconds: 10
    timeoutSeconds: 1
    successThreshold: 1
    failureThreshold: 5

  ## Redis Master Node selectors and tolerations for pod assignment
  ## ref: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#nodeselector
  ## ref: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#taints-and-tolerations-beta-feature
  ##
  # nodeSelector: {"beta.kubernetes.io/arch": "amd64"}
  # tolerations: []
  ## Redis Master pod/node affinity/anti-affinity
  ##
  affinity: {}

  ## Redis Master Service properties
  service:
    ##  Redis Master Service type
    type: ClusterIP
    port: 6379

    ## Specify the nodePort value for the LoadBalancer and NodePort service types.
    ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport
    ##
    # nodePort:

    ## Provide any additional annotations which may be required. This can be used to
    ## set the LoadBalancer service type to internal only.
    ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#internal-load-balancer
    ##
    annotations: {}
    loadBalancerIP:

  ## Redis Master Pod Security Context
  ##
  securityContext:
    enabled: true
    fsGroup: 1001
    runAsUser: 1001

  ## Enable persistence using Persistent Volume Claims
  ## ref: http://kubernetes.io/docs/user-guide/persistent-volumes/
  ##
  persistence:
    enabled: true
    ## The path the volume will be mounted at, useful when using different
    ## Redis images.
    path: /bitnami/redis/data
    ## The subdirectory of the volume to mount to, useful in dev environments
    ## and one PV for multiple services.
    subPath: ""
    ## redis data Persistent Volume Storage Class
    ## If defined, storageClassName: <storageClass>
    ## If set to "-", storageClassName: "", which disables dynamic provisioning
    ## If undefined (the default) or set to null, no storageClassName spec is
    ##   set, choosing the default provisioner.  (gp2 on AWS, standard on
    ##   GKE, AWS & OpenStack)
    ##
    # storageClass: "-"
    accessModes:
    - ReadWriteOnce
    size: 8Gi

  ## Update strategy, can be set to RollingUpdate or onDelete by default.
  ## https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/#updating-statefulsets
  statefulset:
    updateStrategy: RollingUpdate
    ## Partition update strategy
    ## https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#partitions
    # rollingUpdatePartition:

  ## Redis Master pod priorityClassName
  # priorityClassName: {}

##
## Redis Slave properties
## Note: service.type is a mandatory parameter
## The rest of the parameters are either optional or, if undefined, will inherit those declared in Redis Master
##
slave:
  ## Slave Service properties
  service:
    ## Redis Slave Service type
    type: ClusterIP
    ## Specify the nodePort value for the LoadBalancer and NodePort service types.
    ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport
    ##
    # nodePort:

    ## Provide any additional annotations which may be required. This can be used to
    ## set the LoadBalancer service type to internal only.
    ## ref: https://kubernetes.io/docs/concepts/services-networking/service/#internal-load-balancer
    ##
    annotations: {}
    loadBalancerIP:

  ## Redis port
  # port: 6379
  ## Redis extra flags
  # extraFlags: []
  ## List of Redis commands to disable
  # disableCommands: []

  ## Redis Slave pod/node affinity/anti-affinity
  ##
  affinity: {}

  ## Configure extra options for Redis Slave liveness and readiness probes
  ## ref: https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/#configure-probes)
  ##
  # livenessProbe:
  #   enabled: true
  #   initialDelaySeconds: 30
  #   periodSeconds: 10
  #   timeoutSeconds: 5
  #   successThreshold: 1
  #   failureThreshold: 5
  # readinessProbe:
  #   enabled: true
  #   initialDelaySeconds: 5
  #   periodSeconds: 10
  #   timeoutSeconds: 10
  #   successThreshold: 1
  #   failureThreshold: 5

  ## Redis slave Resource
  # resources:
  #   requests:
  #     memory: 256Mi
  #     cpu: 100m

  ## Redis slave selectors and tolerations for pod assignment
  # nodeSelector: {"beta.kubernetes.io/arch": "amd64"}
  # tolerations: []

  ## Use an alternate scheduler, e.g. "stork".
  ## ref: https://kubernetes.io/docs/tasks/administer-cluster/configure-multiple-schedulers/
  ##
  # schedulerName:

  ## Redis slave pod Annotation and Labels
  # podLabels: {}
  # podAnnotations: {}

  ## Redis slave pod Security Context
  # securityContext:
  #   enabled: true
  #   fsGroup: 1001
  #   runAsUser: 1001

  ## Redis slave pod priorityClassName
  # priorityClassName: {}

## Prometheus Exporter / Metrics
##
metrics:
  enabled: true

  image:
    registry: docker.io
    repository: oliver006/redis_exporter
    tag: v1.3.5
    pullPolicy: IfNotPresent
    ## Optionally specify an array of imagePullSecrets.
    ## Secrets must be manually created in the namespace.
    ## ref: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
    ##
    # pullSecrets:
    #   - myRegistrKeySecretName

  service:
    type: ClusterIP
    ## Use serviceLoadBalancerIP to request a specific static IP,
    ## otherwise leave blank
    # loadBalancerIP:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "9121"

  ## Metrics exporter resource requests and limits
  ## ref: http://kubernetes.io/docs/user-guide/compute-resources/
  ##
  # resources: {}

  ## Extra arguments for Metrics exporter, for example:
  ## extraArgs:
  ##   check-keys: myKey,myOtherKey
  # extraArgs: {}

  ## Metrics exporter labels and tolerations for pod assignment
  # nodeSelector: {"beta.kubernetes.io/arch": "amd64"}
  # tolerations: []

  ## Metrics exporter pod Annotation and Labels
  # podAnnotations: {}
  # podLabels: {}

  # Enable this if you're using https://github.com/coreos/prometheus-operator
  serviceMonitor:
    enabled: true
    namespace: "${NAMESPACE}"
    # fallback to the prometheus default unless specified
    # interval: 10s
    ## [Prometheus Selector Label](https://github.com/helm/charts/tree/master/stable/prometheus-operator#prometheus-operator-1)
    ## [Kube Prometheus Selector Label](https://github.com/helm/charts/tree/master/stable/prometheus-operator#exporters)
    selector:
      release: prometheus-operator

  ## Metrics exporter pod priorityClassName
  # priorityClassName: {}

##
## Init containers parameters:
## volumePermissions: Change the owner of the persist volume mountpoint to RunAsUser:fsGroup
##
volumePermissions:
  enabled: false
  image:
    registry: docker.io
    repository: bitnami/minideb
    tag: latest
    pullPolicy: IfNotPresent
  resources: {}

## Redis config file
## ref: https://redis.io/topics/config
##
configmap: |-
  # maxmemory-policy volatile-lru
  save 120 1

## Sysctl InitContainer
## used to perform sysctl operation to modify Kernel settings (needed sometimes to avoid warnings)
sysctlImage:
  enabled: false
  command: []
  registry: docker.io
  repository: bitnami/minideb
  tag: latest
  pullPolicy: Always
  mountHostSys: false
  resources: {}
EOF
