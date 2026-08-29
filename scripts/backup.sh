#!/usr/bin/env bash
# Consistent world backup: pause saves, flush to disk, tar, resume.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

: "${MC_BACKUP_DIR:=$MC_ROOT/backups}"
: "${MC_BACKUP_KEEP:=7}"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$MC_BACKUP_DIR/world-$stamp.tar.gz"
install -d -o "$MC_USER" -g "$MC_USER" -m 750 "$MC_BACKUP_DIR"

running=false
if service_active; then
  running=true
  log "Pausing world saves"
  mc_console "save-off"
  mc_console "save-all flush"
  sleep 10
fi

# Always resume saves, even if tar fails.
resume() {
  if [ "$running" = true ]; then
    log "Resuming world saves"
    mc_console "save-on" || true
  fi
}
trap resume EXIT

log "Archiving world data to $archive"
tar -czf "$archive" -C "$MC_ROOT" \
  $(cd "$MC_ROOT" && ls -d world world_nether world_the_end 2>/dev/null)
chown "$MC_USER:$MC_USER" "$archive"

trap - EXIT
resume

log "Pruning to the newest $MC_BACKUP_KEEP backups"
ls -1t "$MC_BACKUP_DIR"/world-*.tar.gz 2>/dev/null \
  | tail -n "+$((MC_BACKUP_KEEP + 1))" \
  | xargs -r rm -f

log "Backup complete: $archive ($(du -h "$archive" | cut -f1))"
# Parsed by the backup workflow over SSH.
printf 'ARCHIVE=%s\n' "$archive"
