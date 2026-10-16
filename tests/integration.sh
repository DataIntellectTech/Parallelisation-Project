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

# kill the primary and any secondary on the test ports (46001 -> "4600", so 46000-46009 only)
stopall() {
  if [[ -n "$PRIMARYPID" ]]; then kill -9 "$PRIMARYPID" 2>/dev/null || true; fi
  pkill -9 -f "src/secondary.q -p ${SECONDARY_BASE_PORT%?}" 2>/dev/null || true
  PRIMARYPID=""
}

# used to kill any processes incase script stops early eg. CTRL+C
trap stopall EXIT

# refuse to start if something is already on the test ports
portsfree() {
  local p
  for p in $(seq "$PRIMARY_PORT" $((SECONDARY_BASE_PORT + NUM_SECONDARYS + 1))); do
    if (exec 3<>"/dev/tcp/localhost/$p") 2>/dev/null; then
      echo "port $p is already in use; kill whatever is on it (ss -ltnp | grep $p) and rerun" >&2
      return 1
    fi
  done
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
  sleep 0.5    # let the ports free up before the next cluster
done

echo
if [[ $ran -eq 0 ]]; then echo "no specs matched '$FILTER'" >&2; exit 1; fi
if [[ $rc -eq 0 ]]; then echo "integration: all $ran spec files passed"; else echo "integration: failures; logs are in $LOG_DIR"; fi
exit $rc
