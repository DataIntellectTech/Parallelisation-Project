#!/usr/bin/env bash
# start one secondary process by hand (the primary normally spawns them)
# usage: bin/startsecondary.sh <id> [config]
# secondaries don't listen on a port: each one connects to the primary, which sends it work down that connection
set -euo pipefail

# the id is required and must be a whole number, 1 or more
# ${1:-} gives "" when no argument was passed, so set -u doesn't abort before the message
ID="${1:-}"
CONFIG="${2:-config/default.env}"

if [[ ! "$ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "startsecondary: usage: bin/startsecondary.sh <id> [config], id is 1 or more" >&2
  exit 1
fi

# set -a exports every variable the file sets, so q can read them with getenv later
set -a
source "$CONFIG"
set +a

: "${PRIMARY_PORT:?startsecondary: PRIMARY_PORT is not set in $CONFIG}"
export QHOME="$KDBX_HOME"
THREADS="${THREADS:-1}"

# used for creating logs
# todo: have it create the absolute path
mkdir -p logs
LOG="logs/sec$ID.$(date -u +%Y.%m.%dD%H.%M.%S).log"

# nohup to run in the background; to run interactively just use x src/secondary.q -id <id>
nohup "$KDBX_HOME/bin/q" src/secondary.q -id "$ID" -s "$THREADS" < /dev/null >> "$LOG" 2>&1 &

echo $! > "logs/sec$ID.pid"
echo "startsecondary: id $ID, threads $THREADS, primary port $PRIMARY_PORT, config $CONFIG, pid $!, log $LOG"