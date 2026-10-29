#!/bin/sh
# Reads ONE secret from GCP Secret Manager with this pod's own Google
# identity (Workload Identity: GKE's metadata server hands out a
# short-lived token - no key file anywhere). Runs in the curl container.
# Usage: fetch-secret.sh <secret-name> <output-file>   (file readable by owner only)
set -eu
project=project-899ced78-a554-40c2-96c
token="$(curl -fsS -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
  | sed -n -E 's/.*"access_token" *: *"([^"]+)".*/\1/p')"
[ -n "$token" ] || { echo "no Workload Identity token - is the pod's service account set up?"; exit 1; }
umask 077
curl -fsS -H "Authorization: Bearer $token" \
  "https://secretmanager.googleapis.com/v1/projects/$project/secrets/$1/versions/latest:access" \
  | sed -n -E 's/.*"data" *: *"([^"]+)".*/\1/p' | base64 -d > "$2"
[ -s "$2" ] || { echo "secret $1 is empty or unreadable"; exit 1; }
echo "fetched $1"
