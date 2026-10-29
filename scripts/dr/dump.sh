#!/bin/bash
# Encrypted MongoDB backup + manifest. Runs in the mongo container.
#   MONGO_URI_FILE  connection string of the READ-ONLY backup user
#   AGE_RECIPIENT   age PUBLIC key: can encrypt, can never decrypt
#   AGE             path to the age binary
#   OUT_DIR         where the two output files go
# Prints the backup name, e.g. mern-20261030T201500Z
set -euo pipefail   # pipefail: a failing mongodump fails the job (not just age)
uri="$(cat "$MONGO_URI_FILE")"
name="mern-$(date -u +%Y%m%dT%H%M%SZ)"
archive="$OUT_DIR/$name.archive.gz.age"

# 1. Document count per collection (the restore drill compares against it).
counts="$(mongosh "$uri" --quiet --eval '
  const c = {};
  db.getCollectionNames().sort().forEach(n => { c[n] = db.getCollection(n).countDocuments(); });
  print(JSON.stringify(c));')"
database="$(mongosh "$uri" --quiet --eval 'print(db.getName())')"

# 2. dump -> gzip -> encrypt in ONE stream: nothing unencrypted touches the disk.
mongodump --uri="$uri" --archive --gzip --quiet | "$AGE" -r "$AGE_RECIPIENT" -o "$archive"

# 3. Fingerprint + manifest (small, not secret: names and numbers only).
sha="$(sha256sum "$archive" | cut -d' ' -f1)"
bytes="$(stat -c %s "$archive")"
printf '{"name":"%s","database":"%s","created":"%s","sha256":"%s","bytes":%s,"counts":%s}\n' \
  "$name" "$database" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sha" "$bytes" "$counts" > "$OUT_DIR/$name.manifest.json"
echo "$name"
