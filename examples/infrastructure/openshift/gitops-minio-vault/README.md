# OpenShift GitOps MinIO With Vault CSI

This sample deploys a MinIO object-storage instance on OpenShift with Argo CD and Helm.

The MinIO root credentials and application service credentials are mounted from HashiCorp Vault with the Secrets Store CSI Driver. The sample intentionally does not create or reference OpenShift `Secret` objects for these credentials.

## What It Creates

- Argo CD `Application` pointing at the local Helm chart.
- MinIO `Deployment`, `Service`, optional OpenShift `Route`, and `PersistentVolumeClaim`.
- Vault `SecretProviderClass` for file-based credential injection.
- A PostSync initialization `Job` that creates:
  - `user-assets`
  - `public-assets`
  - read/write IAM policies for both buckets
  - an anonymous read policy for `public-assets`
  - a MinIO service user from Vault-mounted credentials

## Layout

```text
examples/infrastructure/openshift/gitops-minio-vault/
├── README.md
└── gitops/
    ├── applications/
    │   └── minio.yaml
    ├── minio/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   ├── files/
    │   │   ├── init-minio.sh
    │   │   └── policies/
    │   │       ├── public-assets-anonymous-download.json
    │   │       ├── public-assets-rw.json
    │   │       └── user-assets-rw.json
    │   └── templates/
    └── vault/
        ├── README.md
        └── minio-read-policy.hcl
```

## Prerequisites

- OpenShift GitOps / Argo CD installed.
- Secrets Store CSI Driver installed.
- HashiCorp Vault CSI provider installed.
- Vault Kubernetes auth configured for the target OpenShift cluster.
- Vault path containing these keys:
  - `rootUser`
  - `rootPassword`
  - `serviceUser`
  - `servicePassword`

Default Vault path:

```text
secret/data/openshift/minio
```

## Deploy With Argo CD

Edit `gitops/applications/minio.yaml` and set `spec.source.repoURL` to your Git repository URL.

Then apply the application:

```bash
oc apply -f examples/infrastructure/openshift/gitops-minio-vault/gitops/applications/minio.yaml
```

## Render Locally

```bash
helm template minio-vault \
  ./examples/infrastructure/openshift/gitops-minio-vault/gitops/minio
```

## Notes

- The chart uses `MINIO_ROOT_USER_FILE` and `MINIO_ROOT_PASSWORD_FILE` so MinIO reads root credentials from mounted files at startup.
- The init job reads root and service-user credentials from the same Vault CSI volume.
- The sample uses the MinIO community container image, which MinIO documents as GNU AGPLv3 licensed. Review MinIO license obligations before production use.
- For production MinIO on Kubernetes, MinIO recommends the MinIO Operator and Tenant chart over the community chart. This sample stays chart-local to keep the GitOps initialization and configuration easy to inspect.
