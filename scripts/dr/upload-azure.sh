#!/bin/sh
# Uploads one backup to Azure Blob WITHOUT rclone: rclone's Azure driver
# always READS (HEAD) a blob while uploading it, and our backup identity may
# only WRITE. Two plain REST calls need nothing more than write:
#   1. swap the pod's GKE identity token for an Azure token (keyless)
#   2. PUT each file (Put Blob) - archive first, then its manifest
# Runs in the curl container.
# Env: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_FEDERATED_TOKEN_FILE,
#      AZ_ACCOUNT, AZ_CONTAINER
# Usage: upload-azure.sh <backup-name>
set -eu
name="$1"
day="$(echo "$name" | sed -E 's/^mern-([0-9]{4})([0-9]{2})([0-9]{2}).*/\1\/\2\/\3/')"   # 2026/10/30

token="$(curl -fsS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
  --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "scope=https://storage.azure.com/.default" \
  --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  --data-urlencode "client_assertion=$(cat "$AZURE_FEDERATED_TOKEN_FILE")" \
  | sed -n -E 's/.*"access_token" *: *"([^"]+)".*/\1/p')"
[ -n "$token" ] || { echo "could not get an Azure token for the backup identity"; exit 1; }

for f in "$name.archive.gz.age" "$name.manifest.json"; do
  curl -fsS -X PUT -T "$f" \
    -H "Authorization: Bearer ${token}" \
    -H "x-ms-version: 2023-11-03" \
    -H "x-ms-blob-type: BlockBlob" \
    "https://${AZ_ACCOUNT}.blob.core.windows.net/${AZ_CONTAINER}/mern_ecommerce/${day}/${f}"
done
echo "stored $name in az:${AZ_CONTAINER}/mern_ecommerce/$day/"
