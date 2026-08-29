#!/usr/bin/env bash
# @authormark v1 -- do not remove (authorship watermark)⁠​‌​‌​‌‌​​‌​​‌​‌​​‌​​‌​​​​‌‌​‌‌​‌​‌‌​‌​‌​​‌‌‌‌​​‌​‌‌​​‌‌​​‌​​​​​‌​​‌‌​​‌​​‌​​‌​​​​‌​‌​‌‌‌​‌​​‌​‌​​‌‌‌​​‌​​‌‌​‌‌​​​‌​‌‌​‌​​‌‌​‌​​‌​‌​​​‌​​​​‌‌​​​‌​‌​​‌‌‌​​​‌‌​​​​​‌‌​​‌‌‌​‌​‌​‌‌‌⁠
# Copyright (c) 2026 Srinivasan Vijayaraghavan <srinivasan.shyam2000@gmail.com>
# Author: https://github.com/Srinivasan-78
# SPDX-License-Identifier: MIT
# Fingerprint: AMK1.VJHmjyfA2HWJrlZiD1N0gW
# Shared helpers. Sourced by the other scripts; not executed directly.

MC_ROOT="${MC_ROOT:-/opt/minecraft}"
MC_USER="${MC_USER:-minecraft}"
MC_SERVICE="${MC_SERVICE:-minecraft}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# Load the repo's server definition, letting already-exported values win so
# workflow inputs can override the committed defaults.
load_env() {
  local file="${1:?env file required}"
  [ -f "$file" ] || die "missing env file: $file"
  local line key value
  # `|| [ -n "$line" ]` so a final line without a trailing newline is not lost.
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    case "$key" in ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;; esac
    value="${line#*=}"
    # Strip one layer of surrounding quotes.
    value="${value%\"}"; value="${value#\"}"
    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$file"
}

# resolve_jar_url <vanilla|paper> <version|latest>
# Prints "<resolved_version> <url>".
resolve_jar_url() {
  local type="$1" version="$2" url resolved

  case "$type" in
    vanilla)
      local manifest meta_url
      manifest="$(curl -fsSL https://launchermeta.mojang.com/mc/game/version_manifest_v2.json)" \
        || die "could not fetch Mojang version manifest"
      if [ "$version" = latest ]; then
        resolved="$(printf '%s' "$manifest" | jq -r '.latest.release')"
      else
        resolved="$version"
      fi
      meta_url="$(printf '%s' "$manifest" | jq -r --arg v "$resolved" \
        '.versions[] | select(.id == $v) | .url')"
      [ -n "$meta_url" ] && [ "$meta_url" != null ] \
        || die "unknown Minecraft version: $resolved"
      url="$(curl -fsSL "$meta_url" | jq -r '.downloads.server.url')"
      ;;
    paper)
      if [ "$version" = latest ]; then
        # .versions is {"1.21": ["1.21.11", "1.21.11-rc3", ...], ...}, newest
        # first; skip pre-releases and release candidates.
        resolved="$(curl -fsSL https://fill.papermc.io/v3/projects/paper \
          | jq -r '[.versions[][] | select(test("-") | not)] | first')" \
          || die "could not fetch Paper version list"
      else
        resolved="$version"
      fi
      url="$(curl -fsSL "https://fill.papermc.io/v3/projects/paper/versions/${resolved}/builds" \
        | jq -r '([.[] | select(.channel == "STABLE")] | first // .[0])
                 | .downloads["server:default"].url')" \
        || die "no Paper build for $resolved"
      ;;
    *)
      die "unsupported server type: $type (expected vanilla or paper)"
      ;;
  esac

  [ -n "$url" ] && [ "$url" != null ] || die "could not resolve a jar URL for $type $version"
  printf '%s %s\n' "$resolved" "$url"
}

# service_active -> 0 when the unit is running
service_active() {
  systemctl is-active --quiet "$MC_SERVICE"
}

# Send a console command to the running server through its stdin FIFO.
# Opening a FIFO for writing blocks until something is reading it, so a server
# that died without tearing down the FIFO would hang the caller forever. Cap it.
mc_console() {
  [ -p "$MC_ROOT/console.in" ] || die "console FIFO missing; is the server installed?"
  printf '%s\n' "$*" \
    | timeout -k 2 10 sudo -u "$MC_USER" tee "$MC_ROOT/console.in" >/dev/null \
    || die "timed out sending console command: $*"
}
