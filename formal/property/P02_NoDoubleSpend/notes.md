# P02 — No-Double-Spend — notes

This package now covers **two layers**:

- **Layer A (Phase 0)** — `abstract.tla` (renamed from the original
  `property.tla`): the abstract three-set accumulator model, proven unbounded.
  Its standalone transcript is preserved verbatim in `certificate-abstract.txt`.
  The sections below up to "Full-model upgrade" describe Layer A (file
  references to the abstract model now read `abstract.tla`).
- **Layer B (this phase)** — `property.tla`: EXTENDS the full on-chain machine
  `module/Onchain.tla` and proves the same claim over the concrete
  BatchInscription state machine. See "Full-model upgrade" below.

The combined `certificate.txt` and `verify.sh` cover both layers.

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
JVM             : Temurin OpenJDK 17.0.19
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every later certificate re-states the Apalache + Z3 version it was produced
under, so a divergent result on a future version is attributable.

## What this is

Phase-0 deliverable: the legacy bounded TLC model
[`nullifier-chaining/FirstSpendWins.tla`](https://github.com/zk-coins/research/blob/feat/formal-nullifier-chaining-model/formal/nullifier-chaining/FirstSpendWins.tla)
(`Bound = 5`) ported to Apalache and proven **unbounded** by an inductive
invariant. It validates the toolchain end-to-end and produces the first
machine certificate of the initiative.

## Property statement (M4 ground-truth)

- **Prose spec section formalised:** On-chain Sec. 3.6 (chain scanning,
  first-spend-wins), Sec. 3.7 (the nullifier accumulator), Sec. 3.10
  (transaction states; the accumulator absorbs every *admitted*
  `pending ∪ completed` batch, not only `completed`), Architecture Sec. 6.6
  (≤ 5-block reorg bound ⇒ `completed` absolute). Baseline `docs@b6972b8`
  (post-`docs#40`).
- **Pass-3 §4 game-style statement (the oracle):** "Each coin `c` can be
  successfully spent at most once. A PPT adversary cannot cause two distinct
  honest receivers to credit two distinct downstream coins that both consume
  `c`." Pass-3 verdict: **HIGH**, conditional on A3, A12 (and, post-#40, A15/A16
  for the aggregate-proof / SMT obligations).
- **Formalised invariant:** `NoDoubleSpend == doubled = {}`, where `doubled`
  accumulates any nullifier an admitted batch inserts while it is already
  present in the accumulator `Acc = pending ∪ completed`. The first-spend-wins
  rule (the `[GATE]` conjunct `B ∩ Acc = {}`) is exactly the post-#40
  `AggregateBatchProof` obligation that every batch nullifier is a non-member
  of `prev_root`.

## Modelling decisions

- **Sequence-free encoding.** The legacy model carried `log` as a `Seq` of
  records and bounded its length with `Bound`. Apalache encodes sequences with
  a static capacity, which would re-introduce a length bound. The accumulator
  is therefore modelled directly as the two nullifier **sets** `pending` /
  `completed` (zones of On-chain Sec. 3.10), with `doubled` as double-spend
  evidence. State is finite-dimensional, so the inductive step is a single SMT
  query with **no** bound on the number of transitions — the genuine "for all
  N" the initiative targets.
- **Nullifier = coin identity (axiom A1).** `nf = Hc("Nullifier", nk ‖ id)` is
  injective, so a nullifier *is* the coin; set membership is the double-spend
  test.
- **Accumulator as a set (axioms A15/A16).** Post-#40 the accumulator advances
  by `new_root = SMT.insert_many(prev_root, batch_nullifiers)` attested by the
  `AggregateBatchProof`. Under A16 the SMT root is collision-bound to its key
  set, so reasoning over the abstract *set* of admitted nullifiers is faithful;
  A15 covers the half-aggregated signature check folded into the same proof.
  These are accepted per decision D3.
- **`completed` absolute.** `Reorg` removes only from `pending`; `completed`
  (depth ≥ 6) is never touched — the ≤ 5-block reorg bound (A12, Architecture
  Sec. 6.6).
