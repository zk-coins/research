#!/usr/bin/env bash
# Reproducibility runner for P06 Client-Side Validation (no third-party trust)
# -- Phase-2 unbounded composition proof.
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# property.tla EXTENDS module/Onchain.tla (which EXTENDS Foundations and
# Assumptions). Apalache resolves EXTENDS only from the spec's own directory,
# so this runner stages property.tla together with the three module files in a
# scratch dir and runs there -- the module files are NOT duplicated into the
# committed property directory (same pattern as P02/P08 and module/verify-modules.sh).
#
# The composed machine is  P6Next == OnNext \/ Receive \/ AdversaryOffer.
# The UNBOUNDED proof is the conjunction of checks [P2]+[P3]+[P4]:
#   [P2] base        P6Init   => IndInv_P6
#   [P3] step        IndInv_P6 /\ P6Next => IndInv_P6'
#   [P4] implication IndInv_P6 => INV_P6
# [P0] is a bounded reachability sanity pass. [P1] is the VACUITY GUARD
# (reachability probe: credits actually happen -> CreditsNeverHappen is
# VIOLATED). The two NEGATIVE CONTROLS (gate checks are load-bearing) run
# separately, see notes.md.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MOD="$HERE/../../module"
SPEC=property.tla

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$HERE/_apalache-out"' EXIT
cp "$MOD/Foundations.tla" "$MOD/Assumptions.tla" "$MOD/Onchain.tla" "$STAGE/"
cp "$HERE/$SPEC" "$STAGE/"
cd "$STAGE"

PASS=0; FAIL=0

run_typecheck () { # <label>
  local label=$1
  echo "### $label"
  if apalache-mc typecheck "$SPEC" 2>&1 | grep -q "EXITCODE: OK"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo ">>> $label: UNEXPECTED (expected typecheck OK)"; FAIL=$((FAIL+1))
  fi
  echo
}

run_expect_ok () { # <label> <args...>
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo "$out" | grep -E "The outcome is:|Checker reports no error up to" | head -2
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

run_expect_violation () { # <label> <args...>   (expect a counterexample = Error)
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$SPEC" 2>&1)
  if echo "$out" | grep -q "The outcome is: Error"; then
    echo "$out" | grep -E "The outcome is:" | head -1
    echo ">>> $label: OK (counterexample found, as expected)"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected a counterexample)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "Instance: P6ConstInit = OnConstInit (Nullifiers = {nf1,nf2,nf3}, Publishers=1..2,"
echo "BundleLocators=1..2); inductive argument uniform in the universe sizes."
echo "Composed machine: P6Next == OnNext \\/ Receive \\/ AdversaryOffer."
echo

run_typecheck       "[P0t] typecheck     property.tla (EXTENDS Onchain)"
run_expect_ok       "[P0]  bounded SANITY P6Init/P6Next |= INV_P6 (length 6)"            --cinit=P6ConstInit --init=P6Init    --next=P6Next --inv=INV_P6    --length=6
run_expect_violation "[P1]  VACUITY GUARD  credits ARE reachable (CreditsNeverHappen violated, len 6)" --cinit=P6ConstInit --init=P6Init    --next=P6Next --inv=CreditsNeverHappen --length=6
run_expect_ok       "[P2]  inductive BASE  P6Init => IndInv_P6 (length 0)"               --cinit=P6ConstInit --init=P6Init    --next=P6Next --inv=IndInv_P6 --length=0
run_expect_ok       "[P3]  inductive STEP  IndInv_P6 /\\ P6Next => IndInv_P6' (length 1)" --cinit=P6ConstInit --init=IndInvInit --next=P6Next --inv=IndInv_P6 --length=1
run_expect_ok       "[P4]  IMPLICATION     IndInv_P6 => INV_P6 (length 0)"               --cinit=P6ConstInit --init=IndInvInit --next=P6Next --inv=INV_P6    --length=0

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P06 Client-Side Validation: VERIFIED (unbounded, inductive)."
  echo "  Composed machine OnNext \\/ Receive \\/ AdversaryOffer:"
  echo "  unbounded INV_P6 [P2]+[P3]+[P4]; bounded sanity [P0];"
  echo "  reachability vacuity guard [P1] (credits reachable)."
  echo "  Negative controls (gate load-bearing) -- see notes.md."
else
  echo "P06: FAILURE."
fi
exit "$FAIL"
