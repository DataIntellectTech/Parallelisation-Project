#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ $# -eq 0 ]]; then
  echo "usage: tests/run.sh <spec file or folder> [qspec flags]" >&2
  echo "  e.g. tests/run.sh tests/unit" >&2
  exit 2
fi

set -a
source config/default.env
set +a

export QHOME="$KDBX_HOME"
export QPATH="$ROOT/tests:/opt/kdbx/mod:/home/jrutledge/x/kdbx-modules-main"

"$KDBX_HOME/bin/q" tests/runspecs.q -q "$@"
