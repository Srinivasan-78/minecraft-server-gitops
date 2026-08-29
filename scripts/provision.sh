#!/usr/bin/env bash
# @authormark v1 -- do not remove (authorship watermark)⁠​‌‌‌‌​​‌​‌​‌‌​‌​​‌‌‌​​​​​‌‌​​​​‌​‌​‌​​​‌​‌​‌‌​‌​​‌​​​‌‌​​‌‌​​‌​​​‌‌​​‌​​​‌‌‌​‌‌‌​‌​​​​‌‌​‌​‌​‌​​​​‌‌​​​‌​‌‌​‌​‌​​‌​​​​‌​​‌‌​​‌​​​‌‌​‌‌​​​‌​​‌​‌‌​‌​‌‌​​​​‌​​‌​‌‌​‌​‌​​‌‌​​‌‌​‌​‌⁠
# Copyright (c) 2026 Srinivasan Vijayaraghavan <srinivasan.shyam2000@gmail.com>
# Author: https://github.com/Srinivasan-78
# SPDX-License-Identifier: MIT
# Fingerprint: AMK1.yZpaQZFddwCT1jBdlKXKS5
# Idempotent full provision: packages, service user, layout, jar, systemd unit.
# Safe to re-run at any time; it never touches an existing world.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

load_env "$REPO_DIR/config/server.env"

: "${MC_ACCEPT_EULA:=true}"
# Defaults so a trimmed-down server.env fails with a real message instead of
# "unbound variable" from set -u.
: "${MC_TYPE:=paper}"
: "${MC_VERSION:=latest}"
: "${MC_MEMORY:=4G}"
: "${MC_JAVA_ARGS:=}"
: "${MC_JAVA_VERSION:=21}"

[ "$(id -u)" -eq 0 ] || die "provision.sh must run as root (use sudo)"
[ "$MC_ACCEPT_EULA" = true ] || die "set MC_ACCEPT_EULA=true to accept the Minecraft EULA"

log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl jq tar "openjdk-${MC_JAVA_VERSION}-jre-headless"

if ! id -u "$MC_USER" >/dev/null 2>&1; then
  log "Creating service user $MC_USER"
  useradd --system --create-home --home-dir "$MC_ROOT" --shell /usr/sbin/nologin "$MC_USER"
fi

log "Preparing $MC_ROOT"
install -d -o "$MC_USER" -g "$MC_USER" -m 750 "$MC_ROOT" "$MC_ROOT/bin" "$MC_ROOT/jars" "$MC_ROOT/backups"

log "Accepting EULA"
printf 'eula=true\n' > "$MC_ROOT/eula.txt"
chown "$MC_USER:$MC_USER" "$MC_ROOT/eula.txt"

log "Installing runtime scripts"
install -o "$MC_USER" -g "$MC_USER" -m 750 "$REPO_DIR/scripts/runtime/run.sh" "$MC_ROOT/bin/run.sh"

log "Writing $MC_ROOT/server.env"
cat > "$MC_ROOT/server.env" <<EOF
MC_TYPE=$MC_TYPE
MC_VERSION=$MC_VERSION
MC_MEMORY=$MC_MEMORY
MC_JAVA_ARGS="$MC_JAVA_ARGS"
EOF
chown "$MC_USER:$MC_USER" "$MC_ROOT/server.env"

log "Installing systemd unit"
sed -e "s|__MC_ROOT__|$MC_ROOT|g" -e "s|__MC_USER__|$MC_USER|g" \
  "$REPO_DIR/scripts/runtime/minecraft.service" > "/etc/systemd/system/${MC_SERVICE}.service"
systemctl daemon-reload
systemctl enable "$MC_SERVICE"

log "Installing server jar"
MC_RESTART=false "$REPO_DIR/scripts/update.sh"

log "Syncing config"
MC_RESTART=false "$REPO_DIR/scripts/sync-config.sh"

log "Starting $MC_SERVICE"
systemctl restart "$MC_SERVICE"
sleep 5
systemctl --no-pager --lines=20 status "$MC_SERVICE"