- **Over-approximation (sound for safety).** `Confirm` promotes an arbitrary
  subset of `pending` (real confirmation is depth-ordered) and `Reorg` drops an
  arbitrary subset of `pending` (a real reorg drops whole record suffixes).
  Both admit strictly **more** behaviours than the protocol; a safety invariant
  proven over the larger behaviour set holds a fortiori for the protocol's
  subset. Legitimate respend after a reorg is preserved: a dropped nullifier
  leaves `Acc` and may be re-admitted, exactly as in the legacy model.
- **Inductive invariant.** `IndInv == TypeOK /\ ZonesDisjoint /\ NoDoubleSpend`.
  `NoDoubleSpend` is inductive on its own; `ZonesDisjoint`
  (`pending ∩ completed = {}`) is carried because it is the structural fact the
  richer `Onchain.tla` will rely on, and it requires genuine induction.
  `IndInvInit` is the assignment-form restatement used as the `--init`
  predicate of the step check (Apalache requires each variable *assigned*, not
  merely constrained by `\subseteq`); the two are logically equivalent
  (`x \in SUBSET S ⟺ x ⊆ S`, and `doubled = {}` subsumes
  `doubled ⊆ Nullifier`).
- **No `apalache.cfg`.** The unbounded proof is four runs with *different*
  `--init`/`--inv`/`--length` combinations, which a single TLC-style config
  file cannot express; the constant is pinned in-module (`ConstInit`,
  consumed via `--cinit`). [`verify.sh`](./verify.sh) is therefore the
  canonical, reproducible runner for this property (now both layers) — the §8
  reproducibility contract's "one command" is `./verify.sh`.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary
(all wall-clock < 2 s each on the host above; runner: [`verify.sh`](./verify.sh)):

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=Init --next=Next --inv=IndInv --length=12` | NoError |
| 2 | inductive base | `--init=Init --inv=IndInv --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=Next --inv=IndInv --length=1` | NoError |
| 4 | implication | `--init=IndInvInit --inv=NoDoubleSpend --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded proof. All runs use
`--cinit=ConstInit` (Nullifier = 1..6).

**Uniformity in |Nullifier|.** Checks 2/3/4 were re-run with
`Nullifier = 1..12`; all three report NoError. The inductive argument is
per-nullifier local, so the result is uniform in the universe size; the
committed `ConstInit` fixes 1..6 for a fast default run.

## Negative control (the gate is load-bearing)

Removing the `[GATE]` conjunct `B ∩ Acc = {}` from `Admit` and running

```
apalache-mc check --cinit=ConstInit --init=Init --next=Next --inv=NoDoubleSpend --length=2 abstract.tla
```

returns a counterexample — confirming the model can *see* a double-spend, so a
NoError verdict with the gate is meaningful:

```
State0:  pending={},  completed={},  doubled={}
State1:  pending={1}, completed={},  doubled={}     (Admit B={1})
State2:  pending={1}, completed={},  doubled={1}    (Admit B={1} again — nf 1 re-spent)
         => state invariant NoDoubleSpend violated at State 2
```

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 label **HIGH**; Apalache verdict **verified** ⇒ **confirmed** at the
abstract accumulator level. Full reconciliation is deferred to Phase 4.

**Oracle/baseline provenance.** The Pass-3 audit was written against docs
snapshot `01ae663` (pre-`#33` eight-file layout), so its P2 prose still says
"first-spend-wins, canonical order (§3.6 step 6)" — the pre-`docs#40`
node-local-rebuild mechanism. `docs#40` (baseline `b6972b8`) relocated that
obligation into the publisher's in-circuit `AggregateBatchProof`
(`new_root = SMT.insert_many(prev_root, batch_nullifiers)` with per-nullifier
non-membership). The *claim* is identical across the redesign — only the
enforcement site moved — so the audit remains a valid oracle; this note records
the wording delta for any reader cross-referencing the audit text.

## Scope / what is deliberately NOT yet modelled

