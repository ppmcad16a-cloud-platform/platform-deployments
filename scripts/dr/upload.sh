#!/bin/sh
# Uploads one backup (encrypted archive + manifest) to GCS and S3 (Azure: upload-azure.sh).
# Any failure fails the job: a backup only counts once it exists three times.
# Runs in the rclone container; credentials are keyless and come from the
# pod's environment (see backup.Jenkinsfile).
#
# Why a local "upload/" folder: the backup identities may WRITE but not READ.
# Uploading into a sub-folder makes rclone first check (read) whether that
# folder is a file - refused on Azure. Uploading the folder tree into the
# bucket ROOT needs no such check in any cloud.
# Usage: upload.sh <backup-name>
set -eu
name="$1"
day="$(echo "$name" | sed -E 's/^mern-([0-9]{4})([0-9]{2})([0-9]{2}).*/\1\/\2\/\3/')"   # 2026/10/30

rm -rf upload
mkdir -p "upload/mern_ecommerce/$day"
cp "$name.archive.gz.age" "$name.manifest.json" "upload/mern_ecommerce/$day/"

for target in "gcs:$GCS_BUCKET" "s3:$S3_BUCKET"; do
  # one file at a time, sorted by name: the archive (…archive.gz.age) lands
  # BEFORE its manifest (…manifest.json), so a manifest always means a
  # complete backup (the restore drill relies on that).
  rclone copy --no-check-dest --retries 3 --transfers 1 --order-by name,ascending upload "$target"
  echo "stored $name in $target/mern_ecommerce/$day/"
done
rm -rf upload
