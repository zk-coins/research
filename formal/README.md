# Formal verification of the zkCoins specification

Machine-checkable models and proofs of the zkCoins protocol logic, independent of any implementation. This directory holds the artifacts for the **100% Logical Verification initiative** declared by the project lead on 2026-06-06.

## Goal

**Every security property the specification claims is mechanically proven to follow from the spec's clauses plus a finite, named set of cryptographic assumptions.** No "manual game argument" — only proofs a tool will accept and a third party can re-run.

## What "100%" means in this directory

| Class | Definition | What it proves |
|---|---|---|
| **Bounded model checking** | Exhaustive search up to fixed bounds (e.g. ≤ N accounts, ≤ M transitions) | Property holds within the bounds. Not 100% in our sense. |
| **Unbounded symbolic model checking** | SMT-backed inductive invariants over the unbounded state space | Property holds for **all** N. **100% for state-machine properties.** |
| **Theorem proving** | Mechanical derivation in a proof assistant from named axioms | Property holds for all inputs, all adversaries, under the stated axioms. Highest standard. |

**Our 100% target = unbounded symbolic model checking (Apalache) for every property in §"Properties under verification" below, with the cryptographic primitives (§"Axiomatized assumptions") taken as ideal functionalities.** This is the UC-style decomposition: a tool proves the protocol composes the primitives correctly; the primitives themselves are stated as axioms and the residual risk that a primitive is weaker than assumed is acknowledged outside this directory.

See [`100-percent-verification-plan.md`](./100-percent-verification-plan.md) for the operational plan: phases, deliverables, progress tracking, reproducibility.

## What 100% does NOT cover

Mechanical verification proves composition, not primitive strength. The following items are **explicitly outside** the 100% target in this directory:

- **R1** Poseidon-Goldilocks Plonky2-instance algebraic-attack margin (~95 bits, BBLP22) — narrowing through Ethereum Foundation Cryptanalysis Initiative, concludes Dec 2026.
- **R2** Plonky2 cyclic-recursion soundness — taken as A1 axiom; not proven here.
- **R3** Reference-implementation review — separate work, gated on F15 closure.
- **R4** Novel attack patterns not in the public corpus — irreducible.

These are documented in the [Pass-3 audit §8 residual-risk inventory](../audit/2026-06-06.03.md).

## Method

