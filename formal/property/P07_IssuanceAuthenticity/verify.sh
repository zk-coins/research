#!/usr/bin/env bash
# Reproducibility runner for P07 Issuance Authenticity (v1), unbounded proof.
#
# property.tla EXTENDS module/Proofs.tla, which EXTENDS Foundations + Assumptions.
# Apalache resolves EXTENDS from the spec's own directory, so the checks are
# staged into a temp dir holding those four modules together; nothing but
# property.tla / verify.sh / certificate.txt / notes.md is committed here.
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# The unbounded proof is the conjunction of checks [2]+[3]+[4]:
#   [2] base        PrInit  => IndInv
#   [3] step        IndInv  /\ PrNext => IndInv'
#   [4] implication IndInv  => INV_P7
# [1] is a bounded reachability sanity pass. The negative control that shows the
# §6.5 (b)/(c) mint clauses are load-bearing is recorded in notes.md (run in a
# /tmp copy so this committed model keeps MintV1Clauses intact).
# Exit status = total unexpected outcomes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MODDIR="$HERE/../../module"
PASS=0; FAIL=0

run_expect_ok () { # <label> <args...>
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE|error" | head -3
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "Universe: Accounts = {1,2}, one v1 asset family (PrConstInit via ConstInit);"
echo "inductive argument is per-account local (notes.md records the |Accounts|=3 base/impl confirmation)."
echo

STAGE="$(mktemp -d)"
cp "$MODDIR/Foundations.tla" "$MODDIR/Assumptions.tla" "$MODDIR/Proofs.tla" \
   "$HERE/property.tla" "$STAGE/"
cd "$STAGE"
SPEC=property.tla

run_expect_ok "[1] bounded sanity  PrInit/PrNext |= IndInv (length 6)"     --cinit=ConstInit --init=PrInit     --next=PrNext --inv=IndInv  --length=6
run_expect_ok "[2] inductive BASE   PrInit => IndInv (length 0)"           --cinit=ConstInit --init=PrInit     --next=PrNext --inv=IndInv  --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ PrNext => IndInv' (len 1)"   --cinit=ConstInit --init=IndInvInit --next=PrNext --inv=IndInv  --length=1
run_expect_ok "[4] IMPLICATION      IndInv => INV_P7 (length 0)"           --cinit=ConstInit --init=IndInvInit --next=PrNext --inv=INV_P7  --length=0

cd "$HERE"
rm -rf "$STAGE"
rm -rf "$HERE/_apalache-out"

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P07 IssuanceAuthenticity: VERIFIED (unbounded, inductive)."
  echo "  unbounded issuance authenticity: [2]+[3]+[4]; bounded sanity [1]."
else
  echo "P07: FAILURE."
fi
exit "$FAIL"
