#!/usr/bin/env bash
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
  local key value
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"
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
mc_console() {
  [ -p "$MC_ROOT/console.in" ] || die "console FIFO missing; is the server installed?"
  printf '%s\n' "$*" | sudo -u "$MC_USER" tee "$MC_ROOT/console.in" >/dev/null
}
