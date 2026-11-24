#!/usr/bin/env bash
# Sync an S3 prefix locally, compress it, and publish it to the Nginx web root.
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET is required}"
S3_PREFIX="${S3_PREFIX:-}"
WORK_DIR="${WORK_DIR:-/tmp/s3-sync}"
WEB_ROOT="${WEB_ROOT:-/usr/share/nginx/html}"
SYNC_INTERVAL="${SYNC_INTERVAL:-300}"
ARCHIVE_NAME="${ARCHIVE_NAME:-archive.tar.gz}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

write_status() {
  local result="$1" size="$2" files="$3"
  local tmp="$WEB_ROOT/.status.json.tmp"
  cat >"$tmp" <<EOF
{"last_run":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","result":"$result","archive":"$ARCHIVE_NAME","size_bytes":$size,"file_count":$files,"source":"s3://$S3_BUCKET/$S3_PREFIX"}
EOF
  mv "$tmp" "$WEB_ROOT/status.json"
}

# NOTE: called from an `if`, where `set -e` is disabled, so errors use `|| return 1`.
sync_once() {
  mkdir -p "$WORK_DIR/data"
  log "Syncing s3://$S3_BUCKET/$S3_PREFIX"
  aws s3 sync "s3://$S3_BUCKET/$S3_PREFIX" "$WORK_DIR/data" --delete --only-show-errors || return 1

  local tmp="$WORK_DIR/$ARCHIVE_NAME.tmp"
  tar -czf "$tmp" -C "$WORK_DIR/data" . || return 1
  mv "$tmp" "$WEB_ROOT/$ARCHIVE_NAME" || return 1

  local size files
  size=$(stat -c %s "$WEB_ROOT/$ARCHIVE_NAME")
  files=$(find "$WORK_DIR/data" -type f | wc -l)
  write_status success "$size" "$files"
  log "Published $ARCHIVE_NAME ($size bytes, $files files)"
}

run_once() {
  if ! sync_once; then
    log "Sync failed"
    write_status failure 0 0
    return 1
  fi
}

case "${1:-loop}" in
  once) run_once ;;
  loop)
    while true; do
      run_once || true
      sleep "$SYNC_INTERVAL"
    done
    ;;
  *) echo "usage: $0 [once|loop]" >&2; exit 2 ;;
esac
