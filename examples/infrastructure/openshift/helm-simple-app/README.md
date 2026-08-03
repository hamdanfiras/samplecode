# Simple OpenShift Helm Chart

This example contains a minimal Helm chart for learning how Helm can create an OpenShift `Deployment`, `Service`, and `Route`.

The chart is located at:

```bash
examples/infrastructure/openshift/helm-simple-app/chart
```

## What It Creates

- `Deployment` - runs the application container.
- `Service` - exposes the pod inside the OpenShift cluster.
- `Route` - exposes the service outside the cluster using OpenShift routing.

No Argo CD configuration is included.

## Files

```text
examples/infrastructure/openshift/helm-simple-app/
├── README.md
└── chart/
    ├── Chart.yaml
    ├── values.yaml
    ├── values-dev.yaml
    ├── values-prod.yaml
    └── templates/
        ├── _helpers.tpl
        ├── deployment.yaml
        ├── service.yaml
        └── route.yaml
```

## Values

The default values are in `values.yaml`.

Important values:

| Value | Purpose |
| --- | --- |
| `replicaCount` | Number of pods to run. |
| `image.repository` | Container image repository. |
| `image.tag` | Container image tag. |
| `containerPort` | Port exposed by the container. |
| `service.port` | Port exposed by the Kubernetes service. |
| `route.enabled` | Creates or skips the OpenShift Route. |
| `route.host` | Optional custom route hostname. Empty means OpenShift generates one. |
| `route.tls.enabled` | Enables TLS on the OpenShift Route. |

## Prerequisites

You need:

- Access to an OpenShift cluster.
- The `oc` CLI logged in to the cluster.
- The `helm` CLI installed.

Check your login:

```bash
oc whoami
```

Check the current project:

```bash
oc project
```

Create and switch to a learning project if needed:

```bash
oc new-project helm-learning
```

## Render Templates Locally

This shows the Kubernetes/OpenShift YAML Helm will generate without installing it:

```bash
helm template simple-app ./examples/infrastructure/openshift/helm-simple-app/chart
```

Render with the development values:

```bash
helm template simple-app ./examples/infrastructure/openshift/helm-simple-app/chart \
  -f ./examples/infrastructure/openshift/helm-simple-app/chart/values-dev.yaml
```

Render with the production example values:

```bash
helm template simple-app ./examples/infrastructure/openshift/helm-simple-app/chart \
  -f ./examples/infrastructure/openshift/helm-simple-app/chart/values-prod.yaml
```

## Install

Install the chart into the current OpenShift project:

```bash
helm install simple-app ./examples/infrastructure/openshift/helm-simple-app/chart
```

Install with the development values file:

```bash
helm install simple-app ./examples/infrastructure/openshift/helm-simple-app/chart \
  -f ./examples/infrastructure/openshift/helm-simple-app/chart/values-dev.yaml
```

## Check The Deployment

```bash
oc get deployment,service,route
```

Check pods:

```bash
oc get pods
```

Get the route URL:

```bash
oc get route simple-app
```

Open the route in a browser:

```bash
oc get route simple-app -o jsonpath='http://{.spec.host}{"\n"}'
```

If `route.tls.enabled` is `true`, use `https://` instead of `http://`.

## Upgrade

After changing values or templates, apply the new version with:

```bash
helm upgrade simple-app ./examples/infrastructure/openshift/helm-simple-app/chart
```

Upgrade with a values file:

```bash
helm upgrade simple-app ./examples/infrastructure/openshift/helm-simple-app/chart \
  -f ./examples/infrastructure/openshift/helm-simple-app/chart/values-prod.yaml
```

## Uninstall

Remove the release:

```bash
helm uninstall simple-app
```

## Example Custom Image

You can override values from the command line:

```bash
helm install simple-app ./examples/infrastructure/openshift/helm-simple-app/chart \
  --set image.repository=quay.io/example/my-app \
  --set image.tag=1.0.0 \
  --set containerPort=8080
```

For learning, editing `values.yaml` is usually easier than using many `--set` flags.
