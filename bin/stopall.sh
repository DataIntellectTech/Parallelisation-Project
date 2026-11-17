#!/usr/bin/env bash

# Claude
# stop the primary and every secondary started with one config

# forces script to exit as soon a the command fails, or an unset variable is used, or a pipe fails
set -euo pipefail

CONFIG="${1:-config/default.env}"

# set -a exports every variable the file sets, so q can read them with getenv
set -a
source "$CONFIG"
set +a

# this user's primary and secondary processes for this config: PRIMARY_PORT in their environment,
# or, for a primary started without the config loaded, -p PRIMARY_PORT on its command line
ourpids() {
  for pid in $(pgrep -u "$USER" -f 'src/(primary|secondary)\.q' || true); do
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qx "PRIMARY_PORT=$PRIMARY_PORT" \
      || tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q -- "-p $PRIMARY_PORT "; then
      echo "$pid"
    fi
  done
}

before=$(ourpids)
if [[ -z "$before" ]]; then
  echo "stopall: nothing running for PRIMARY_PORT $PRIMARY_PORT"
  exit 0
fi
echo "stopall: running for PRIMARY_PORT $PRIMARY_PORT: pids $(echo $before)"

# 1. ask the primary to exit (2s to connect); if it isn't there or doesn't answer, go straight to the wait and kill
"$KDBX_HOME/bin/q" -q <<'EOF' || true
h:@[hopen; (`$"::",getenv`PRIMARY_PORT; 2000); 0Ni];
if[null h; -1 "stopall: could not connect to the primary, will kill instead"; exit 1];
-1 "stopall: asking the primary to exit";
neg[h]"exit 0"; neg[h][];
exit 0
EOF

# 2. wait for everything to exit: the primary's own grace period, plus 5s
wait=$(( ${STOP_GRACE_PERIOD_SECS:-5} + 5 ))
for ((i=0; i<wait; i++)); do
  [[ -z "$(ourpids)" ]] && { echo "stopall: all stopped"; exit 0; }
  sleep 1
done

# 3. anything still running: kill, then kill -9
left=$(ourpids)
echo "stopall: still running after ${wait}s, killing: pids $(echo $left)"
kill $left 2>/dev/null || true
sleep 2
left=$(ourpids)
if [[ -n "$left" ]]; then
  echo "stopall: killing with -9: pids $(echo $left)"
  kill -9 $left 2>/dev/null || true
fi
echo "stopall: all stopped"