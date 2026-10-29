#!/bin/bash
# Restore drill. Runs in the mongo container.
#   MANIFEST, ARCHIVE    the downloaded backup
#   AGE, AGE_KEY_FILE    age binary + PRIVATE key (from the vault, deleted after the job)
#   RESTORE_URI_FILE     connection string of restore-drill (may touch ONLY the scratch DB)
#   TARGET_DB            scratch database, e.g. mern_restore_drill
# Exit 0 only if the checksum AND every collection's document count match.
set -euo pipefail
source_db="$(grep -o '"database":"[^"]*"' "$MANIFEST" | cut -d'"' -f4)"

# 1. Is the file exactly what the backup job uploaded?
expected="$(grep -o '"sha256":"[0-9a-f]*"' "$MANIFEST" | cut -d'"' -f4)"
actual="$(sha256sum "$ARCHIVE" | cut -d' ' -f1)"
if [ "$expected" != "$actual" ]; then echo "CHECKSUM MISMATCH: expected $expected, got $actual"; exit 1; fi
echo "checksum OK ($actual)"

uri="$(cat "$RESTORE_URI_FILE")"
# mongorestore must not get a database inside the URI when renaming with nsFrom/nsTo.
uri_nodb="$(printf '%s' "$uri" | sed -E 's#(mongodb(\+srv)?://[^/]+)/[^?]*#\1/#')"

# Always leave the scratch database empty again - even if a step fails.
cleanup() { mongosh "$uri" --quiet --eval 'db.getCollectionNames().forEach(n => db.getCollection(n).drop())' || true; }
trap cleanup EXIT

# 2. decrypt -> restore into the scratch DB (source_db.* is renamed to TARGET_DB.*).
"$AGE" -d -i "$AGE_KEY_FILE" "$ARCHIVE" \
  | mongorestore --uri="$uri_nodb" --archive --gzip --drop --quiet \
      --nsInclude="$source_db.*" --nsFrom="$source_db.*" --nsTo="$TARGET_DB.*"

# 3. Same number of documents in every collection?
MANIFEST="$MANIFEST" mongosh "$uri" --quiet --eval '
  const m = JSON.parse(require("fs").readFileSync(process.env.MANIFEST, "utf8"));
  let bad = 0;
  for (const [n, want] of Object.entries(m.counts)) {
    const got = db.getCollection(n).countDocuments();
    print(`${got === want ? "OK  " : "FAIL"}  ${n}: backup ${want}, restored ${got}`);
    if (got !== want) bad++;
  }
  print(bad ? `${bad} collection(s) differ` : `all ${Object.keys(m.counts).length} collections match`);
  if (bad) quit(1);'
