#!/usr/bin/env bash
# Reproducibility runner for P02 No-Double-Spend (Phase-0 unbounded proof).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# The unbounded proof is the conjunction of checks [2]+[3]+[4]:
#   [2] base       Init    => IndInv
#   [3] step       IndInv  /\ Next => IndInv'
#   [4] implication IndInv => NoDoubleSpend
# [1] is a bounded reachability sanity pass; [5] is the negative control that
# shows the first-spend-wins gate is load-bearing (must FAIL = find a trace).
set -u
cd "$(dirname "$0")"

SPEC=property.tla
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
echo "Universe: Nullifier = 1..6 (ConstInit); inductive argument is uniform in |Nullifier| (notes.md records a |Nullifier|=12 confirmation)."
echo

run_expect_ok "[1] bounded sanity  Init/Next |= IndInv (length 12)" --cinit=ConstInit --init=Init --next=Next --inv=IndInv --length=12
run_expect_ok "[2] inductive BASE   Init => IndInv (length 0)"        --cinit=ConstInit --init=Init --inv=IndInv --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ Next => IndInv' (length 1)" --cinit=ConstInit --init=IndInvInit --next=Next --inv=IndInv --length=1
run_expect_ok "[4] IMPLICATION      IndInv => NoDoubleSpend (length 0)"    --cinit=ConstInit --init=IndInvInit --inv=NoDoubleSpend --length=0

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
[ "$FAIL" -eq 0 ] && echo "P02 NoDoubleSpend: VERIFIED (unbounded, inductive)." || echo "P02: FAILURE."
exit "$FAIL"
