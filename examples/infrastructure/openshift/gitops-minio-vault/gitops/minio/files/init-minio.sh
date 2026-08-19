#!/bin/sh
set -eu

log() {
  printf '%s\n' "$*"
}

read_secret_file() {
  file_path="$1"
  if [ ! -s "$file_path" ]; then
    log "Missing required Vault-mounted file: $file_path"
    exit 1
  fi
  tr -d '\r\n' < "$file_path"
}

ROOT_USER="$(read_secret_file "${VAULT_MOUNT_PATH}/${MINIO_ROOT_USER_FILE_NAME}")"
ROOT_PASSWORD="$(read_secret_file "${VAULT_MOUNT_PATH}/${MINIO_ROOT_PASSWORD_FILE_NAME}")"
SERVICE_USER="$(read_secret_file "${VAULT_MOUNT_PATH}/${MINIO_SERVICE_USER_FILE_NAME}")"
SERVICE_PASSWORD="$(read_secret_file "${VAULT_MOUNT_PATH}/${MINIO_SERVICE_PASSWORD_FILE_NAME}")"

log "Waiting for MinIO endpoint ${MINIO_ENDPOINT}"
until mc alias set "${MINIO_ALIAS}" "${MINIO_ENDPOINT}" "${ROOT_USER}" "${ROOT_PASSWORD}" >/dev/null 2>&1; do
  sleep 5
done

log "Creating buckets"
mc mb --ignore-existing "${MINIO_ALIAS}/${USER_ASSETS_BUCKET}"
mc mb --ignore-existing "${MINIO_ALIAS}/${PUBLIC_ASSETS_BUCKET}"

log "Creating or enabling service user"
if mc admin user info "${MINIO_ALIAS}" "${SERVICE_USER}" >/dev/null 2>&1; then
  mc admin user enable "${MINIO_ALIAS}" "${SERVICE_USER}"
else
  mc admin user add "${MINIO_ALIAS}" "${SERVICE_USER}" "${SERVICE_PASSWORD}"
fi

ensure_policy() {
  policy_name="$1"
  policy_file="$2"

  if mc admin policy info "${MINIO_ALIAS}" "${policy_name}" >/dev/null 2>&1; then
    mc admin policy detach "${MINIO_ALIAS}" "${policy_name}" --user "${SERVICE_USER}" >/dev/null 2>&1 || true
    mc admin policy rm "${MINIO_ALIAS}" "${policy_name}"
  fi

  mc admin policy create "${MINIO_ALIAS}" "${policy_name}" "${policy_file}"
}

log "Creating or updating bucket policies"
ensure_policy "${USER_ASSETS_RW_POLICY}" /config/policies/user-assets-rw.json
ensure_policy "${PUBLIC_ASSETS_RW_POLICY}" /config/policies/public-assets-rw.json

log "Attaching service user policies"
mc admin policy attach "${MINIO_ALIAS}" "${USER_ASSETS_RW_POLICY}" --user "${SERVICE_USER}"
mc admin policy attach "${MINIO_ALIAS}" "${PUBLIC_ASSETS_RW_POLICY}" --user "${SERVICE_USER}"

log "Applying anonymous download policy for public assets"
mc anonymous set-json /config/policies/public-assets-anonymous-download.json "${MINIO_ALIAS}/${PUBLIC_ASSETS_BUCKET}"

log "MinIO initialization complete"
