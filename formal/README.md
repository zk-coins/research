# Formal models

Machine-checkable models of the zkCoins / Shielded CSV protocol **logic**, independent of any implementation. Each model takes one protocol claim, expresses it as a formal property, and lets a model checker either prove it (over a bounded state space) or return a concrete counterexample.

These models validate the **design**, not the code. They are deliberately implementation-agnostic, matching the spec's own stance (the human-readable specification at `docs.zkcoins.app/specification` "does not mandate Plonky2, Poseidon, or any particular proof system").

## Why this exists

An idea can be checked for logical soundness before a line of code is written. The two questions any model here answers:

1. **Consistency** — are the protocol's rules self-consistent (a satisfying model exists)?
2. **Entailment** — does the claimed guarantee *necessarily follow* from the rules, in **every** case the rules allow (not just the examples we imagined)?

A model checker answers both by exhaustive search over a bounded scope: no counterexample found ⇒ the property holds for that scope (a proof, not a test); a counterexample found ⇒ a concrete trace exposing the flaw.

## Models

| Path | Module | Property checked | Spec sections |
|---|---|---|---|
| `nullifier-chaining/` | `FirstSpendWins` | No coin is spent twice in the canonical Bitcoin log, even under reorgs | On-chain §3.5 / §3.6 / §3.7 / §3.9 / §3.10; Architecture §6.6 |

(Further models — balance conservation §2.1 clause 3, receive-anchoring §2.3.3 — slot in as sibling directories.)

## `nullifier-chaining/` — `FirstSpendWins.tla`

Models the zkCoins post-#21 / post-#25 design: every node admits a `SpendRecord` only when its **published-in-the-clear** nullifiers are disjoint from the locally-rebuilt accumulator (On-chain §3.6 step 6), and Bitcoin produces no canonical reorgs deeper than 5 blocks (Architecture §6.6). The model verifies that, under those rules, no coin is ever spent twice in the canonical log.

- **Anchor.** Bitcoin is modelled as nothing more than an append-only, totally-ordered log of admitted `SpendRecord`s with a bounded reorg depth `K − 1`. The completed prefix (records at depth ≥ `K`) is immutable per the spec's `K = 6` finality threshold.
- **Discipline.** A record is admitted only if its published `nf` set is disjoint from the running accumulator (first-spend-wins). The accumulator absorbs nfs **at admission**, not at finality — matching On-chain §3.10's "admission gates the accumulator, finality gates receiver credit" asymmetry.
- **Claim.** `NoDoubleSpend`: no nullifier appears in two distinct records of the current canonical log. Because completed records never reorg out, this extends to "no two records ever in `completed` share an nf" — i.e. the `completed` state from §3.10 is absolute under the reorg-bound assumption.

### Compared to the earlier `NullifierChaining.tla` (removed)

The previous version of this model encoded the pre-#21 per-batch `prev_root → post_root` chaining: each transition carried claimed roots, an aggregator pattern bundled up to `MAX_IN_COINS = 8` source proofs, and double-spend protection lived in-circuit. `zk-coins/docs#21` removed all of that — spent nullifiers are now published verbatim on-chain, and `docs#25` formalised the three-state lifecycle in On-chain §3.10. The property the model checks (no double-spend) is unchanged; the mechanism it encodes is dramatically simpler, and so is the model: no claimed roots, no `Chains` predicate, no aggregator, no recursion-shape probing. The full state space at 4 coins, `K = 6`, log bound 5 is checked in seconds.

### Modelling assumptions (stated openly)

A proof is only meaningful relative to what it assumes. This model assumes:

- **A1 · Nullifier injectivity.** `nf = Hc("Nullifier", nk ‖ coin.identifier)` is injective, so the model identifies a nullifier with the coin it spends.
- **A2 · Thin Bitcoin anchor.** Bitcoin is an append-only, totally-ordered log of admitted records; reorgs drop at most `K − 1` records from the tail (Architecture §6.6: "no canonical reorgs deeper than 5 blocks"). No Script, UTXO, or mining.
- **A3 · Admission predicate abstracted to first-spend-wins.** The other §3.5+§3.6 admission checks (parser, `block_anchor` bounds, signature validity, nullifier-`inr` binding, canonical order) reject ill-formed records but do not affect the nullifier-set logic this model verifies, so they are folded into the proposer's freedom (records range over `SUBSET Nullifier ∖ {∅}`).

Discharging the abstracted checks belongs to the proof-system / signature / structural layers, not here.

### Running it

Requires TLA+'s `tla2tools.jar` (the [TLA+ tools](https://github.com/tlaplus/tlaplus/releases)) and a JRE:

```sh
java -jar tla2tools.jar -config FirstSpendWins.cfg FirstSpendWins.tla
```

The config is small but exhaustive: `Nullifier = {n1, n2, n3, n4}`, `K = 6`, `Bound = 5`. Expected result: `TypeOK`, `NoDoubleSpend`, and `AdmissionFreshness` all hold; no counterexample.

### Watching the model checker earn its keep

In `FirstSpendWins.tla`, delete the conjunct marked `[GATE]` in the `Admit` action (the `r ∩ Acc(log) = {}` first-spend-wins check) and re-run TLC. It returns a double-spend trace within seconds — demonstrating that the model distinguishes the correct admission discipline from a flawed one. Restore the conjunct and the property holds again.
