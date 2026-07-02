#!/usr/bin/env bash
# Reproducibility runner for P05 On-chain Privacy / Unlinkability.
#
# P05 is an OBSERVATIONAL property over the FULL on-chain BatchInscription
# machine module/Onchain.tla (the SAME machine P02 No-Double-Spend uses). It
# certifies the chain-observer PROJECTION ChainView and the facts about it that
# the cryptographic axioms (A3, BIP-32-PRF, A2) then compose with -- the
# machine-checkable composition surface of unlinkability. Unlinkability itself
# rests on those axioms and is NOT claimed verified (see notes.md / certificate).
#
# property.tla EXTENDS Onchain, which EXTENDS Foundations + Assumptions, so the
# checks are staged into a temp dir holding those four modules together
# (Apalache resolves EXTENDS from the spec's own directory).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# UNBOUNDED dynamic proof = checks [P2]+[P3]+[P4] (set-projection inductive).
#   [P1] bounded SAFETY sanity (length 6 = finality depth K) for the full
#        history-quantified INV_P5 (PublisherOnlyLink + NoMemberStructureOnChain),
#        and [P5] the structural-projection fact over the admit fragment, are
#        supporting bounded results (Seq-capacity scope, see notes.md).
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

echo "=================================================================="
echo "P05 -- On-chain Privacy / Unlinkability (full on-chain model)"
echo "=================================================================="
STAGE="$(mktemp -d)"
cp "$MODDIR/Foundations.tla" "$MODDIR/Assumptions.tla" "$MODDIR/Onchain.tla" \
   "$HERE/property.tla" "$STAGE/"
cd "$STAGE"
SPEC=property.tla
run_typecheck "$SPEC" "[P0] typecheck       property.tla (EXTENDS Onchain)"
run_expect_ok "$SPEC" "[P1] bounded OBSERVABLE  OnInit/OnNext |= INV_P5 (length 6)"        --cinit=P5ConstInit --init=OnInit     --next=OnNext --inv=INV_P5    --length=6
run_expect_ok "$SPEC" "[P2] inductive BASE      OnInit => IndInv_P5 (length 0)"            --cinit=P5ConstInit --init=OnInit     --next=OnNext --inv=IndInv_P5 --length=0
run_expect_ok "$SPEC" "[P3] inductive STEP      IndInv_P5 /\\ OnNext => IndInv_P5' (len 1)" --cinit=P5ConstInit --init=IndInvInit --next=OnNext --inv=IndInv_P5 --length=1
run_expect_ok "$SPEC" "[P4] IMPLICATION         IndInv_P5 => ObservableGuarantee (length 0)" --cinit=P5ConstInit --init=IndInvInit --next=OnNext --inv=ObservableGuarantee --length=0
run_expect_ok "$SPEC" "[P5] structural projection  OnInit/OnNext |= NoMemberStructureOnChain (length 6)" --cinit=P5ConstInit --init=OnInit --next=OnNext --inv=NoMemberStructureOnChain --length=6
cd "$HERE"
rm -rf "$STAGE"
rm -rf "$HERE/_apalache-out"

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P05 On-chain Privacy: VERIFIED (observable composition surface)."
  echo "  Dynamic PublisherOnlyLink: UNBOUNDED set-projection [P2]+[P3]+[P4];"
  echo "                             bounded history-quantified INV_P5 [P1]."
  echo "  Structural NoMemberStructureOnChain: by-construction, checked [P5]."
  echo "  Unlinkability proper rests on AXIOMS A3 / BIP-32-PRF / A2 (see notes.md)."
else
  echo "P05: FAILURE."
fi
exit "$FAIL"
