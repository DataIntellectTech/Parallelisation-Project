#!/usr/bin/env bash
# start the PRIMARY process
# usage: bin/startprimary.sh config/default.env

# failure protection
set -euo pipefail

# defaults to default.env if nothing is passed
CONFIG="${1:-config/default.env}"

# set -a exports all variables set from this point
set -a
source "$CONFIG"
set +a

: "${PRIMARY_PORT:?startPRIMARY: PRIMARY_PORT is not set in $CONFIG}"
export QHOME="$KDBX_HOME"

# used for creating logs
# todo: have it create the absolute path
mkdir -p logs
LOG="logs/primary.$(date -u +%Y.%m.%dD%H.%M.%S).log"

# Claude
# the command, wrapped in systemd-run when starting under a cgroup
USE_CGROUP="${USE_CGROUP:-1}"
CMD=("$KDBX_HOME/bin/q" src/primary.q -p "$PRIMARY_PORT")
if [[ "$USE_CGROUP" == 1 && -n "${GLOBAL_MEM_LIMIT:-}" ]]; then
  if ! systemctl --user show-environment > /dev/null 2>&1; then   # checks if there is a systemd user manager so we can create a cgroup
    echo "startprimary: USE_CGROUP=1 but there's no systemd user session to make a cgroup in; set USE_CGROUP=0 to start without the memory cap" >&2
    exit 1
  fi
  # --scope runs the command itself in a new cgroup; MemorySwapMax=0 means kill rather than swap; --quiet keeps systemd-run's own message out of the log
  CMD=(systemd-run --user --scope --quiet -p MemoryMax="$GLOBAL_MEM_LIMIT" -p MemorySwapMax=0 "${CMD[@]}")
  CAP="memory cap $GLOBAL_MEM_LIMIT bytes"
else
  CAP="no memory cap"
fi

# nohup to run in backgorund if want to run interactively just use x src/primary.q
nohup "${CMD[@]}" < /dev/null >> "$LOG" 2>&1 &

echo $! > logs/primary.pid
echo "startprimary: port $PRIMARY_PORT, $CAP, config $CONFIG, pid $!, log $LOG"