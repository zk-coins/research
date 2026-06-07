# 100% Logical Verification Plan — zkCoins v1 Specification

**Initiated:** 2026-06-06
**Owner:** project lead
**Spec baseline:** [`zk-coins/docs@b6972b8`](https://github.com/zk-coins/docs/commit/b6972b8) — current `develop` tip, equal to the prior baseline `a7a9f97` plus exactly one commit: [`docs#40`](https://github.com/zk-coins/docs/pull/40) (Variant-2 constant-per-batch on-chain redesign), **merged 2026-06-06**. The baseline was advanced from `a7a9f97` to `b6972b8` per decision **D1** (model against the post-`docs#40` form; see §Dependencies). The earlier `a7a9f97` pin and the Pass-3 audit predate `docs#40`; §3-dependent properties (P2, P5, P6) are therefore reconciled against the new on-chain layer in Phase 4.

## 0 · Declaration of intent

The project lead has declared on 2026-06-06 that the target is not "towards 100%" but **the full 100%**. This document is the operational plan to reach that target — every spec-level property mechanically proven, not manually argued.

This goal supersedes the Pass-3 audit's confidence labels (which were honest game-style manual arguments). Pass-3 stays as a historical artifact and as the priors / cross-check oracle for the verification work; the **mechanical certificates produced here become the load-bearing evidence.**

## 1 · Scope

### 1.1 In scope

Every property in the [Pass-3 audit §4](../audit/2026-06-06.03.md):

- P1 No-Forgery
- P2 No-Double-Spend
- P3 Per-Asset Balance Conservation
- P4 Zero-Knowledge
- P5 On-chain Privacy / Unlinkability
- P6 Client-Side Validation
- P7 Issuance Authenticity v1
- P8 Transport Confidentiality + Authentication
- P9 Recovery Completeness
- P10 Capability Discipline

Each is verified as a TLA+ invariant or temporal property using Apalache, with the spec's cryptographic primitives axiomatized as ideal functionalities (A1–A17; see [README §Axiomatized assumptions](./README.md#axiomatized-assumptions)). A1–A14 are the established-primitive set inherited from the Pass-3 audit; A15–A17 are **derived-primitive axioms** added 2026-06-06 (half-aggregation soundness, Merkle/SMT CR lifting, `serialize(AccountState)` injectivity) — each follows from a published reduction to A1–A14 and shaves modeling effort without hollowing the proof.

### 1.2 Out of scope

- **A1–A14 themselves.** Apalache is not asked to prove that BIP-340 is EUF-CMA, that Plonky2 is knowledge-sound, that Poseidon-Goldilocks is collision-resistant, etc. Those are axiomatized; if a primitive turns out to be weaker than its axiom, no spec-level proof can recover.
- **The reference implementation.** This plan verifies the specification. The implementation is a separate gate ([F15](../audit/2026-06-06.03.md#f1-f15-f9-f12--carry-forward-status)).
- **Performance / DoS surface.** Apalache is a logic tool; it does not model wall-clock cost or rate-limiting.
- **Operational hygiene** (Tor / SNI / replication-operator independence) — these are out-of-protocol concerns the spec already documents.

The boundary between "in scope" and "out of scope" matches the Pass-3 audit's [§8 Residual-risk inventory](../audit/2026-06-06.03.md#8--honest-residual-risk-inventory) — R1–R4.

## 2 · Method

### 2.1 Tool

**Apalache** ([apalache.informal.systems](https://apalache.informal.systems)) — SMT-backed symbolic model checker for TLA+, capable of **inductive invariant** proofs over the unbounded state space. Version pinned per-property in each `notes.md`.

### 2.2 Why this tool and not alternatives

| Considered | Verdict | Reason |
|---|---|---|
| **TLC** (classical TLA+ MC) | rejected | bounded only; not 100% under our definition |
| **Apalache** | chosen | unbounded; protocol-level; tractable iteration cycles |
| **Lean4 / Coq** | deferred | would prove primitives + composition, but adds 3–6 months for a marginal increment past axiomatization |
| **EasyCrypt** | deferred | game-based crypto proofs, ideal for primitive composition, but the smallest tooling community and steep learning curve |
| **Tamarin / ProVerif** | rejected | Dolev-Yao symbolic crypto cannot model ZK primitives cleanly |

### 2.3 Decomposition principle

The protocol is decomposed into:

- **State machine** — `AccountState` evolution, on-chain log admission, lifecycle states `pending` / `completed` / `failed`, multi-node selection, transport delivery + ACK, recovery. Verified via Apalache invariants.
- **Cryptographic primitives** — axiomatized as ideal functionalities (signature oracles, hash random oracles, ZK simulator). Apalache models them as nondeterministic operators with the stated security property baked into the model.
- **Adversary** — bounded by A1–A14; otherwise omniscient. Models all combinations the audit Pass-3 §2 adversary model permits.

A verification result of the form *"under axioms A1–A14, the protocol invariant `INV_Pn` holds in all reachable states"* is then a **100% machine-checked proof of Pn at the protocol-composition level**.

## 3 · Phases and deliverables

**Total estimate:** 1–1.5 weeks continuous, 2 weeks worst case (reduced from initial 1.5–2 weeks by adopting A15–A17).

| Phase | Target time | Output |
|---|---|---|
| 0 Setup | 0.5–1 day | Apalache running, legacy `FirstSpendWins.tla` ported to unbounded |
| 1 TLA+ modeling | 2–3 days | Complete `formal/module/` (8 files) |
| 2 Property formalization | 1–2 days | `property/Pn_<Name>/property.tla` for P1–P10 |
| 3 Apalache verification | 3–5 days | `certificate.txt` per property |
| 4 Cross-check vs Pass-3 | 1–2 days | Reconciliation table, divergences logged |
| 5 Documentation + sign-off | 1–2 days | Audit doc references certificates, reproducibility verified |
| 6 Residual escalation | (only if needed) | per-property fallback per §4 |

### Phase 0 — Setup (target: 0.5–1 day)

- Install Apalache on the verification host (local Apple Silicon workstation).
- Verify Apalache version + basic smoke test.
- Port the existing [`nullifier-chaining/FirstSpendWins.tla`](./nullifier-chaining/FirstSpendWins.tla) from TLC-compatible to Apalache-compatible form; reproduce its property as an **unbounded** verification (no `Bound`). Demonstrates the toolchain works end-to-end.
- **Deliverable:** `formal/property/P02_NoDoubleSpend/` with a passing unbounded Apalache run.

### Phase 1 — Formal modeling of the specification (target: 2–3 days, was 3–5 days before A15–A17)

Build the `formal/module/` directory. Each module is a TLA+ file modeling one spec section. The A15–A17 axioms collapse what would otherwise be byte-level / curve-arithmetic modeling into ideal-operator calls — saving 1–2 days off Phase 1.

| Module | Models | Source spec sections | Axioms used |
|---|---|---|---|
| `Foundations.tla` | Types: Address, Pkᵢ, ash, ocr, inr, nf, asset_id, AccountState, Coin, CoinProof, Invoice (post-F9) | §1 | A17 (serialize) |
| `Proofs.tla` | Compliance predicate `C` as a TLA+ operator; clauses 1–9; witness type; canonical empty account | §2.1, §2.2 | A1, A2, A3, A16 |
| `Onchain.tla` | Admission state machine (§3.5 parser + §3.6 scanner); first-spend-wins with within-record rollback (F16); nullifier accumulator; §3.10 lifecycle | §3.5, §3.6, §3.7, §3.9, §3.10 | A7, A12, A15, A16 |
| `Transport.tla` | DeliveryEvent + ACK with `ack_nonce` (F17); k-replication; self-delivery | §4.2, §4.3, §4.6 | A7, A8, A9, A10, A11 |
| `Access.tla` | OwnershipProof, GrantProof, zkview, zkavk, BalanceAttestation; PullChallenge with `chan_bind` | §5.1 — §5.8 | A5, A7, A14 |
| `Architecture.tla` | Multi-node composition; latest-state selection (F12); reorg-bound assumption | §6.3, §6.6 | A12, A13 |
| `Assumptions.tla` | Axiomatized A1–A17 as TLA+ operators with stated security properties | — | — |
| `Adversary.tla` | PPT adversary as nondeterministic environment; capabilities per Pass-3 §2 | — | — |

Process: one subagent per module in parallel; harmonization pass at the end.

**Deliverable:** complete `formal/module/` directory, all files type-check cleanly under Apalache.

### Phase 2 — Property formalization (target: 1–2 days)

Each P1–P10 stated as a TLA+ invariant or temporal property in `formal/property/Pn_<Name>/property.tla`. Where useful, an inductive invariant is supplied alongside (some properties need them; Apalache cannot always infer them).

Template per property:

```tla
---------------- MODULE property ----------------
EXTENDS Module.Foundations, Module.Proofs, Module.Onchain, ...

\* The property to verify, in the protocol's own language.
INV_Pn == ...

\* Optional inductive strengthening (if Apalache cannot infer one).
IndInv_Pn == INV_Pn /\ ...

\* TLA+ temporal property (for liveness like P9).
Temporal_Pn == [](...)
==================================
```

**Deliverable:** `formal/property/` populated with stubs for all 10 properties.

### Phase 3 — Apalache verification (target: 3–5 days)

For each property, run Apalache with the inductive invariant. Three possible outcomes:

| Outcome | Action |
|---|---|
| **`No error found`** | Property verified. Save Apalache output as `certificate.txt`. Update progress table. |
| **`Inductive invariant not strong enough`** | Strengthen `IndInv_Pn`; retry. If unsuccessful after 3 strengthenings, escalate (see §4 Risk). |
| **Counter-example trace** | Either model bug or spec bug. Investigate. If spec bug, file finding F-NN and a docs PR; if model bug, fix model. |

Iterations expected: 1–3 per property. Realistic spread: P2, P10 are easiest; P1, P4, P8 (cryptographic composition) are hardest.

**Deliverable:** `certificate.txt` per property + cross-check table.

### Phase 4 — Cross-check + reconciliation (target: 1–2 days)

For each property, compare the Apalache verdict against the Pass-3 manual confidence label:

| Pass-3 label | Apalache verdict | Reconciliation |
|---|---|---|
| HIGH | verified | confirmed |
| HIGH | counter-example | **Pass-3 was wrong** → file spec finding |
| MEDIUM | verified | manual review may have been too cautious; lift Pass-3 |
| MEDIUM | counter-example | **Pass-3 found the issue, Apalache confirms** → file spec finding |
| HIGH | inductive-invariant-failed | inconclusive — escalate to Phase 6 |

Any divergence is logged in `formal/property/Pn_<Name>/notes.md` with the resolution path.

**Deliverable:** the Pass-4 reconciliation table in [`CERTIFICATE.md`](./CERTIFICATE.md), carrying the mechanical certificate references. The Pass-3 audit document itself is a **read-only snapshot** and is deliberately not amended; the Pass-4 cross-check lives in `formal/` alongside the certificates it references.

### Phase 5 — Documentation + sign-off (target: 1–2 days)

- All `certificate.txt` files committed.
- `formal/property/STATUS.md` table marked all green.
- Certificate hyperlinks published in [`CERTIFICATE.md`](./CERTIFICATE.md) and [`property/STATUS.md`](./property/STATUS.md) (the Pass-3 snapshot stays read-only).
- Reproducibility documented per-property.

**Deliverable:** complete formal package, ready-for-review-PR on `zk-coins/research`.

### Phase 6 — Residual escalation (only if needed)

For any property Apalache cannot prove (e.g. inductive invariant intractable, decidability boundary hit), fallback options:

- **Manual TLA+ proof in TLAPS** (TLA+ Proof System) — heavier, but still mechanical.
- **Reduction to a previously-proven property** — sometimes Pn follows from Pm.
- **Stronger axiomatization** — push more into A1–A14 if the spec's primitive use is the actual proof obligation.
- **Lean4 fallback** — for genuinely hard composition properties, hand-build the proof in Lean4. Cost: weeks per property.

If a property reaches Phase 6, it is the only one outside the 100% guarantee until resolved.

## 4 · Risks and contingencies

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Apalache inductive invariant intractable for Pn | medium | Phase-6 escalation | start with TLAPS fallback or stronger axiomatization |
| Real spec bug found (counter-example) | medium | spec PR + audit revision | desired outcome: that's what verification is for |
| Apalache tool bug | low | debugging detour | report upstream; pin known-good version |
| docs#40 (Variant-2) merges mid-Phase-1 | high | rework §3 modeling | model against docs#40 branch from the start |
| Time blowout past 1.5 weeks | medium | extend; the goal is 100%, not 100%-by-date | keep daily progress diary |

## 5 · Dependencies

### Hard

- **docs#40** ([Variant-2 on-chain redesign](https://github.com/zk-coins/docs/pull/40)) — **RESOLVED.** `docs#40` merged into `develop` on 2026-06-06 (`b6972b8`), making the clean post-redesign baseline available immediately. Per decision **D1**, the spec baseline was advanced from `a7a9f97` to `b6972b8` and `Onchain.tla` (and every §3-dependent property) is modelled against the post-`docs#40` form — equivalent to the original option (1) "wait for merge", now that the merge has happened. No retrofit work is incurred.

  Net change vs the pre-`docs#40` design that `Onchain.tla`/P2 must reflect: the on-chain object is now a constant-size `BatchInscription` carrying `prev_root → new_root` (not per-record raw nullifiers); nullifiers live off-chain in a `BatchBundle`; first-spend-wins is enforced by (a) sequential `prev_root` continuity + stale-rejection and (b) the `AggregateBatchProof`'s in-circuit obligation that `new_root = SMT.insert_many(prev_root, batch_nullifiers)` with every batch nullifier a non-member of `prev_root`. The abstract accumulator-level no-double-spend invariant is unchanged.

### Decisions (resolved 2026-06-06)

- **D1 — baseline:** advance to `b6972b8` (post-`docs#40`). Resolved above.
- **D2 — verification host:** Apalache runs locally/interactively on the project's Apple Silicon workstation. Pinned tool versions recorded per-property in `notes.md`.
- **D3 — derived-primitive axioms A15–A17:** accepted (half-aggregation soundness, Merkle/SMT CR lifting, `serialize(AccountState)` injectivity); each reduces to A1–A14. Note: `docs#40` renamed §3.3 "Half-aggregation" → "Off-chain signature handling" and moved aggregation into the `AggregateBatchProof` witness as an optimisation; A15's applicability to the new form is re-checked when `Onchain.tla` is built.

### Soft

- Apalache tooling on the verification host.
- TLA+ + Apalache local IDE (optional, helps iteration).
- Reproducibility on an always-on workstation for nightly verifications.

## 6 · Progress

Per-property status — updated as Phase 3 advances.

| Property | Phase | Apalache status | Cross-check vs Pass-3 | Certificate |
|---|---|---|---|---|
| **P1** No-Forgery | Phase 3 done | **verified** — provenance unbounded; signature-level statement bounded + documented reduction | confirmed (HIGH) | [`property/P01_NoForgery/certificate.txt`](./property/P01_NoForgery/certificate.txt) |
| **P2** No-Double-Spend | Phase 3 done (two layers) | **verified unbounded** — abstract (Phase 0) + full `Onchain` machine; chain continuity bounded (documented) | confirmed (HIGH) | [`property/P02_NoDoubleSpend/certificate.txt`](./property/P02_NoDoubleSpend/certificate.txt) |
| **P3** Balance Conservation | Phase 3 done | **verified unbounded** (ghost supply/mint ledgers over the compliance predicate) | confirmed (HIGH, creator-bound v1 model) | [`property/P03_BalanceConservation/certificate.txt`](./property/P03_BalanceConservation/certificate.txt) |
| **P4** Zero-Knowledge | Phase 3 done | **verified** — publication-gate flow invariant unbounded; indistinguishability itself = A2 (axiom, scoped) | confirmed (HIGH) at composition level | [`property/P04_ZeroKnowledge/certificate.txt`](./property/P04_ZeroKnowledge/certificate.txt) |
| **P5** On-chain Privacy | Phase 3 done | **verified** — publisher-only-link unbounded; structural surface facts labelled; network half out of scope | confirmed; **strengthened post-`docs#40`** (on-chain `k_j` leak eliminated; publisher pubkey is the new, sole on-chain link) | [`property/P05_OnchainPrivacy/certificate.txt`](./property/P05_OnchainPrivacy/certificate.txt) |
| **P6** Client-Side Validation | Phase 3 done | **verified unbounded** (§2.3.3 receive gate composed over the full on-chain machine) | confirmed (HIGH) | [`property/P06_ClientSideValidation/certificate.txt`](./property/P06_ClientSideValidation/certificate.txt) |
| **P7** Issuance Authenticity v1 | Phase 3 done | **verified unbounded** | confirmed (HIGH) | [`property/P07_IssuanceAuthenticity/certificate.txt`](./property/P07_IssuanceAuthenticity/certificate.txt) |
| **P8** Transport Confidentiality + Auth | Phase 3 done | **verified unbounded** (ACK nonce-freshness = the merged F17 fix) | confirmed (HIGH; F17 LOW resolved in spec and model) | [`property/P08_TransportConfAuth/certificate.txt`](./property/P08_TransportConfAuth/certificate.txt) |
| **P9** Recovery Completeness | Phase 3 done | **verified** — safety (no false-accept) unbounded; liveness via enabledness surrogate (Apalache 0.58.0 has no fairness support) | confirmed (HIGH correctness / MEDIUM liveness — mirrored) | [`property/P09_RecoveryCompleteness/certificate.txt`](./property/P09_RecoveryCompleteness/certificate.txt) |
| **P10** Capability Discipline | Phase 3 done | **verified unbounded** — 3 dynamic invariants; spend-escalation recorded as structural (an earlier vacuous encoding was caught in review and fixed) | confirmed (HIGH) | [`property/P10_CapabilityDiscipline/certificate.txt`](./property/P10_CapabilityDiscipline/certificate.txt) |

Update protocol: every Phase-3 verification result (success or counter-example) updates this table in the same PR.

## 7 · Definition of done

The 100% Verification Initiative is **complete** when **all** of the following hold simultaneously:

1. Every row of §6 Progress is "verified" with a non-empty Apalache certificate.
2. Every divergence between Apalache and Pass-3 is reconciled (resolution recorded in the per-property `notes.md`).
3. Reproducibility verified: a third party can clone `zk-coins/research`, install Apalache from a pinned version, and re-run every certificate.
4. The certificate hyperlinks are published in [`CERTIFICATE.md`](./CERTIFICATE.md) (Pass-4 reconciliation table) and [`property/STATUS.md`](./property/STATUS.md). The Pass-3 audit document is a read-only snapshot and is intentionally not amended.
5. The project lead signs off after reading the final cross-check table.

Anything short of all five is **not** "100%" and the work continues.

## 8 · Reproducibility contract

Every verification must be re-runnable by a third party. Each `formal/property/Pnn_<Name>/` directory contains:

- `property.tla` — the property and its inductive invariant (`IndInv` / `IndInvInit`). The constant instance is pinned in-module (`ConstInit`, consumed via `--cinit`); there is no separate `apalache.cfg`, because the proof is several runs with different `--init`/`--inv`/`--length` combinations a single TLC-style config cannot express.
- `verify.sh` — the reproducible runner: it stages `property.tla` with its `module/` dependencies into a scratch dir (Apalache resolves `EXTENDS` only from the spec's own directory) and runs the check sequence, exiting non-zero on any unexpected outcome.
- `certificate.txt` — Apalache stdout from the successful run (with a pinned-version header).
- `notes.md` — Apalache + Z3 versions, command table, modeling decisions, vacuity probes, negative controls, Pass-3 cross-check.

[`verify-all.sh`](./verify-all.sh) at the `formal/` root executes the module gate plus every property certificate in one command. CI integration is a stretch goal.

## 9 · Honest residual after 100%

Even at 100% under this definition, the following remain:

- **A1–A17 are axioms.** If Poseidon-Goldilocks falls to a new algebraic attack (R1, narrowing through Dec 2026), every property depending on A3/A4 needs re-evaluation under the new bound. Apalache certificates are conditional on the axioms.
- **M1–M4 are meta-assumptions.** Apalache soundness, TLA+↔spec fidelity, adversary-model completeness, property-statement correctness. These cannot be axiomatized inside the verification because they are *about* the verification itself. See [README §Meta-assumptions](./README.md#meta-assumptions-the-unprovable-foundation) for the full inventory and mitigations. The load-bearing items are M2 (translation fidelity) and M4 (property correctness); both addressed by Pass-4 cross-check in Phase 4.
- **The reference implementation is separate.** Apalache verifies the spec; F15 still gates mainnet (the canonical verifier-data artefact must exist).
- **Novel adversary capabilities not in the Pass-3 §2 model** are by definition uncatchable here. The adversary model itself is human-authored (M3).

These items are explicit in the §1.2 out-of-scope section and in the audit's §8 residual inventory. 100% means "100% under the stated axioms (A1–A17), meta-assumptions (M1–M4), and adversary model" — the strongest claim a verification can make, and the honest claim.

## 10 · Authority

This plan was produced on 2026-06-06 in response to the project lead's directive to document the verification effort completely. The document is the canonical reference for the initiative; updates land via PR on `zk-coins/research` and supersede any earlier version on merge.
