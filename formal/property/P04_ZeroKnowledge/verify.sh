#!/usr/bin/env bash
# Reproducibility runner for P04 Zero-Knowledge (witness confidentiality)
# -- the DYNAMIC observer-flow / containment half (Phase-2 unbounded proof).
#
# Prerequisite: apalache-mc on PATH (pinned version recorded in notes.md).
# Usage:        ./verify.sh
#
# property.tla EXTENDS module/Proofs.tla (which EXTENDS Foundations and
# Assumptions). Apalache resolves EXTENDS only from the spec's own directory,
# so this runner stages property.tla together with its three module files in a
# scratch dir and runs there -- the module files are NOT duplicated into the
# committed property directory (same pattern as module/verify-modules.sh).
#
# The unbounded proof of the DYNAMIC flow invariant is checks [2]+[3]+[4]:
#   [2] base        Init                  => IndInv         (incl. PrTypeOK)
#   [3] step        IndInv /\ Next         => ObsInv'        (observer invariant
#                   preserved, RELATIVE to the PrTypeOK lineage-typing
#                   hypothesis carried in the generated pre-state; PrTypeOK
#                   itself is module/Proofs.tla's own type-safety obligation,
#                   confirmed reachable to depth 8 by check [1])
#   [4] implication ObsInv                => INV_P4_flow
# [1] is a bounded reachability sanity pass (full IndInv incl. PrTypeOK, depth
# 8). [V] is the vacuity probe and [NC]
# is the negative control -- both run out of band and recorded in notes.md /
# certificate.txt (they must FIND a trace = expected Error).
#
# P4 is split honestly: this runner machine-checks the DYNAMIC observer-flow
# containment invariant only. The STRUCTURAL typed-disjointness fact and the
# AXIOM half (A2 indistinguishability, A10/A11, A3/A9) are documented, NOT
# machine-claimed -- see notes.md / certificate.txt.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MOD="$HERE/../../module"
SPEC=property.tla

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$MOD/Foundations.tla" "$MOD/Assumptions.tla" "$MOD/Proofs.tla" "$STAGE/"
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
echo "Instance: PrConstInit (Accounts={1,2}, one v1 asset family);"
echo "the flow argument is per-transition local (the gate is evaluated fresh on"
echo "each publish), uniform in the instance sizes (notes.md records a larger run)."
echo

run_expect_ok "[1] bounded sanity  Init/Next |= IndInv (length 8)"           --cinit=ConstInit --init=Init       --next=Next --inv=IndInv      --length=8
run_expect_ok "[2] inductive BASE   Init => IndInv (length 0)"                --cinit=ConstInit --init=Init       --next=Next --inv=IndInv      --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ Next => ObsInv' (length 1)"     --cinit=ConstInit --init=IndInvInit --next=Next --inv=ObsInv      --length=1
run_expect_ok "[4] IMPLICATION      ObsInv => INV_P4_flow (length 0)"         --cinit=ConstInit --init=IndInvInit --next=Next --inv=INV_P4_flow --length=0

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
[ "$FAIL" -eq 0 ] && echo "P04 Zero-Knowledge (dynamic flow half): VERIFIED (unbounded, inductive)." || echo "P04: FAILURE."
exit "$FAIL"
