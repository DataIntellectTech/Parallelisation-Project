#!/usr/bin/env bash
# start the master process
# usage: bin/startMaster.sh config/default.env

# failure protection
set -euo pipefail

# defaults to default.env if nothing is passed
CONFIG="${1:-config/default.env}"


# set -a exports all variables set from this point
set -a
source "$CONFIG"
set +a

: "${MASTER_PORT:?startMaster: MASTER_PORT is not set in $CONFIG}"

echo "startMaster: port $MASTER_PORT, config $CONFIG"
exec q src/master.q -p "$MASTER_PORT"