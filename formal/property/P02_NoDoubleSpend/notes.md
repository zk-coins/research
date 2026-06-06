# P02 — No-Double-Spend — notes

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
  canonical, reproducible runner for this property — the §8 reproducibility
  contract's "one command" is `./verify.sh`.

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
apalache-mc check --cinit=ConstInit --init=Init --next=Next --inv=NoDoubleSpend --length=2 property.tla
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
