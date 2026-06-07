#!/usr/bin/env bash
# Reproducibility runner for P01 No-Forgery.
#
# property.tla EXTENDS module/Proofs.tla, which EXTENDS Foundations + Assumptions.
# Apalache resolves EXTENDS from the spec's own directory, so the checks are
# staged into a temp dir holding those four modules together; nothing but
# property.tla / verify.sh / certificate.txt / notes.md is committed here.
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# TWO-TIER result (see notes.md):
#   TIER 1 -- INV_Provenance, the structural no-forgery core, proven UNBOUNDED
#     by the inductive conjunction [2]+[3]+[4]:
#       [2] base        PrInit  => IndInv
#       [3] step        IndInv  /\ PrNext => IndInv'
#       [4] implication IndInv  => INV_Provenance
#     INV_Provenance is prAuthorised-free, so its induction is sound for the
#     genuinely unbounded reachable space (|prAuthorised| grows without bound).
#   TIER 2 -- INV_NoForgery, the full signature-level statement, proven BOUNDED
#     safety [5] (length 6). Its unbounded extension reduces to TIER 1 + the
#     model's honest-oracle lockstep (notes.md).
# [1] is a bounded reachability/safety sanity pass. [0] is the vacuity probe:
# coins really do get credited (~NoCoinsEver is VIOLATED at depth), so the
# invariants are not vacuously true. The negative control that shows the
# honest-signing oracle is load-bearing is recorded in notes.md (run in a
# /tmp copy so this committed model keeps the honest A7 oracle intact).
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

run_expect_violation () { # <label> <args...>   (a vacuity probe: must FAIL)
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  if echo "$out" | grep -q "The outcome is: Error"; then
    echo ">>> $label: VIOLATED as expected (coins are credited -- invariant non-vacuous)"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -3
    echo ">>> $label: UNEXPECTED (expected a violation)"; FAIL=$((FAIL+1))
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

run_expect_violation "[0] vacuity probe   ~NoCoinsEver must be VIOLATED (len 3)"        --cinit=ConstInit --init=PrInit     --next=PrNext --inv=NoCoinsEver     --length=3
run_expect_ok "[1] bounded sanity  PrInit/PrNext |= IndInv (length 6)"           --cinit=ConstInit --init=PrInit     --next=PrNext --inv=IndInv         --length=6
run_expect_ok "[2] inductive BASE   PrInit => IndInv (length 0)"                 --cinit=ConstInit --init=PrInit     --next=PrNext --inv=IndInv         --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ PrNext => IndInv' (len 1)"         --cinit=ConstInit --init=IndInvInit --next=PrNext --inv=IndInv         --length=1
run_expect_ok "[4] IMPLICATION      IndInv => INV_Provenance (length 0)"         --cinit=ConstInit --init=IndInvInit --next=PrNext --inv=INV_Provenance --length=0
run_expect_ok "[5] TIER-2 SAFETY    PrInit/PrNext |= INV_NoForgery (length 6)"   --cinit=ConstInit --init=PrInit     --next=PrNext --inv=INV_NoForgery   --length=6

cd "$HERE"
rm -rf "$STAGE"
rm -rf "$HERE/_apalache-out"

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P01 NoForgery: VERIFIED."
  echo "  TIER 1 (structural provenance): UNBOUNDED  [2]+[3]+[4]"
  echo "  TIER 2 (signature-level):       BOUNDED safety [5] (unbounded extension via TIER 1 + honest oracle; notes.md)"
  echo "  bounded sanity [1]; vacuity probe [0]."
else
  echo "P01: FAILURE."
fi
exit "$FAIL"
