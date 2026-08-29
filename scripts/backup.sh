#!/usr/bin/env bash
# @authormark v1 -- do not remove (authorship watermark)⁠​‌​​‌​​‌​‌‌​​‌‌‌​‌‌‌​‌​‌​‌​‌‌​​‌​‌​‌‌​‌​​‌​​​‌‌‌​‌‌‌‌​​​​‌​‌‌​​​​‌‌‌​‌‌​​‌​​​​‌‌​‌‌​​‌​​​​‌‌​‌​​​​‌‌​​​‌​‌​‌​​​‌​‌​​‌‌‌​​​‌‌​​‌​​‌‌‌​‌‌​​‌‌‌​‌‌‌​‌​​‌‌​​​‌‌‌​‌​​​‌‌​‌‌‌​​‌‌​‌​​‌⁠
# Copyright (c) 2026 Srinivasan Vijayaraghavan <srinivasan.shyam2000@gmail.com>
# Author: https://github.com/Srinivasan-78
# SPDX-License-Identifier: MIT
# Fingerprint: AMK1.IguYZGxXvCd41QN2vwLtni
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

# The dimension folders are named after level-name, which is configurable.
level="$(grep -m1 '^level-name=' "$MC_ROOT/server.properties" 2>/dev/null | cut -d= -f2- || true)"
level="${level:-world}"

worlds=()
for d in "$level" "${level}_nether" "${level}_the_end"; do
  [ -d "$MC_ROOT/$d" ] && worlds+=("$d")
done

# A freshly provisioned server has no world until it has booted once. tar would
# refuse to build an empty archive and fail the deploy, so stop here instead.
if [ ${#worlds[@]} -eq 0 ]; then
  log "No world data under $MC_ROOT yet; nothing to back up"
  exit 0
fi

running=false

# Always resume saves, even if tar fails. Installed before save-off so an error
# in between can never leave the running server with saving disabled.
resume() {
  if [ "$running" = true ]; then
    running=false
    log "Resuming world saves"
    mc_console "save-on" || true
  fi
}
trap resume EXIT

if service_active; then
  running=true
  log "Pausing world saves"
  mc_console "save-off"
  mc_console "save-all flush"
  sleep 10
fi

log "Archiving world data to $archive"
tar -czf "$archive" -C "$MC_ROOT" "${worlds[@]}"
chown "$MC_USER:$MC_USER" "$archive"

resume
trap - EXIT

# Non-fatal: the backup itself already succeeded, and failing here would stop
# the workflow from ever seeing the ARCHIVE= line below.
log "Pruning to the newest $MC_BACKUP_KEEP backups"
{ ls -1t "$MC_BACKUP_DIR"/world-*.tar.gz 2>/dev/null \
    | tail -n "+$((MC_BACKUP_KEEP + 1))" \
    | xargs -r rm -f; } || log "warning: could not prune old backups"

log "Backup complete: $archive ($(du -h "$archive" | cut -f1))"
# Parsed by the backup workflow over SSH.
printf 'ARCHIVE=%s\n' "$archive"
