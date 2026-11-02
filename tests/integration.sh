#!/usr/bin/env bash
# end to end tests
# for each tests/integration/*_spec.q: start a fresh primary (which spawns its own secondaries),
# run that spec against it with qspec, then kill everything
# usage (from anywhere): tests/integration.sh            run every spec
#                        tests/integration.sh stale      run only specs whose file name contains "stale"
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

set -a
source config/default.env
source config/integration.env
set +a
export QHOME="$KDBX_HOME"
# export QPATH="$ROOT/tests:/opt/kdbx/mod:/home/jrutledge/x/kdbx-modules-main"

Q="$KDBX_HOME/bin/q"
FILTER="${1:-}"
mkdir -p "$LOG_DIR"
PRIMARYPID=""

# kill the test primary and its secondaries
# secondaries have no port, so they're found by the PRIMARY_PORT they inherited from the test primary;
# /proc/<pid>/environ is only readable for our own processes, and any other primary's secondaries have a
# different PRIMARY_PORT, so nothing else is touched
stopall() {
  if [[ -n "$PRIMARYPID" ]]; then
    kill -9 "$PRIMARYPID" 2>/dev/null || true
    wait "$PRIMARYPID" 2>/dev/null || true      # reap it, so bash doesn't print "Killed"
  fi
  local p
  for p in $(pgrep -f "src/secondary.q"); do
    if tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "PRIMARY_PORT=$PRIMARY_PORT"; then
      kill -9 "$p" 2>/dev/null || true
    fi
  done
  PRIMARYPID=""
}

# used to kill any processes incase script stops early eg. CTRL+C
trap stopall EXIT

# refuse to start if something is already on the test primary's port (secondaries don't listen)
portsfree() {
  if (exec 3<>"/dev/tcp/localhost/$PRIMARY_PORT") 2>/dev/null; then
    echo "port $PRIMARY_PORT is already in use; kill whatever is on it (ss -ltnp | grep $PRIMARY_PORT) and rerun" >&2
    return 1
  fi
}

# start the primary in the background and wait until it is listening
startprimary() {
  "$Q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG_DIR/primary.log" 2>&1 &
  PRIMARYPID=$!
  for _ in $(seq 50); do
    if (exec 3<>"/dev/tcp/localhost/$PRIMARY_PORT") 2>/dev/null; then return 0; fi
    sleep 0.2
  done
  echo "primary never started listening; see $LOG_DIR/primary.log" >&2
  return 1
}

portsfree || exit 1

rc=0
ran=0
for spec in tests/integration/*_spec.q; do
  if [[ -n "$FILTER" && "$spec" != *"$FILTER"* ]]; then continue; fi
  ran=$((ran + 1))
  echo
  echo "== $spec"
  echo "== $(date -u +%Y.%m.%dD%H:%M:%S) $spec" >> "$LOG_DIR/primary.log"
  if ! startprimary; then rc=1; stopall; continue; fi
  if ! EXTRA_ENV=config/integration.env tests/run.sh "$spec"; then rc=1; fi
  stopall
  sleep 0.5    # let the processes exit and the primary's port free up before the next spec
done

echo
if [[ $ran -eq 0 ]]; then echo "no specs matched '$FILTER'" >&2; exit 1; fi
if [[ $rc -eq 0 ]]; then echo "integration: all $ran spec files passed"; else echo "integration: failures; logs are in $LOG_DIR"; fi
exit $rc