#!/usr/bin/env bash
# Push config/ from the repo to the server. The repo is the source of truth for
# these files; anything edited in-game (ops, whitelist) is overwritten.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

: "${MC_RESTART:=true}"

FILES=(server.properties ops.json whitelist.json banned-players.json)
changed=false

# The committed samples ship a placeholder UUID. Pushing it would whitelist
# nobody and op nobody, so refuse until it is replaced with real values.
need jq
for f in ops.json whitelist.json banned-players.json; do
  src="$REPO_DIR/config/$f"
  [ -f "$src" ] || continue
  jq -e . "$src" >/dev/null || die "$f is not valid JSON"
  if jq -e 'any(.[]; .uuid == "00000000-0000-0000-0000-000000000000")' "$src" >/dev/null; then
    die "$f still contains the placeholder UUID; replace it with real player UUIDs or use an empty list []"
  fi
done

for f in "${FILES[@]}"; do
  src="$REPO_DIR/config/$f"
  [ -f "$src" ] || continue
  if ! cmp -s "$src" "$MC_ROOT/$f"; then
    log "Updating $f"
    install -o "$MC_USER" -g "$MC_USER" -m 640 "$src" "$MC_ROOT/$f"
    changed=true
  fi
done

if [ "$changed" = false ]; then
  log "Config already up to date"
  exit 0
fi

if [ "$MC_RESTART" = true ] && service_active; then
  # Player lists reload live; server.properties needs a restart.
  mc_console "whitelist reload"
  mc_console "reload permissions"
  log "Restarting $MC_SERVICE to apply server.properties"
  systemctl restart "$MC_SERVICE"
fi