**Tool: Apalache** ([apalache.informal.systems](https://apalache.informal.systems)) — TLA+ specification language, SMT-backed symbolic model checker, proves invariants over the unbounded state space via inductive invariants. Industrial-scale TLA+ users include Tendermint, Cosmos, MongoDB.

**Why Apalache and not Lean4 / Coq / EasyCrypt:**

- Apalache verifies state-machine and composition properties on the protocol level, which is what we need.
- The cryptographic primitives can be axiomatized as ideal functionalities (UC-style) — this collapses the need for a separate proof-assistant pass on each primitive.
- TLA+ has a well-defined translation from the kind of pseudo-code the spec uses; the gap is small.
- Apalache verification cycles are minutes-to-hours per property, not weeks of human proof labor.
- EasyCrypt would be more thorough on primitive composition but adds months of effort for a marginal increment past axiomatization.

**Why not pure TLC (the classical TLA+ model checker):** TLC is bounded only. The existing [`nullifier-chaining/FirstSpendWins.tla`](./nullifier-chaining/FirstSpendWins.tla) was a TLC model with `Bound = 5`. It is a useful smoke test but not 100% under our definition.

## Properties under verification

Each property carries the same number as in the [Pass-3 audit §4](../audit/2026-06-06.03.md).

| ID | Property | Spec source | Verification target |
|---|---|---|---|
| **P1** | No-Forgery | §2.1 + §3.2 + §3.6 | Apalache invariant + axiomatized BIP-340 EUF-CMA |
| **P2** | No-Double-Spend | §3.6 + §3.7 + §3.10 | Apalache invariant (unbounded, with reorg) |
| **P3** | Per-Asset Balance Conservation | §2.1 clause 3 + §6.5 | Apalache invariant per asset |
| **P4** | Zero-Knowledge | §2.1 clause 9 | Apalache + axiomatized Plonky2 ZK |
| **P5** | On-chain Privacy / Unlinkability | §3.1 + §3.5 | Apalache (with adversary view) |
| **P6** | Client-Side Validation | §2.3.3 + §3.10 | Apalache invariant (receiver decision rule) |
| **P7** | Issuance Authenticity v1 | §6.5 + §4.3 | Apalache + axiomatized BIP-340 |
| **P8** | Transport Confidentiality + Authentication | §4.2 + §4.3 | Apalache + axiomatized NIP-44 + ACK-nonce |
| **P9** | Recovery Completeness | §4.5 + §4.6 | Apalache liveness property |
| **P10** | Capability Discipline | §5.1 — §5.8 | Apalache invariant (access predicate) |

## Axiomatized assumptions

The following primitives are taken as ideal functionalities — Apalache does not prove them; it proves the protocol composes them correctly. A1–A14 mirror the Pass-3 audit. A15–A17 are additional **derived-primitive** axioms added 2026-06-06 to reduce TLA+ modeling effort without hollowing the proof (each follows from a published reduction to A1–A14 above).

| ID | Axiom | Used by |
|---|---|---|
| A1 | Plonky2 knowledge-soundness | P1, P7 |
| A2 | Plonky2 zero-knowledge | P4 |
| A3 | Poseidon-Goldilocks collision resistance (Plonky2 instance, 8+22 rounds) | All `Hc(...)` |
| A4 | Poseidon-Goldilocks sponge security | All variable-length `Hc` |
| A5 | SHA-256 collision resistance | P1, P7, P8, P10 |
| A6 | SHA-256 preimage resistance | P1, P7 |
| A7 | BIP-340 Schnorr EUF-CMA over secp256k1 | P1, P7, P8, P10 |
| A8 | secp256k1 discrete log + ECDH | P4, P8 |
| A9 | HKDF-SHA-256 as PRF/KDF | P4, P8 |
| A10 | NIP-44 v2 IND-CCA | P8 |
| A11 | NIP-59 gift-wrap envelope confidentiality | P8 |
| A12 | Bitcoin honest-majority + no reorgs ≥ 6 blocks | P2, P6 |
| A13 | Per-node eclipse resistance (own bitcoind) | P6 |
| A14 | TLS 1.2 EMS / TLS 1.3 / Tor v3 for the pull endpoint | P10 |
| **A15** | **Half-aggregation soundness** — §3.3's multi-scalar check `s_agg·G == Σⱼ aⱼ·(Rⱼ + eⱼ·Pkⱼ)` with coefficients `aⱼ = H(z ‖ le32(j))`, `z = H("zkCoins/v1/HalfAgg" ‖ …)` accepts iff every constituent BIP-340 signature `(Rⱼ, sⱼ)` is valid under `(Pkⱼ, mⱼ)`. Reduction: standard Stinson-Wei aggregation defense; the transcript-bound coefficients eliminate rogue-key attacks; conditional on A7 (BIP-340 EUF-CMA). Without A15, `Onchain.tla` would have to model the elliptic-curve arithmetic byte-for-byte. | P1, P2 |
| **A16** | **Merkle / SMT collision-resistance lifting** — §1.7.5 Poseidon Merkle tree (over leaf lists) and §1.7.6 sparse Merkle trees (NfAcc, CoinHist) produce collision-resistant roots: two distinct leaf-sets / key-value maps producing the same root imply a Poseidon collision. Reduction: standard Merkle-tree CR proof; per-level domain separation in `Hc("…/Node", i, l, r)` rules out cross-level confusion; conditional on A3. Without A16, every property invoking a Merkle root would have to model the tree hash-by-hash. | P1, P2, P3, P6 |
| **A17** | **`serialize(AccountState)` canonical** — §1.7.4's byte serialization is **injective**: two distinct `AccountState` values produce distinct byte strings (no two map to the same `ash`). Reduction: §1.7.4 pins field order, omits-zero balances, requires ascending `asset_id` sort, and fixes widths; together these make collisions correspond exactly to byte-string equality — provably injective by direct construction (not even conditional on a cryptographic assumption). Without A17, `Foundations.tla` would have to model byte-string concatenation rules. | P3, P6 |

## Directory layout

```
formal/
├── README.md                                  ← this file (initiative framing)
├── 100-percent-verification-plan.md           ← phases, deliverables, progress
├── module/                                    ← formal model of the spec
│   ├── Foundations.tla
│   ├── Proofs.tla
│   ├── Onchain.tla
│   ├── Transport.tla
│   ├── Access.tla
│   ├── Architecture.tla
│   ├── Assumptions.tla
│   └── Adversary.tla
├── property/                                  ← per-property verification artifacts
│   ├── P01_NoForgery/
│   │   ├── property.tla
│   │   ├── invariants.tla
│   │   ├── apalache.cfg
│   │   ├── certificate.txt
│   │   └── notes.md
│   ├── P02_NoDoubleSpend/
│   ├── …
│   └── P10_CapabilityDiscipline/
└── nullifier-chaining/                        ← legacy: TLC bounded; superseded by P02_NoDoubleSpend
    ├── FirstSpendWins.tla
    └── FirstSpendWins.cfg
```

## Status

Initialised 2026-06-06. Plan document complete; module modeling pending. See [`100-percent-verification-plan.md`](./100-percent-verification-plan.md) §Progress for live status per property.

## Reproducibility

Every verification result in this directory MUST be re-runnable from a clean clone with one command. Apalache is the only dependency. Per-property `notes.md` records the Apalache version + command + output.
