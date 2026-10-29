#!/bin/sh
# Uploads one backup (encrypted archive first, then its manifest) to ALL
# THREE clouds. Any failure fails the job: a backup only counts once it
# exists three times. Runs in the rclone container; credentials are
# keyless and come from the pod's environment (see backup.Jenkinsfile).
# Usage: upload.sh <backup-name>
set -eu
name="$1"
day="$(echo "$name" | sed -E 's/^mern-([0-9]{4})([0-9]{2})([0-9]{2}).*/\1\/\2\/\3/')"   # 2026/10/30
for target in "gcs:$GCS_BUCKET" "s3:$S3_BUCKET" "az:$AZ_CONTAINER"; do
  for f in "$name.archive.gz.age" "$name.manifest.json"; do
    rclone copyto --no-check-dest --retries 3 "$f" "$target/mern_ecommerce/$day/$f"
  done
  echo "stored $name in $target/mern_ecommerce/$day/"
done
