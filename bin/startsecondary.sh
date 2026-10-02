#!/usr/bin/env bash
# start one secondary process
# bin/startsecondary.sh 1 default: config/default.env
# id is 1, 2, 3 ... and decides the port: SECONDARY_BASE_PORT + id - 1
set -euo pipefail


# the id is required and must be a whole number, 1 or more
# ${1:-} gives "" when no argument was passed, so set -u doesn't abort before the message
ID="${1:-}"
CONFIG="${2:-config/default.env}"

# if no id provided exit
if [[ ! "$ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "no id provided usage example: bash bin/startsecondary.sh <id>" >&2
  exit 1
fi

# set -a exports every variable the file sets, so q can read them with getenv later
set -a
source "$CONFIG"
set +a

: "${SECONDARY_BASE_PORT:?startsecondary: SECONDARY_BASE_PORT is not set in $CONFIG}"

# secondary 1 gets the base port, secondary 2 the next one up and so on
PORT=$(( SECONDARY_BASE_PORT + ID - 1 ))
export QHOME="$KDBX_HOME"

# used for creating logs
# todo: have it create the absolute path
mkdir -p logs
LOG="logs/sec$ID.$(date -u +%Y.%m.%dD%H.%M.%S).log"

# nohup to run in bbackgorund if want to run interactively just use x src/primary.q
nohup "$KDBX_HOME/bin/q" src/secondary.q -p "$PORT" -id "$ID" < /dev/null >> "$LOG" 2>&1 &

echo $! > "logs/sec$ID.pid"
echo "start secondary: id $ID, port $PORT, config $CONFIG, pid $!, log $LOG"
