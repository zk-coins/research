#!/usr/bin/env bash
# Phase-1 module gate: every module type-checks; every state-machine module
# additionally passes an Init/Next reachability smoke check (TypeOK, length 3).
#
# Every state-machine module carries a per-module PREFIX on its Init/Next/Spec/
# vars/TypeOK/ConstInit and on its variables and exposed invariants, so any
# subset of modules can be EXTENDed together with no name clash. A COMPOSITION
# SMOKE below proves two machine modules actually compose (EXTENDS both).
#   prefixes: Onchain=On  Proofs=Pr  Transport=Tr  Access=Ac  Architecture=Ar
#
# Prerequisite: apalache-mc on PATH (pinned version in property/*/notes.md).
# Usage:        ./verify-modules.sh
set -u
cd "$(dirname "$0")"

DEFINITION_MODULES="Foundations Assumptions Adversary"

# Each entry: "Module Prefix" -- the prefix names the module's Init/Next/etc.
MACHINE_MODULES="Proofs:Pr Onchain:On Transport:Tr Access:Ac Architecture:Ar"

FAIL=0

for m in $DEFINITION_MODULES; do
  printf '%-14s typecheck ' "$m"
  if apalache-mc typecheck "$m.tla" 2>&1 | grep -q "EXITCODE: OK"; then
    echo "OK"
  else
    echo "FAIL"; FAIL=$((FAIL+1))
  fi
done

for entry in $MACHINE_MODULES; do
  m="${entry%%:*}"
  printf '%-14s typecheck ' "$m"
  if apalache-mc typecheck "$m.tla" 2>&1 | grep -q "EXITCODE: OK"; then
    echo "OK"
  else
    echo "FAIL"; FAIL=$((FAIL+1))
  fi
done

for entry in $MACHINE_MODULES; do
  m="${entry%%:*}"
  p="${entry##*:}"
  printf '%-14s smoke     ' "$m"
  if apalache-mc check --cinit="${p}ConstInit" --init="${p}Init" \
       --next="${p}Next" --inv="${p}TypeOK" --length=3 "$m.tla" 2>&1 \
       | grep -q "The outcome is: NoError"; then
    echo "OK"
  else
    echo "FAIL"; FAIL=$((FAIL+1))
  fi
done

# ---------------------------------------------------------------------------
# COMPOSITION SMOKE. Prove that two machine modules compose: a scratch module
# EXTENDS both Onchain and Proofs (which both used to define Init/Next/Spec/
# vars/TypeOK/ConstInit and a VARIABLE `authorised`). With the prefixes there
# is no clash, so the composed Init/Next/TypeOK over the union of both modules'
# variables is a well-formed spec. length=1 is enough to prove they compose.
# ---------------------------------------------------------------------------
SCRATCH="$(mktemp -d)"
cp Foundations.tla Assumptions.tla Onchain.tla Proofs.tla "$SCRATCH/"
cat > "$SCRATCH/Compose.tla" <<'EOF'
-------------------------- MODULE Compose --------------------------
\* Composition smoke (Phase-1 gate): EXTENDS two machine modules at once and
\* combines their prefixed entry points. NoError proves the two compose with
\* no name clash on Init/Next/Spec/vars/TypeOK/ConstInit or any variable.
EXTENDS Onchain, Proofs

\* Combined constant initialiser (no constant-name overlap between the two).
BothConstInit == OnConstInit /\ PrConstInit

\* Composed initial predicate over the union of both modules' variables.
BothInit   == OnInit /\ PrInit

\* Composed transition: each module steps independently, holding the other
\* module's variables fixed (the prefixed prVars / onVars are both visible here,
\* which is exactly what a Phase-2 property module EXTENDing both will rely on).
BothNext   == \/ (OnNext /\ UNCHANGED prVars)
              \/ (PrNext /\ UNCHANGED onVars)

BothTypeOK == OnTypeOK /\ PrTypeOK
====================================================================
EOF

printf '%-14s smoke     ' "Compose(On+Pr)"
COMPOSE_CMD="apalache-mc check --cinit=BothConstInit --init=BothInit --next=BothNext --inv=BothTypeOK --length=1 Compose.tla"
if ( cd "$SCRATCH" && eval "$COMPOSE_CMD" ) 2>&1 | grep -q "The outcome is: NoError"; then
  echo "OK"
else
  echo "FAIL"; FAIL=$((FAIL+1))
fi
rm -rf "$SCRATCH"

rm -rf _apalache-out
echo "=================================================="
[ "$FAIL" -eq 0 ] && echo "Phase 1 modules: ALL GREEN." || echo "Phase 1 modules: $FAIL failure(s)."
exit "$FAIL"
