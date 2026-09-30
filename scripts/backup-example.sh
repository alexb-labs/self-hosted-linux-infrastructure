#!/bin/bash
set -euo pipefail

# Public example of the backup process used for the n8n and RAG services.
# Replace the example values before using this script.
# Never commit generated backups or production .env files.

BACKUP_DIR="/opt/n8n/backup"
REMOTE="r2:example-backups"
MAX_REMOTE_BACKUPS=30
LOGFILE="$BACKUP_DIR/backup.log"
GPG_KEY_ID="REPLACE_WITH_GPG_KEY_FINGERPRINT"
ALERT_EMAIL="admin@example.com"

POSTGRES_CONTAINER="rag-postgres"
N8N_CONTAINER="n8n"
N8N_RUNNERS_CONTAINER="n8n-task-runners"

RAG_DB_USER="raguser"
RAG_DB_NAME="ragdb"
N8N_DB_USER="n8n_user"
N8N_DB_NAME="n8n_db"

TS="$(date +"%Y%m%d-%H%M")"

send_fail_mail() {
  echo "Backup FAILED on $(hostname) at $(date)" \
    | mail -s "Backup FAILED" "$ALERT_EMAIL"
}

cleanup_on_exit() {
  STATUS=$?

  # Prevent the final exit from invoking this trap again.
  trap - EXIT

  # Cleanup errors must not replace the original exit status.
  set +e

  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
    rm -rf -- "$WORK_DIR"
  fi

  if [ -n "${ARCHIVE:-}" ]; then
    rm -f -- "$ARCHIVE"
  fi

  if [ -n "${ENC_FILE:-}" ]; then
    rm -f -- "$ENC_FILE"
  fi

  if [ -n "${VERIFY_GPG_FILE:-}" ]; then
    rm -f -- "$VERIFY_GPG_FILE"
  fi

  docker exec "$POSTGRES_CONTAINER" rm -f \
    /tmp/ragdb.dump \
    /tmp/n8n_db.dump \
    /tmp/postgres-globals.sql \
    >/dev/null 2>&1 || true

  docker exec "$N8N_CONTAINER" rm -rf \
    /tmp/workflow-export \
    /tmp/n8n-cli \
    >/dev/null 2>&1 || true

  if [ "$STATUS" -ne 0 ]; then
    echo "[$(date)] Backup failed; temporary files cleaned up"
    send_fail_mail
  fi

  exit "$STATUS"
}

trap cleanup_on_exit EXIT

mkdir -p "$BACKUP_DIR"

# Remove files left by interrupted runs after 12 hours.
find "$BACKUP_DIR" \
  -mindepth 1 \
  -maxdepth 1 \
  -type d \
  -name 'tmp-*' \
  -mmin +720 \
  -exec rm -rf -- {} +

find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'n8n+ragdb+config-*.tar' \
  -mmin +720 \
  -delete

find "$BACKUP_DIR" \
  -maxdepth 1 \
  -type f \
  -name 'verify-*.gpg' \
  -mmin +720 \
  -delete

docker exec "$POSTGRES_CONTAINER" rm -f \
  /tmp/ragdb.dump \
  /tmp/n8n_db.dump \
  /tmp/postgres-globals.sql \
  >/dev/null 2>&1 || true

exec >>"$LOGFILE" 2>&1

echo "[$(date)] Starting application and infrastructure backup"

WORK_DIR="$BACKUP_DIR/tmp-$TS"
mkdir -p "$WORK_DIR"

########################################
# 1) Dump the RAG database
########################################

docker exec "$POSTGRES_CONTAINER" pg_dump \
  -U "$RAG_DB_USER" \
  -d "$RAG_DB_NAME" \
  --format=custom \
  --file=/tmp/ragdb.dump

docker exec "$POSTGRES_CONTAINER" pg_restore \
  --list /tmp/ragdb.dump >/dev/null

docker cp \
  "$POSTGRES_CONTAINER:/tmp/ragdb.dump" \
  "$WORK_DIR/ragdb.dump"

docker exec "$POSTGRES_CONTAINER" rm /tmp/ragdb.dump

########################################
# 2) Dump the n8n database and roles
########################################

docker exec "$POSTGRES_CONTAINER" pg_dump \
  -U "$N8N_DB_USER" \
  -d "$N8N_DB_NAME" \
  --format=custom \
  --file=/tmp/n8n_db.dump

docker exec "$POSTGRES_CONTAINER" pg_restore \
  --list /tmp/n8n_db.dump >/dev/null

docker cp \
  "$POSTGRES_CONTAINER:/tmp/n8n_db.dump" \
  "$WORK_DIR/n8n_db.dump"

docker exec "$POSTGRES_CONTAINER" rm /tmp/n8n_db.dump

docker exec "$POSTGRES_CONTAINER" pg_dumpall \
  -U "$RAG_DB_USER" \
  --globals-only \
  --file=/tmp/postgres-globals.sql