This is the Phase-0 abstract smoke test. The following post-#40 mechanism
detail is modelled in `module/Onchain.tla` (Phase 1) and folded into the final
Phase-3 P02 certificate; none of it affects the abstract invariant proven here:

- the `BatchInscription` byte format and 231-byte fixed parse (On-chain Sec. 3.5);
- `prev_root` continuity races between competing publishers and stale-rejection
  (Sec. 3.4 / Sec. 3.6 step 4);
- the `pending`-due-to-DA sub-state vs `pending`-due-to-confirmations
  (Sec. 3.10), and the `mint-verified` status for non-anchored mints;
- the in-circuit derivation `nf = Hc("Nullifier", nk ‖ coin.identifier)` and the
  per-account coin-history discipline (Proofs Sec. 2.1 clauses 2/4/8), which P2
  also leans on for the *within-account* no-double-spend half.

---

# Full-model upgrade (Layer B — `property.tla` EXTENDS `module/Onchain.tla`)

This phase lifts P02 from the abstract three-set smoke test to the **full
post-docs#40 on-chain model**, proving the same safety claim over the concrete
`BatchInscription` state machine in `module/Onchain.tla` (baseline
`docs@b6972b8`, On-chain Sec. 3.4–3.10). `abstract.tla` (Phase 0) is preserved
unchanged.

## What the full model adds over the abstract

The abstract model carried only `pending/completed/doubled` sets and a single
set-level `[GATE]`. Layer B carries the real machine:

- **BatchInscription admission** (`Admit`, §3.6 steps 1–8) over a concrete
  record `[publisherPk, prevRoot, newRoot, bundleLocator, blockAnchorHeight,
  batchNullifiers, memberValidities, anchorOk]`, gated by six explicit
  conjuncts, each citing its spec step:
  - `[SIG]` §3.6 step 3 / A7 — publisher BIP-340 signature valid (`SigValid`
    over the `onAuthorised` oracle, grown only by honest `PublisherSign`);
  - `[ANCHOR]` §3.5 — block_anchor strict-ancestor + gap≤100 (`anchorOk`);
  - `[AGG]` §3.3 / A15 — half-aggregation: every member signature valid
    (`AggSoundValid`);
  - `[CONT]` §3.6 step 4 / §3.4 — prev_root continuity: `prevRoot` commits to
    the live accumulator `Acc` (`RootCommitsSet`); a stale racing publisher
    simply fails this conjunct (the §3.6 step-4 stale rejection, no own action);
  - `[INSERT]` §3.7 / §3.6 step 7 — `newRoot = SMT.insert_many(prevRoot,
    batch)`, i.e. `newRoot` commits to `prevRoot ∪ batchNullifiers`;
  - `[GATE]` post-#40 — first-spend-wins: `batchNullifiers ∩ prevRoot = {}`.
    THE load-bearing predicate; `onDoubled` is written from
    `batchNullifiers ∩ Acc` **before** the gate so its removal is observable.
- **Sequential admitted history** `onAdmittedChain : Seq($batchInscription)`,
  appended on `Admit`, filtered on `Reorg`.
- **Confirm** (§3.9) one-way promotion `onPending → onCompleted`, and **Reorg**
  (§3.7/3.9, A12) reverting only `onPending` with `depth < FinalityDepthK = 6`.

## IndInv design (the 3-check pattern over the full machine)

`INV == OnNoDoubleSpend /\ OnZonesDisjoint` is the safety claim (no double
spend) plus the structural disjoint-zone fact. The inductive invariant:

```
IndInv_P2 ==
  /\ onPending  ⊆ Nullifiers
  /\ onCompleted ⊆ Nullifiers
  /\ onDoubled  ⊆ Nullifiers
  /\ onAuthorised ⊆ (Publishers × BundleLocators)
  /\ onPending ∩ onCompleted = {}      (OnZonesDisjoint)
  /\ onDoubled = {}                    (OnNoDoubleSpend)
```

Three checks, all `NoError` (universe via `OnConstInit`):

