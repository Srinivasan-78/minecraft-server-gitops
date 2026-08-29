#!/usr/bin/env bash
# Short health report, printed at the end of every workflow.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

{
  # is-active prints the state *and* exits non-zero when it is not running, so
  # `|| echo unknown` would emit two lines and break the table.
  state="$(systemctl is-active "$MC_SERVICE" 2>/dev/null || true)"
  port="$(grep -m1 '^server-port=' "$MC_ROOT/server.properties" 2>/dev/null | cut -d= -f2 || true)"

  printf '### Minecraft server\n\n'
  printf '| Field | Value |\n|---|---|\n'
  printf '| Unit | `%s` |\n' "$MC_SERVICE"
  printf '| State | %s |\n' "${state:-unknown}"
  if [ -f "$MC_ROOT/server.env" ]; then
    printf '| Build | %s %s |\n' \
      "$(grep -m1 '^MC_TYPE=' "$MC_ROOT/server.env" | cut -d= -f2)" \
      "$(grep -m1 '^MC_VERSION=' "$MC_ROOT/server.env" | cut -d= -f2)"
  fi
  printf '| Port | %s |\n' "${port:-n/a}"
  printf '| World size | %s |\n' "$(du -sh "$MC_ROOT/world" 2>/dev/null | cut -f1 || echo n/a)"
}

# Fenced: this is appended to $GITHUB_STEP_SUMMARY, where unfenced log lines
# would be reflowed into one unreadable paragraph.
echo
echo "Recent log:"
echo '```'
journalctl -u "$MC_SERVICE" -n 15 --no-pager 2>/dev/null || true
echo '```'
