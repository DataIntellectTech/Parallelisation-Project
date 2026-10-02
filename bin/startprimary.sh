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
echo "start primary: port $PRIMARY_PORT, config $CONFIG"
LOG="logs/primary.$(date -u +%Y.%m.%dD%H.%M.%S).log"

# nohup to run in backgorund if want to run interactively just use x src/primary.q
nohup "$KDBX_HOME/bin/q" src/primary.q -p "$PRIMARY_PORT" < /dev/null >> "$LOG" 2>&1 &

echo $! > logs/primary.pid
echo "startprimary: port $PRIMARY_PORT, config $CONFIG, pid $!, log $LOG"