- `[B2]` base: `OnInit ⇒ IndInv_P2`.
- `[B3]` step: `IndInv_P2 ∧ OnNext ⇒ IndInv_P2'`, where
  `OnNext = PublisherSign ∨ Admit ∨ Confirm ∨ Reorg` (the **full** Next,
  including Reorg).
- `[B4]` implication: `IndInv_P2 ⇒ INV`.

`[B2]+[B3]+[B4]` is the standard inductive argument ⇒ **no-double-spend and
disjoint zones hold UNBOUNDED** over the concrete BatchInscription machine.

**Strengthening note.** `OnNoDoubleSpend` is inductive on its own; the
disjoint-zone conjunct is carried because `Confirm` moves nullifiers from
`onPending` to `onCompleted` and the gate reads `Acc = onPending ∪ onCompleted`
— the same minimal strengthening the abstract layer used, now under the
concrete admission gate. No further conjuncts were needed; the set conjuncts
are exactly the abstract `IndInv` re-expressed over the prefixed variables.

## The Seq-variable handling argument (why this is honest unbounded)

`IndInv_P2` is stated over the **set** variables only; it never references the
`onAdmittedChain` **sequence**. The step check needs an assignment-form init
(Apalache requires every variable *assigned*, not merely `⊆`-constrained):

```
IndInvInit ==
  /\ onPending  ∈ SUBSET Nullifiers
  /\ onCompleted ∈ SUBSET Nullifiers
  /\ onDoubled  = {}
  /\ onAuthorised ∈ SUBSET (Publishers × BundleLocators)
  /\ onPending ∩ onCompleted = {}
  /\ onAdmittedChain = Gen(4)          \* apalache.Gen: arbitrary seq, cap ≤ 4
```

The sequence is assigned an **arbitrary** value via `apalache.Gen` rather than
a specific one. Two facts make this a faithful *unbounded* statement about the
no-double-spend safety property:

1. `IndInv_P2` does not read `onAdmittedChain`; and
2. the **set effects** of every `OnNext` action — including `Admit`, which
   `Append`s to the chain, and `Reorg`, which `SelectSeq`-filters it — do not
   depend on the chain's value (the `[GATE]` tests against the live set `Acc`,
   never the chain).

So the step proves: *for every reachable set-state satisfying `IndInv_P2`
(under ANY admitted history), one `OnNext` step preserves `IndInv_P2`.* The
`Gen(4)` capacity bounds only the bookkeeping witness, never the safety
conclusion. This is the **set-projection unbounded** result the task targets:
a true "for all N" over the number of transitions for the actual P2 claim. We
deliberately took option (ii) from the plan (project the induction onto the set
variables, prove the invariant does not reference the chain) rather than
constructing bounded parametric chains.

## Reorg continuity over-approximation (honest finding)

`OnPrevRootContinuity` (chain `prev_root → new_root` chaining, §3.4 / §3.6
step 4) is **NOT** an invariant of the full machine *including* `Reorg`.
`Onchain.Reorg` rebuilds the chain with `SelectSeq(onAdmittedChain, Survives)`,
`Survives(b) == b.batchNullifiers ∩ D = {}`. The module comment intends a
**suffix-only** revert, but the coded `SelectSeq` over an arbitrary
`D ⊆ onPending` over-approximates to **any-position** removal: dropping a
middle batch leaves a surviving later batch whose `prevRoot` still commits to a
now-removed predecessor, so local continuity breaks. Verified: continuity holds
under `PublisherSign ∨ Admit ∨ Confirm` (`[B5]`, length 6, `NoError`) and is
violated under the full Next with `Reorg` (counterexample at length ≤ 6).

This does **not** weaken the P2 result: no-double-spend is tested against the
live set `Acc`, holds under `Reorg` (`[B2]+[B3]+[B4]`), and does not lean on
continuity. We therefore certify continuity over the **admit/confirm fragment**
(`[B5]`) and document the Reorg gap here. **`module/Onchain.tla` was not
modified** (the task scopes work to the property package); the gap is a Reorg
over-approximation to flag for a future `Onchain` refinement (suffix-only revert
or a continuity-preserving replay), not a P2 safety hole.

