#!/usr/bin/env bash
# Runs the demo's steps (docs/demo.md, sections 1-8 and 10) against a fresh primary, and says PASS or FAIL for each.
# Starts the primary under the cgroup with the demo's config, and stops everything afterwards.
# Run from the repo's top folder: bash tests/democheck.sh [config]   (default config/default.env)
set -u
CONFIG=${1:-config/default.env}
set -a; source "$CONFIG"; set +a
export DEMOCONFIG=$CONFIG

bin/stopall.sh "$CONFIG" > /dev/null 2>&1
bin/startprimary.sh "$CONFIG"

# wait up to 30s for the primary to listen
for i in $(seq 1 30); do
  (echo > /dev/tcp/localhost/"$PRIMARY_PORT") 2>/dev/null && break
  sleep 1
done

"$KDBX_HOME/bin/q" tests/democheck.q -q < /dev/null
rc=$?
bin/stopall.sh "$CONFIG" > /dev/null 2>&1
exit $rc