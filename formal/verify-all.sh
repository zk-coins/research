#!/usr/bin/env bash
# Reproduce the entire zkCoins 100% verification from a clean clone, one command.
#
# Prerequisite: apalache-mc on PATH (pinned: Apalache 0.58.0, Z3 4.14.1.0 --
# see any property/*/notes.md). No other dependency.
# Usage:  formal/verify-all.sh
#
# Runs, in order:
#   1. the Phase-1 module gate (8 modules type-check; 5 state machines smoke;
#      a composition smoke proves they EXTEND together) -- module/verify-modules.sh
#   2. every per-property certificate runner property/Pnn_*/verify.sh
# Exits non-zero if any stage fails.
set -u
cd "$(dirname "$0")"

FAIL=0

echo "############################################################"
echo "# 1. Module gate (Phase 1)"
echo "############################################################"
if ( cd module && ./verify-modules.sh ); then
  echo ">>> module gate: OK"
else
  echo ">>> module gate: FAIL"; FAIL=$((FAIL+1))
fi
echo

echo "############################################################"
echo "# 2. Property certificates (Phases 0/2/3)"
echo "############################################################"
for d in property/P*/; do
  [ -x "$d/verify.sh" ] || continue
  name="$(basename "$d")"
  echo "----- $name -----"
  if ( cd "$d" && ./verify.sh >/dev/null 2>&1 ); then
    echo ">>> $name: VERIFIED"
  else
    echo ">>> $name: FAIL"; FAIL=$((FAIL+1))
  fi
done

echo
echo "============================================================"
if [ "$FAIL" -eq 0 ]; then
  echo "100% VERIFICATION: ALL GREEN -- module gate + all property certificates reproduce."
else
  echo "VERIFICATION: $FAIL stage(s) FAILED."
fi
exit "$FAIL"