docker cp \
  "$POSTGRES_CONTAINER:/tmp/postgres-globals.sql" \
  "$WORK_DIR/postgres-globals.sql"

docker exec "$POSTGRES_CONTAINER" rm /tmp/postgres-globals.sql

test -s "$WORK_DIR/postgres-globals.sql"

echo "[$(date)] Database dumps and globals completed"

########################################
# 3) Export n8n workflows as JSON
########################################

docker exec "$N8N_CONTAINER" sh -c '
rm -rf /tmp/n8n-cli /tmp/workflow-export &&
mkdir -p /tmp/workflow-export &&
N8N_USER_FOLDER=/tmp/n8n-cli \
n8n export:workflow --backup --output=/tmp/workflow-export/
'

mkdir -p "$WORK_DIR/workflows"

docker cp \
  "$N8N_CONTAINER:/tmp/workflow-export/." \
  "$WORK_DIR/workflows/"

docker exec "$N8N_CONTAINER" rm -rf \
  /tmp/workflow-export \
  /tmp/n8n-cli

if ! find "$WORK_DIR/workflows" \
  -type f \
  -name '*.json' \
  -print -quit \
  | grep -q .; then
  echo "[$(date)] ERROR: no workflow JSON files exported"
  exit 1
fi

echo "[$(date)] n8n workflow JSON export completed"

########################################
# 4) Copy configuration and persistent files
########################################

mkdir -p \
  "$WORK_DIR/config" \
  "$WORK_DIR/n8n-data" \
  "$WORK_DIR/certs"

cp /opt/n8n/.env "$WORK_DIR/config/"
cp /opt/n8n/docker-n8n.yml "$WORK_DIR/config/"
cp /opt/ragdb/docker-ragdb.yml "$WORK_DIR/config/"
cp /opt/n8n/backup/backup.sh "$WORK_DIR/config/"

cp -a /etc/nginx "$WORK_DIR/config/nginx"
cp -a /opt/n8n/data/. "$WORK_DIR/n8n-data/"
cp -a /opt/n8n/certs/. "$WORK_DIR/certs/"

crontab -l >"$WORK_DIR/config/root-crontab.txt"

echo "[$(date)] Config and persistent files copied"

########################################
# 5) Record container image versions
########################################

docker inspect "$N8N_CONTAINER" \
  --format='{{.Config.Image}}' \
  >"$WORK_DIR/config/n8n-image.txt" || true

docker inspect "$N8N_RUNNERS_CONTAINER" \
  --format='{{.Config.Image}}' \
  >"$WORK_DIR/config/runners-image.txt" || true

docker inspect "$POSTGRES_CONTAINER" \
  --format='{{.Config.Image}}' \
  >"$WORK_DIR/config/postgres-image.txt" || true

########################################
# 6) Create and verify the TAR archive
########################################

ARCHIVE="$BACKUP_DIR/n8n+ragdb+config-$TS.tar"

tar -cf "$ARCHIVE" -C "$WORK_DIR" .
tar -tf "$ARCHIVE" >/dev/null

echo "[$(date)] Archive created and verified"

########################################
# 7) Encrypt the archive
########################################

gpg --batch --yes \
  --encrypt \
  --recipient "$GPG_KEY_ID" \
  "$ARCHIVE"

ENC_FILE="$ARCHIVE.gpg"

echo "[$(date)] Encryption complete"

########################################
# 8) Upload and verify the remote copy
########################################

LOCAL_SHA="$(sha256sum "$ENC_FILE" | awk '{print $1}')"

rclone copy "$ENC_FILE" "$REMOTE"

VERIFY_GPG_FILE="$BACKUP_DIR/verify-$TS.gpg"
rm -f "$VERIFY_GPG_FILE"

rclone copyto \
  "$REMOTE/$(basename "$ENC_FILE")" \
  "$VERIFY_GPG_FILE"

DOWNLOADED_SHA="$(sha256sum "$VERIFY_GPG_FILE" | awk '{print $1}')"

if [ "$LOCAL_SHA" != "$DOWNLOADED_SHA" ]; then
  echo "[$(date)] ERROR: remote backup hash mismatch"
  exit 1
fi

echo "[$(date)] Remote backup downloaded and SHA256 verified"

########################################
# 9) Remove local working files
########################################

rm -rf -- "$WORK_DIR"
rm -f -- "$ARCHIVE" "$ENC_FILE" "$VERIFY_GPG_FILE"

echo "[$(date)] Local cleanup completed"

########################################
# 10) Keep the newest remote backups
########################################

OLD_BACKUPS="$(
  rclone lsf "$REMOTE" --files-only \
    | grep '\.gpg$' \
    | sort \
    | head -n -"$MAX_REMOTE_BACKUPS" \
    || true
)"

if [ -n "$OLD_BACKUPS" ]; then
  echo "[$(date)] Pruning old backups"

  while read -r FILE; do
    rclone deletefile "$REMOTE/$FILE"
    echo "Deleted remote file: $FILE"
  done <<<"$OLD_BACKUPS"
fi
