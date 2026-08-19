# Vault Setup Notes

This folder contains Vault-side configuration examples for the OpenShift workload identity used by the chart.

The actual credential values must not be committed to Git. Store them in Vault.

Example KV v2 path expected by the chart:

```text
secret/data/openshift/minio
```

Expected keys:

```text
rootUser
rootPassword
serviceUser
servicePassword
```

Example Vault policy:

```bash
vault policy write minio-read ./minio-read-policy.hcl
```

Example Kubernetes auth role:

```bash
vault write auth/kubernetes/role/minio \
  bound_service_account_names=minio-vault \
  bound_service_account_namespaces=minio-gitops \
  policies=minio-read \
  ttl=24h
```

The chart's `SecretProviderClass` references this role through:

```yaml
vault:
  roleName: minio
```
