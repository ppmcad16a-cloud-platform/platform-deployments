#!/bin/sh
# Downloads the NEWEST backup (archive + manifest) from ONE cloud.
# Runs in the rclone container. Prints only the backup name on stdout.
# Usage: download-latest.sh <gcs|s3|azure>
set -eu
case "$1" in
  gcs)   target="gcs:$GCS_BUCKET" ;;
  s3)    target="s3:$S3_BUCKET" ;;
  azure) target="az:$AZ_CONTAINER" ;;
  *)     echo "unknown source '$1' (use gcs, s3 or azure)" >&2; exit 1 ;;
esac
# Paths look like 2026/10/30/mern-20261030T201500Z.manifest.json, so a plain
# sort puts the newest last. A manifest is uploaded AFTER its archive, so a
# manifest always means a complete backup.
manifest="$(rclone lsf --recursive --files-only --include '*.manifest.json' "$target/mern_ecommerce" | sort | tail -n 1)"
[ -n "$manifest" ] || { echo "no backup found in $target" >&2; exit 1; }
name="$(basename "$manifest" .manifest.json)"
rclone copyto "$target/mern_ecommerce/$manifest" "$name.manifest.json" >&2
rclone copyto "$target/mern_ecommerce/$(dirname "$manifest")/$name.archive.gz.age" "$name.archive.gz.age" >&2
echo "downloaded $name from $target" >&2
echo "$name"
