#!/usr/bin/env bash
# Reproducibility runner for P03 Per-Asset Balance Conservation
# (unbounded proof via an inductive invariant).
#
# property.tla EXTENDS the per-account compliance machine module/Proofs.tla,
# which EXTENDS Foundations + Assumptions (+ Adversary, transitively). Apalache
# resolves EXTENDS from the spec's own directory, so the checks are staged into
# a temp dir holding those modules together with property.tla.
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# The unbounded proof is the conjunction of checks [2]+[3]+[4]:
#   [2] base        P3Init   => IndInv
#   [3] step        IndInv   /\ P3Next => IndInv'
#   [4] implication IndInv   => Conservation
# [1] is a bounded reachability sanity pass. The negative control (clause 3
# deleted) is NOT run here -- it requires an edited copy of module/Proofs.tla;
# its transcript is recorded in certificate.txt / notes.md.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MODDIR="$HERE/../../module"
PASS=0; FAIL=0

run_expect_ok () { # <label> <args...>
  local label=$1; shift
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" property.tla 2>&1)
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

run_spec_ok () { # <specfile> <label> <args...>
  local spec=$1; local label=$2; shift 2
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$spec" 2>&1)
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

run_spec_err () { # <specfile> <label> <args...>  -- a check that MUST find a counterexample
  local spec=$1; local label=$2; shift 2
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$spec" 2>&1)
  if echo "$out" | grep -q "The outcome is: Error"; then
    echo ">>> $label: OK (counterexample found, as required)"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected Error/counterexample)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo "Instance: Accounts = {1,2}, one v1 asset family (ConstInit)."
echo "Inductive argument is uniform in the account/asset universe (notes.md)."
echo

STAGE="$(mktemp -d)"
cp "$MODDIR/Foundations.tla" "$MODDIR/Assumptions.tla" "$MODDIR/Adversary.tla" \
   "$MODDIR/Proofs.tla" "$HERE/property.tla" "$STAGE/"
cd "$STAGE"

run_expect_ok "[1] bounded sanity  P3Init/P3Next |= IndInv (length 6)"          --cinit=ConstInit --init=P3Init    --next=P3Next --inv=IndInv       --length=6
run_expect_ok "[2] inductive BASE   P3Init => IndInv (length 0)"                 --cinit=ConstInit --init=P3Init    --next=P3Next --inv=IndInv       --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ P3Next => IndInv' (length 1)"     --cinit=ConstInit --init=IndInvInit --next=P3Next --inv=IndInv       --length=1
run_expect_ok "[4] IMPLICATION      IndInv => Conservation (length 0)"           --cinit=ConstInit --init=IndInvInit --next=P3Next --inv=Conservation --length=0

cd "$HERE"
rm -rf "$STAGE"
rm -rf "$HERE/_apalache-out"

# ===========================================================================
# spec-v1.1 (docs#47 §3.8) FEE-COIN ATOMICITY (fee_atomicity.tla, self-
# contained: EXTENDS Integers/Apalache). Proves the NEW #47 guarantee that the
# fee coin and the recipient payment under the SAME ocr are admitted all-or-none
# (atomic), and a never-anchored transition's fee is never spendable.
# Universe via ConstInit (Ocrs = 1..3).
# ===========================================================================
echo "=================================================================="
echo "FEE ATOMICITY -- fee_atomicity.tla (spec-v1.1 / docs#47 §3.8, unbounded)"
echo "=================================================================="
cd "$HERE"
FSPEC=fee_atomicity.tla
run_spec_ok  "$FSPEC" "[F1] bounded sanity  Init/Next |= IndInv (length 6)"               --cinit=ConstInit --init=Init      --next=Next --inv=IndInv       --length=6
run_spec_ok  "$FSPEC" "[F2] inductive BASE   Init => IndInv (length 0)"                    --cinit=ConstInit --init=Init      --next=Next --inv=IndInv       --length=0
run_spec_ok  "$FSPEC" "[F3] inductive STEP   IndInv /\\ Next => IndInv' (length 1)"        --cinit=ConstInit --init=IndInvInit --next=Next --inv=IndInv       --length=1
run_spec_ok  "$FSPEC" "[F4] IMPLICATION      IndInv => FeeAtomicity (length 0)"            --cinit=ConstInit --init=IndInvInit             --inv=FeeAtomicity --length=0
run_spec_err "$FSPEC" "[F5] VACUITY probe    NoneEverCompleted reachable-false (completed populated)" --cinit=ConstInit --init=Init --next=Next --inv=NoneEverCompleted --length=3
rm -rf "$HERE/_apalache-out"

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P03 BalanceConservation: VERIFIED (unbounded, inductive)."
  echo "  Unbounded proof = [2] base + [3] step + [4] implication."
  echo "  [1] is a supporting bounded reachability sanity pass."
  echo "  Fee atomicity (docs#47 §3.8): unbounded [F2]+[F3]+[F4];"
  echo "  bounded sanity [F1] + vacuity probe [F5]"
  echo "  (negative control recorded in notes.md)."
else
  echo "P03: FAILURE."
fi
exit "$FAIL"
