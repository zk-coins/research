#!/usr/bin/env bash
# Reproducibility runner for P10 Capability Discipline (Phase-2 unbounded proof).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# property.tla EXTENDS module/Access.tla (which EXTENDS Foundations and
# Assumptions). Apalache resolves EXTENDS only from the spec's own directory,
# so this runner stages property.tla together with the three module files in a
# scratch dir and runs there -- the module files are NOT duplicated into the
# committed property directory (same pattern as module/verify-modules.sh).
#
# The unbounded proof is the conjunction of checks [2]+[3]+[4]:
#   [2] base        AcInit             => IndInv_P10
#   [3] step        IndInv_P10 /\ AcNext => IndInv_P10'
#   [4] implication IndInv_P10         => INV_P10
# [1] is a bounded reachability sanity pass. The negative control that shows the
# chan_bind guard is load-bearing -- deleting the ChanBindMatches conjunct(s) so
# a ForeignHost-bound proof releases and AcNoReplayAcrossHosts breaks -- is run
# out of band and recorded in notes.md / certificate.txt (it must FIND a trace =
# expected Error).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MOD="$HERE/../../module"
SPEC=property.tla

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$MOD/Foundations.tla" "$MOD/Assumptions.tla" "$MOD/Access.tla" "$STAGE/"
cp "$HERE/$SPEC" "$STAGE/"
cd "$STAGE"

PASS=0; FAIL=0
run_expect_ok () { # <label> <args...>
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  echo "$out"
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "World: Access.AcConstInit (2 hosts, 2 subjects, 2 pubkeys, 3 records); the"
echo "inductive argument is per-request local and uniform in the world size"
echo "(notes.md records a larger-world confirmation)."
echo

run_expect_ok "[1] bounded sanity  AcInit/AcNext |= IndInv_P10 (length 6)" --cinit=P10ConstInit --init=AcInit --next=AcNext --inv=IndInv_P10 --length=6
run_expect_ok "[2] inductive BASE   AcInit => IndInv_P10 (length 0)"         --cinit=P10ConstInit --init=AcInit --next=AcNext --inv=IndInv_P10 --length=0
run_expect_ok "[3] inductive STEP   IndInv_P10 /\\ AcNext => IndInv_P10' (length 1)" --cinit=P10ConstInit --init=IndInvInit_P10 --next=AcNext --inv=IndInv_P10 --length=1
run_expect_ok "[4] IMPLICATION      IndInv_P10 => INV_P10 (length 0)"        --cinit=P10ConstInit --init=IndInvInit_P10 --next=AcNext --inv=INV_P10 --length=0

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
[ "$FAIL" -eq 0 ] && echo "P10 CapabilityDiscipline: VERIFIED (unbounded, inductive)." || echo "P10: FAILURE."
exit "$FAIL"
