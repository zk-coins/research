#!/usr/bin/env bash
# Reproducibility runner for P02 No-Double-Spend -- BOTH layers.
#
#   Layer A (Phase 0, abstract.tla):   the set-level accumulator abstraction,
#                                      proven UNBOUNDED. Self-contained module.
#   Layer B (this phase, property.tla): the FULL on-chain BatchInscription
#                                      machine (EXTENDS module/Onchain.tla),
#                                      proven UNBOUNDED for no-double-spend.
#
# property.tla EXTENDS Onchain, which EXTENDS Foundations + Assumptions, so the
# full-model checks are staged into a temp dir holding those four modules
# together (Apalache resolves EXTENDS from the spec's own directory).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# Layer A unbounded proof  = checks [A2]+[A3]+[A4].
# Layer B unbounded proof  = checks [B2]+[B3]+[B4] (no-double-spend + zones).
#   [B1] bounded safety sanity (length 6) and [B5] chain-continuity over the
#   admit/confirm fragment are supporting bounded results (see notes.md).
# Exit status = total unexpected outcomes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MODDIR="$HERE/../../module"
PASS=0; FAIL=0

run_expect_ok () { # <specfile> <label> <args...>
  local spec=$1; local label=$2; shift 2
  echo "### $label"
  local out
  out=$(apalache-mc check "$@" "$spec" 2>&1)
  if echo "$out" | grep -q "The outcome is: NoError"; then
    echo "$out" | grep -E "The outcome is:|Checker reports no error up to" | head -2
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo "$out" | grep -E "The outcome is|EXITCODE" | head -2
    echo ">>> $label: UNEXPECTED (expected NoError)"; FAIL=$((FAIL+1))
  fi
  echo
}

run_typecheck () { # <specfile> <label>
  local spec=$1; local label=$2
  echo "### $label"
  if apalache-mc typecheck "$spec" 2>&1 | grep -q "EXITCODE: OK"; then
    echo ">>> $label: OK"; PASS=$((PASS+1))
  else
    echo ">>> $label: UNEXPECTED (expected typecheck OK)"; FAIL=$((FAIL+1))
  fi
  echo
}

echo "Apalache version: $(apalache-mc version 2>/dev/null | head -1)"
echo

# ===========================================================================
# LAYER A -- Phase-0 abstract accumulator model (abstract.tla, self-contained).
# Universe Nullifier = 1..6 (AbstractConstInit); argument uniform in size.
# ===========================================================================
echo "=================================================================="
echo "LAYER A -- abstract accumulator model (Phase 0, unbounded)"
echo "=================================================================="
echo "Universe: Nullifier = 1..6 (ConstInit); inductive argument uniform in |Nullifier|."
echo
cd "$HERE"
ASPEC=abstract.tla
run_expect_ok "$ASPEC" "[A1] bounded sanity  Init/Next |= IndInv (length 12)"         --cinit=ConstInit --init=Init --next=Next --inv=IndInv --length=12
run_expect_ok "$ASPEC" "[A2] inductive BASE   Init => IndInv (length 0)"               --cinit=ConstInit --init=Init --inv=IndInv --length=0
run_expect_ok "$ASPEC" "[A3] inductive STEP   IndInv /\\ Next => IndInv' (length 1)"   --cinit=ConstInit --init=IndInvInit --next=Next --inv=IndInv --length=1
run_expect_ok "$ASPEC" "[A4] IMPLICATION      IndInv => NoDoubleSpend (length 0)"      --cinit=ConstInit --init=IndInvInit --inv=NoDoubleSpend --length=0

# ===========================================================================
# LAYER B -- FULL on-chain BatchInscription machine (property.tla EXTENDS
# Onchain). Staged into a temp dir with Foundations + Assumptions + Onchain.
# ===========================================================================
echo "=================================================================="
echo "LAYER B -- full on-chain model (this phase)"
echo "=================================================================="
STAGE="$(mktemp -d)"
cp "$MODDIR/Foundations.tla" "$MODDIR/Assumptions.tla" "$MODDIR/Onchain.tla" \
   "$HERE/property.tla" "$STAGE/"
cd "$STAGE"
BSPEC=property.tla
run_typecheck "$BSPEC" "[B0] typecheck       property.tla (EXTENDS Onchain)"
run_expect_ok "$BSPEC" "[B1] bounded SAFETY   OnInit/OnNext |= INV (length 6)"             --cinit=OnConstInit --init=OnInit --next=OnNext --inv=INV --length=6
run_expect_ok "$BSPEC" "[B2] inductive BASE   OnInit => IndInv_P2 (length 0)"              --cinit=OnConstInit --init=OnInit --next=OnNext --inv=IndInv_P2 --length=0
run_expect_ok "$BSPEC" "[B3] inductive STEP   IndInv_P2 /\\ OnNext => IndInv_P2' (len 1)"  --cinit=OnConstInit --init=IndInvInit --next=OnNext --inv=IndInv_P2 --length=1
run_expect_ok "$BSPEC" "[B4] IMPLICATION      IndInv_P2 => INV (length 0)"                 --cinit=OnConstInit --init=IndInvInit --next=OnNext --inv=INV --length=0
run_expect_ok "$BSPEC" "[B5] continuity (admit/confirm fragment) |= INV_Continuity (len 6)" --cinit=OnConstInit --init=OnInit --next=NextAdmitConfirm --inv=INV_Continuity --length=6
cd "$HERE"
rm -rf "$STAGE"
rm -rf "$HERE/_apalache-out"

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P02 NoDoubleSpend: VERIFIED."
  echo "  Layer A (abstract):    unbounded   [A2]+[A3]+[A4]"
  echo "  Layer B (full Onchain): unbounded no-double-spend [B2]+[B3]+[B4];"
  echo "                          bounded safety [B1] + fragment continuity [B5]."
else
  echo "P02: FAILURE."
fi
exit "$FAIL"
