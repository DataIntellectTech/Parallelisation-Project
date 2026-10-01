#!/usr/bin/env bash
# start one secondary process
# bin/startSecondary.sh 1 default: config/default.env
# id is 1, 2, 3 ... and decides the port: SECONDARY_BASE_PORT + id - 1
set -euo pipefail


# the id is required and must be a whole number, 1 or more
# ${1:-} gives "" when no argument was passed, so set -u doesn't abort before the message
ID="${1:-}"

CONFIG="${2:-config/default.env}"


# set -a exports every variable the file sets, so q can read them with getenv later
set -a
source "$CONFIG"
set +a

: "${SECONDARY_BASE_PORT:?startSecondary: SECONDARY_BASE_PORT is not set in $CONFIG}"

# secondary 1 gets the base port, secondary 2 the next one up, and so on
PORT=$(( SECONDARY_BASE_PORT + ID - 1 ))

echo "startSecondary: id $ID, port $PORT, config $CONFIG"
exec q src/secondary.q -p "$PORT" -id "$ID"