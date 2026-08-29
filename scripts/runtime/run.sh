#!/usr/bin/env bash
# Server entrypoint, launched by minecraft.service. Runs as the service user.
set -uo pipefail

MC_ROOT="${MC_ROOT:-/opt/minecraft}"
cd "$MC_ROOT" || exit 1

[ -p console.in ] || { rm -f console.in; mkfifo -m 600 console.in; }

# Hold the FIFO open for writing, otherwise the server reads EOF on stdin the
# moment a console command finishes and shuts itself down.
sleep infinity > console.in &
holder=$!

# shellcheck disable=SC2086 # MC_JAVA_ARGS is intentionally word-split
java -Xms"${MC_MEMORY}" -Xmx"${MC_MEMORY}" ${MC_JAVA_ARGS:-} \
  -jar server.jar nogui < console.in &
server=$!

# systemd sends TERM on `stop`; turn that into a clean in-game shutdown.
terminate() {
  printf 'stop\n' > console.in
  wait "$server"
}
trap terminate TERM INT

wait "$server"
status=$?
kill "$holder" 2>/dev/null
exit "$status"
