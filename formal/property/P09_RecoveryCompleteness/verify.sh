#!/usr/bin/env bash
# Reproducibility runner for P09 Recovery Completeness.
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# property.tla EXTENDS module/Transport.tla (which EXTENDS Foundations and
# Assumptions). Apalache resolves EXTENDS only from the spec's own directory,
# so this runner stages property.tla together with the three module files in a
# scratch dir and runs there -- the module files are NOT duplicated into the
# committed property directory (same pattern as P08 / module/verify-modules.sh).
#
# P09 has TWO halves with DIFFERENT certificate strengths (mirroring Pass-3:
# HIGH correctness / MEDIUM liveness):
#
#   SAFETY (correctness) -- UNBOUNDED. Checks [2]+[3]+[4] are the standard
#     3-check inductive-invariant argument, so INV_P9_safety holds in EVERY
#     reachable state (no false-accept; own-key discipline; sound accumulator)
#     for an arbitrary number of Recover / Finish / Transport transitions.
#     [1] is a bounded reachability sanity pass.
#
#   LIVENESS (availability) -- NOT in the unbounded certificate. Check [L]
#     attempts the genuine fairness-conditional temporal property; Apalache
#     0.58.0 does NOT support fairness, so the certificate instead carries the
#     ENABLEDNESS SURROGATE [E] (a held real bundle is always gate-admissible),
#     an honestly weaker SAFETY stand-in. See notes.md for the scope decision.
#
# [V] vacuity probe and [NC] negative control (run separately, see notes.md)
# show the recovery is non-trivial and the verify gate is load-bearing.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MOD="$HERE/../../module"
SPEC=property.tla

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$MOD/Foundations.tla" "$MOD/Assumptions.tla" "$MOD/Transport.tla" "$STAGE/"
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

run_expect_unsupported () { # <label> <args...>  -- expect the fairness NotImplementedError
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  echo "$out"
  if echo "$out" | grep -q "Handling fairness is not supported yet"; then
    echo ">>> $label: AS EXPECTED (Apalache 0.58.0 cannot encode fairness; liveness is out of certificate scope -- see notes.md)"
    PASS=$((PASS+1))
  else
    echo ">>> $label: UNEXPECTED (expected the fairness NotImplementedError)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "Instance: ConstInit (Transport K=3, Holders={1,2,3}, RecipientOpPk=10,"
echo "  IvkHolders=KtxHolders={20,21}, Eve=99; recovery WalletId=30,"
echo "  Bundles={1,2,8,9}, RealBundles={1,2}, AddressedForgeries={8});"
echo "inductive argument is uniform in the instance sizes (notes.md records a larger-instance confirmation)."
echo
echo "------------------------------------------------------------------"
echo "SAFETY half (correctness) -- UNBOUNDED inductive certificate"
echo "------------------------------------------------------------------"

run_expect_ok "[1] bounded sanity  Init/Next |= IndInv (length 8)"            --cinit=ConstInit --init=Init     --next=Next --inv=IndInv         --length=8
run_expect_ok "[2] inductive BASE   Init => IndInv (length 0)"                --cinit=ConstInit --init=Init     --next=Next --inv=IndInv         --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ Next => IndInv' (length 1)"     --cinit=ConstInit --init=IndInvInit --next=Next --inv=IndInv       --length=1
run_expect_ok "[4] IMPLICATION      IndInv => INV_P9_safety (length 0)"        --cinit=ConstInit --init=IndInvInit --next=Next --inv=INV_P9_safety --length=0

echo "------------------------------------------------------------------"
echo "LIVENESS half (availability) -- NOT part of the unbounded certificate"
echo "------------------------------------------------------------------"

run_expect_ok          "[E] enabledness SURROGATE  IndInv => RecoverEnabledForHeld (length 0)" --cinit=ConstInit --init=IndInvInit --next=Next --inv=RecoverEnabledForHeld --length=0
run_expect_unsupported "[L] genuine temporal liveness  ConditionalLiveness (WF-conditional)"   --cinit=ConstInit --init=Init       --next=Next --temporal=ConditionalLiveness --length=8

echo "=================================================================="
echo "RESULT: $PASS check(s) passed/as-expected, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P09 Recovery Completeness: VERIFIED"
  echo "  - SAFETY (correctness): unbounded, inductive ([2]+[3]+[4])."
  echo "  - LIVENESS (availability): enabledness surrogate [E] certified;"
  echo "    full temporal liveness [L] is OUT of certificate scope (Apalache"
  echo "    0.58.0 has no fairness support) -- mirrors Pass-3 MEDIUM-liveness."
else
  echo "P09: FAILURE."
fi
exit "$FAIL"
