# Formal models

Machine-checkable models of the zkCoins / Shielded CSV protocol **logic**, independent of any implementation. Each model takes one protocol claim, expresses it as a formal property, and lets a model checker either prove it (over a bounded state space) or return a concrete counterexample.

These models validate the **design**, not the code. They are deliberately implementation-agnostic, matching the spec's own stance (the human-readable specification at `docs.zkcoins.app/specification` "does not mandate Plonky2, Poseidon, or any particular proof system").

## Why this exists

An idea can be checked for logical soundness before a line of code is written. The two questions any model here answers:

1. **Consistency** — are the protocol's rules self-consistent (a satisfying model exists)?
2. **Entailment** — does the claimed guarantee *necessarily follow* from the rules, in **every** case the rules allow (not just the examples we imagined)?

A model checker answers both by exhaustive search over a bounded scope: no counterexample found ⇒ the property holds for that scope (a proof, not a test); a counterexample found ⇒ a concrete trace exposing the flaw.

## Models

| Path | Property checked | Spec sections |
|---|---|---|
| `nullifier-chaining/` | No coin is spent twice in the finalised ledger, even under Bitcoin reorgs | Proofs §2.1 clause 4; On-chain §3.6 / §3.7 |

(Further models — balance conservation §2.1 clause 3, receive-anchoring §2.3.3 — slot in as sibling directories.)

## `nullifier-chaining/` — TLA+

Models the nullifier-accumulator chaining over a thin Bitcoin anchor:

- **Anchor (TLA+ `A3`).** Bitcoin is modelled as nothing more than an append-only, totally-ordered log of inscribed batches with eventual finality: the finalised prefix never changes; the last `K` batches (the pending zone) may be reorged away. No Script, UTXO, or mining is modelled — the protocol uses none of it. This is the standard honest-majority / k-confirmation anchor.
- **Discipline.** Every transition proves its input nullifiers are **non-members** of the accumulator as it stands just before it, then inserts them; per-transition `prev_root → post_root` roots chain within a batch and across batch boundaries.
- **Claim.** `NoDoubleSpend`: no nullifier is inserted by two distinct finalised transitions. Transient duplicates between a pending branch and a reorged-away branch do not count — only the finalised order is the ledger.

### Modelling assumptions (stated openly)

A proof is only meaningful relative to what it assumes. This model assumes:

- **A1 · Root binds set.** The accumulator root is abstracted by the set of nullifiers it commits to; a prover lying about a root is *not* modelled. That binding is the SNARK knowledge-soundness + SMT collision-resistance assumption — a separate proof obligation.
- **A2 · Nullifier injectivity.** `nf = H(nk, coin.identifier)` is injective, so the model identifies a nullifier with the coin it spends.
- **A3 · Thin Bitcoin anchor** (above).

These assumptions are the boundary of the proof: the model certifies the protocol logic *given* them. Discharging A1 belongs to the proof-system layer, not here.

### Running it

Requires TLA+'s `tla2tools.jar` (the [TLA+ tools](https://github.com/tlaplus/tlaplus/releases)) and a JRE:

```sh
java -jar tla2tools.jar -config NullifierChaining.cfg NullifierChaining.tla
```

The config is small but exhaustive (3 coins, finality depth `K = 2`, batches of up to 2 transitions). Expected result: all invariants hold, no counterexample.

### Watching the model checker earn its keep

In `NullifierChaining.tla`, delete the conjunct marked `[GATE]` in `Chains(...)` (the non-membership check) and re-run TLC. It returns a finalised double-spend trace within seconds — demonstrating that the model distinguishes the correct chaining discipline from a flawed one. Restore the conjunct and the property holds again.
