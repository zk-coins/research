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

## Meta-assumptions (the unprovable foundation)

A1–A17 are the explicit, named cryptographic and operational axioms that Apalache will not prove and that the protocol composition consumes. Below them sits a second layer — the **meta-assumptions** — which cannot be axiomatized inside the verification because they are *about* the verification itself. We list them here so the 100% claim is honest: every certificate this directory produces is conditional on M1–M4 holding.

| ID | Meta-assumption | Why we cannot prove it inside Apalache | What its failure would invalidate |
|---|---|---|---|
| **M1** | **Apalache soundness.** When Apalache reports "no error found" for an invariant, the invariant truly holds in every reachable state. | Apalache is implemented by humans on top of an SMT solver (Z3). A bug in Apalache's TLA+→SMT translation or in Z3 itself could declare a false invariant. | Every certificate. Mitigation: pin Apalache + Z3 versions; cross-check spot properties with TLC bounded; manual inspection of inductive invariants. |
| **M2** | **TLA+ ↔ spec fidelity.** The TLA+ modules in `formal/module/` are a faithful translation of the prose specification in `docs.zkcoins.app/specification`. Every clause is modeled; no clause is silently weakened. | This is a *translation* judgment, not a logical one. If I (the modeler) misread §3.6 step 6, I encode the misreading and Apalache then verifies the wrong thing. | Per-module: a misencoded module leaks to every property invoking it. Mitigation: per-module review (Pass-4 audit); cross-check against Pass-3 confidence labels — divergence is the trip-wire. |
| **M3** | **Adversary-model completeness.** The Pass-3 §2 adversary model (PPT, controls publishers, nodes, relays, network; observes Bitcoin; bounded by A1–A17; cannot compromise the wallet's SPEND branch) captures every real-world adversary capability relevant to the protocol. | An adversary capability outside the modeled space is by definition outside the proof's scope. This is the irreducible limit of any formal verification — the model only protects against modeled adversaries. | Properties tested against the adversary. Mitigation: keep the model conservatively wide; review adversary-model deltas when the threat landscape shifts (e.g. new ZK-attack classes published). |
| **M4** | **Property-statement correctness.** The TLA+ statements of `INV_P1`…`INV_P10` (and any liveness `Temporal_P9`) faithfully express what the spec promises and what users need. | This is a *specification* judgment — does the formal property capture the security intent? If I formalize "no double-spend" as "no nf appears twice in the log" but the real property needs to include receiver-credit decision rules, my formalization is too weak. | Per-property: an under-specified property can be "verified" yet leave real risk. Mitigation: each `INV_Pn` is paired with a `notes.md` quoting the prose spec section it formalizes; cross-check against Pass-3 §4 game-style statements. |

**Where the real residual risk concentrates:** M2 and M4 are the load-bearing meta-assumptions. M1 is mitigated by tool maturity (Apalache + Z3 are widely used and bug-discoveries are public). M3 is structurally irreducible — no formal method escapes the "the adversary model defines the protection envelope" boundary.

A Pass-4 audit *of the formal modeling itself* — separate from the spec audit — is the mechanism for second-pair-of-eyes coverage on M2 and M4. We will perform this as part of Phase 4 (cross-check vs Pass-3): every property where the Apalache verdict disagrees with the Pass-3 manual label is a M2/M4 detection signal.

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

Initialised 2026-06-06. Phase 0 complete (P02 verified unbounded). Phase 1 complete: all eight `module/` files type-check and the five state-machine modules pass an Init/Next reachability smoke check (run `module/verify-modules.sh`). See [`100-percent-verification-plan.md`](./100-percent-verification-plan.md) §Progress for live status per property.

## Reproducibility

Every verification result in this directory MUST be re-runnable from a clean clone with one command. Apalache is the only dependency. Per-property `notes.md` records the Apalache version + command + output.
