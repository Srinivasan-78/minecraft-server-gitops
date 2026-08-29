#!/usr/bin/env bash
# Install (or change) the server jar. Restarts the service if it is running,
# unless MC_RESTART=false.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

load_env "$REPO_DIR/config/server.env"
: "${MC_RESTART:=true}"

need curl; need jq

# Assign first: `read ... <<<"$(...)"` reports read's status, so a failure inside
# resolve_jar_url would be swallowed and we would carry on with empty values.
jar_info="$(resolve_jar_url "$MC_TYPE" "$MC_VERSION")"
read -r resolved url <<<"$jar_info"
[ -n "$resolved" ] && [ -n "$url" ] || die "could not resolve $MC_TYPE $MC_VERSION"
target="$MC_ROOT/jars/${MC_TYPE}-${resolved}.jar"

if [ -s "$target" ]; then
  log "Jar already present: $target"
else
  log "Downloading $MC_TYPE $resolved"
  tmp="$(mktemp "$MC_ROOT/jars/.download.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL -o "$tmp" "$url"
  [ -s "$tmp" ] || die "downloaded jar is empty"
  mv "$tmp" "$target"
  trap - EXIT
fi

chown "$MC_USER:$MC_USER" "$target"
ln -sfn "$target" "$MC_ROOT/server.jar"
chown -h "$MC_USER:$MC_USER" "$MC_ROOT/server.jar"
log "Active jar: $MC_TYPE $resolved"

# Keep the unit's copy of the version in step with the repo.
if [ -f "$MC_ROOT/server.env" ]; then
  sed -i -e "s|^MC_TYPE=.*|MC_TYPE=$MC_TYPE|" \
         -e "s|^MC_VERSION=.*|MC_VERSION=$resolved|" \
         -e "s|^MC_MEMORY=.*|MC_MEMORY=$MC_MEMORY|" "$MC_ROOT/server.env"
fi

if [ "$MC_RESTART" = true ] && service_active; then
  log "Restarting $MC_SERVICE"
  systemctl restart "$MC_SERVICE"
fi
