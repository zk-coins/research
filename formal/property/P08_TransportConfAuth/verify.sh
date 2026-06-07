#!/usr/bin/env bash
# Reproducibility runner for P08 Transport Confidentiality + Authentication
# (Phase-2 unbounded proof).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# property.tla EXTENDS module/Transport.tla (which EXTENDS Foundations and
# Assumptions). Apalache resolves EXTENDS only from the spec's own directory,
# so this runner stages property.tla together with the three module files in a
# scratch dir and runs there -- the module files are NOT duplicated into the
# committed property directory (same pattern as module/verify-modules.sh).
#
# The unbounded proof is the conjunction of checks [2]+[3]+[4]:
#   [2] base        TrInit  => IndInv
#   [3] step        IndInv  /\ TrNext => IndInv'
#   [4] implication IndInv  => INV_P8
# [1] is a bounded reachability sanity pass. [5a]/[5b] are the negative
# controls (run separately, see notes.md) that show the nonce-equality check
# and the trAckOk drop guard are load-bearing.
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

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "Instance: TrConstInit (K=3, Holders={1,2,3}, RecipientOpPk=10, IvkHolders=KtxHolders={20,21}, Eve=99);"
echo "inductive argument is uniform in the instance sizes (notes.md records a larger-instance confirmation)."
echo

run_expect_ok "[1] bounded sanity  TrInit/TrNext |= IndInv (length 10)" --cinit=ConstInit --init=TrInit --next=TrNext --inv=IndInv --length=10
run_expect_ok "[2] inductive BASE   TrInit => IndInv (length 0)"          --cinit=ConstInit --init=TrInit --next=TrNext --inv=IndInv --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ TrNext => IndInv' (length 1)" --cinit=ConstInit --init=IndInvInit --next=TrNext --inv=IndInv --length=1
run_expect_ok "[4] IMPLICATION      IndInv => INV_P8 (length 0)"            --cinit=ConstInit --init=IndInvInit --next=TrNext --inv=INV_P8 --length=0

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
[ "$FAIL" -eq 0 ] && echo "P08 Transport Conf+Auth: VERIFIED (unbounded, inductive)." || echo "P08: FAILURE."
exit "$FAIL"