Apalache cannot evaluate Onchain's cumulative `OnPrevRootContinuity` directly
(`UNION { … : j ∈ 1..(i-1) }` is a non-constant range — a known Apalache
limitation), so `[B5]` checks the logically-equivalent **local step form**
`OnPrevRootContinuityLocal` (adjacent-entry chaining + empty first prev_root),
defined in `property.tla`. By induction on the index the two forms are
equivalent; the local form is the one with constant-index access.

## Commands and outcome (full model)

All run by [`verify.sh`](./verify.sh), which stages `Foundations.tla`,
`Assumptions.tla`, `Onchain.tla` and `property.tla` into a temp dir (Apalache
resolves `EXTENDS` from the spec's own directory). All `NoError`:

| # | Check | `--init` / `--next` / `--inv` / `--length` | Outcome |
|---|---|---|---|
| B0 | typecheck | `typecheck property.tla` | OK |
| B1 | bounded safety | `OnInit` / `OnNext` / `INV` / 6 | NoError |
| B2 | inductive base | `OnInit` / `OnNext` / `IndInv_P2` / 0 | NoError |
| B3 | inductive step | `IndInvInit` / `OnNext` / `IndInv_P2` / 1 | NoError |
| B4 | implication | `IndInvInit` / `OnNext` / `INV` / 0 | NoError |
| B5 | continuity (fragment) | `OnInit` / `NextAdmitConfirm` / `INV_Continuity` / 6 | NoError |

`B2 + B3 + B4` = the unbounded no-double-spend proof over the full machine.
Full transcript in [`certificate.txt`](./certificate.txt).

## Negative control on the full model

A `/tmp` copy of `module/Onchain.tla` with the `[GATE]` conjunct
`cand.batchNullifiers ∩ cand.prevRoot = {}` deleted from `Admit`, checked with

```
apalache-mc check --cinit=OnConstInit --init=OnInit --next=OnNext --inv=INV --length=3 property.tla
```

returns a counterexample (`The outcome is: Error`, exit 12), 3-step trace:

```
State0  empty
State1  PublisherSign            -- publisher authorises the batch_message
State2  Admit batch = { nf3 }    -- nf3 enters onPending           (onDoubled = {})
State3  Admit batch = { nf3 }    -- nf3 re-inserted while present;
                                    with [GATE] gone, onDoubled = { nf3 }
                                    => OnNoDoubleSpend violated
```

(`nf3 = MkNullifier(0, SmokeCoinId(3))`.) The committed `Onchain.tla` is
unchanged; the `/tmp` copy and its `_apalache-out` were discarded.

## Cross-check vs Pass-3 (full-model verdict)

Pass-3 P2 label **HIGH** (sound under A3, A12; post-#40 also A15/A16). Apalache
verdict over the FULL on-chain model: **no-double-spend VERIFIED unbounded**
⇒ **confirmed at full on-chain fidelity** for the on-chain half of P2 — the
load-bearing first-spend-wins gate the audit names is now machine-checked on
the concrete `BatchInscription` admission path, not just the set abstraction.

| Property | Pass-3 | Abstract (Layer A) | Full Onchain (Layer B) |
|---|---|---|---|
| P2 No-Double-Spend (on-chain half) | HIGH | verified (unbounded) | **verified (unbounded)** |

## Remaining scope

- **Within-account half.** P2 also leans on the per-account coin-history
  discipline / `nf = Hc("Nullifier", nk ‖ coin.identifier)` derivation
  (Proofs Sec. 2.1 clauses 2/4/8). That lives in the `Proofs` (`Pr…`) module
  and is covered by P1 composition — the on-chain accumulator model here proves
  the global-accumulator half only.
- **Reorg refinement.** The Reorg continuity over-approximation above is a
  candidate `Onchain.tla` refinement (suffix-only revert) for a later phase;
  it does not affect the P2 safety verdict.
