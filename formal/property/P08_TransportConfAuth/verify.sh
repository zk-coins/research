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
cp "$HERE/zbe.tla" "$STAGE/"      # self-contained spec-v1.1 ZBE anti-truncation
cp "$HERE/zbe_nc.tla" "$STAGE/"   # its negative control (wired as [Z6])
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
echo "Instance: TrConstInit (K=3, Holders={1,2,3}, RecipientOpPk=10, IvkHolders=KtxHolders={20,21}, Eve=99);"
echo "inductive argument is uniform in the instance sizes (notes.md records a larger-instance confirmation)."
echo

run_expect_ok "[1] bounded sanity  TrInit/TrNext |= IndInv (length 10)" --cinit=ConstInit --init=TrInit --next=TrNext --inv=IndInv --length=10
run_expect_ok "[2] inductive BASE   TrInit => IndInv (length 0)"          --cinit=ConstInit --init=TrInit --next=TrNext --inv=IndInv --length=0
run_expect_ok "[3] inductive STEP   IndInv /\\ TrNext => IndInv' (length 1)" --cinit=ConstInit --init=IndInvInit --next=TrNext --inv=IndInv --length=1
run_expect_ok "[4] IMPLICATION      IndInv => INV_P8 (length 0)"            --cinit=ConstInit --init=IndInvInit --next=TrNext --inv=INV_P8 --length=0

# ===========================================================================
# spec-v1.1 (docs#47 §4.2.1) ZBE ANTI-TRUNCATION (zbe.tla, self-contained:
# EXTENDS Integers/Sequences/Apalache). Proves the NEW #47 integrity guarantee
# that a truncated / extended / reordered chunk sequence is REJECTED (does not
# authenticate), so an ACCEPTED plaintext equals exactly the sealed plaintext.
# Confidentiality stays the existing CanDecrypt/A10 fact above; this is the
# integrity layer. Universe via ConstInit (MaxN=3, Payloads=1..2).
# ===========================================================================
echo "=================================================================="
echo "ZBE ANTI-TRUNCATION -- zbe.tla (spec-v1.1 / docs#47 §4.2.1, unbounded)"
echo "=================================================================="
ZSPEC=zbe.tla
run_spec_ok  "$ZSPEC" "[Z1] bounded sanity  Init/Next |= IndInv (length 4)"               --cinit=ConstInit --init=Init      --next=Next --inv=IndInv         --length=4
run_spec_ok  "$ZSPEC" "[Z2] inductive BASE   Init => IndInv (length 0)"                    --cinit=ConstInit --init=Init      --next=Next --inv=IndInv         --length=0
run_spec_ok  "$ZSPEC" "[Z3] inductive STEP   IndInv /\\ Next => IndInv' (length 1)"        --cinit=ConstInit --init=IndInvInit --next=Next --inv=IndInv         --length=1
run_spec_ok  "$ZSPEC" "[Z4] IMPLICATION      IndInv => AntiTruncation (length 0)"          --cinit=ConstInit --init=IndInvInit             --inv=AntiTruncation --length=0
run_spec_err "$ZSPEC" "[Z5] VACUITY probe    NeverAccepted reachable-false (accepted=TRUE reachable)" --cinit=ConstInit --init=Init --next=Next --inv=NeverAccepted --length=3
run_spec_err "zbe_nc.tla" "[Z6] NEGATIVE CONTROL dropped (N,i) AAD => AntiTruncation violated" --cinit=ConstInit --init=Init --next=Next --inv=AntiTruncation --length=3

echo "=================================================================="
echo "RESULT: $PASS check(s) passed, $FAIL unexpected."
if [ "$FAIL" -eq 0 ]; then
  echo "P08 Transport Conf+Auth: VERIFIED (unbounded, inductive)."
  echo "  ZBE anti-truncation (docs#47 §4.2.1): unbounded [Z2]+[Z3]+[Z4];"
  echo "  bounded sanity [Z1] + vacuity probe [Z5]"
  echo "  (negative control recorded in notes.md)."
else
  echo "P08: FAILURE."
fi
exit "$FAIL"
