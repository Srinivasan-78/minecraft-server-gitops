#!/usr/bin/env bash
# Short health report, printed at the end of every workflow.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

{
  printf '### Minecraft server\n\n'
  printf '| Field | Value |\n|---|---|\n'
  printf '| Unit | `%s` |\n' "$MC_SERVICE"
  printf '| State | %s |\n' "$(systemctl is-active "$MC_SERVICE" 2>/dev/null || echo unknown)"
  if [ -f "$MC_ROOT/server.env" ]; then
    printf '| Build | %s %s |\n' \
      "$(grep -m1 '^MC_TYPE=' "$MC_ROOT/server.env" | cut -d= -f2)" \
      "$(grep -m1 '^MC_VERSION=' "$MC_ROOT/server.env" | cut -d= -f2)"
  fi
  printf '| Port | %s |\n' "$(grep -m1 '^server-port=' "$MC_ROOT/server.properties" 2>/dev/null | cut -d= -f2)"
  printf '| World size | %s |\n' "$(du -sh "$MC_ROOT/world" 2>/dev/null | cut -f1 || echo n/a)"
}

echo
echo "Recent log:"
journalctl -u "$MC_SERVICE" -n 15 --no-pager 2>/dev/null || true
