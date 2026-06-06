# 100% Logical Verification Plan — zkCoins v1 Specification

**Initiated:** 2026-06-06
**Owner:** project lead, via Claude (AI execution)
**Spec baseline:** [`zk-coins/docs@a7a9f97`](https://github.com/zk-coins/docs/commit/a7a9f97) — develop tip after F1, F16, F17, F9, F12, and the anchor-polish + profile-preimage-pin merges of 2026-06-06. Subject to advance once [`docs#40`](https://github.com/zk-coins/docs/pull/40) (Variant-2 on-chain redesign) merges; see §Dependencies.

## 0 · Declaration of intent

The project lead has declared on 2026-06-06: *"ich will nicht 'richtung 100%'. ich will volle 100%, dafür sind wir hier!"* This document is the operational plan to reach that target — every spec-level property mechanically proven, not manually argued.

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

Each is verified as a TLA+ invariant or temporal property using Apalache, with the spec's cryptographic primitives axiomatized as ideal functionalities (A1–A14; see [README §Axiomatized assumptions](./README.md#axiomatized-assumptions)).

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

### Phase 0 — Setup (target: 0.5–1 day)

- Install Apalache on the verification host (m5me or local).
- Verify Apalache version + basic smoke test.
- Port the existing [`nullifier-chaining/FirstSpendWins.tla`](./nullifier-chaining/FirstSpendWins.tla) from TLC-compatible to Apalache-compatible form; reproduce its property as an **unbounded** verification (no `Bound`). Demonstrates the toolchain works end-to-end.
- **Deliverable:** `formal/property/P02_NoDoubleSpend/` with a passing unbounded Apalache run.

### Phase 1 — Formal modeling of the specification (target: 3–5 days)

Build the `formal/module/` directory. Each module is a TLA+ file modeling one spec section.

| Module | Models | Source spec sections |
|---|---|---|
| `Foundations.tla` | Types: Address, Pkᵢ, ash, ocr, inr, nf, asset_id, AccountState, Coin, CoinProof, Invoice (post-F9) | §1 |
| `Proofs.tla` | Compliance predicate `C` as a TLA+ operator; clauses 1–9; witness type; canonical empty account | §2.1, §2.2 |
| `Onchain.tla` | Admission state machine (§3.5 parser + §3.6 scanner); first-spend-wins with within-record rollback (F16); nullifier accumulator; §3.10 lifecycle | §3.5, §3.6, §3.7, §3.9, §3.10 |
| `Transport.tla` | DeliveryEvent + ACK with `ack_nonce` (F17); k-replication; self-delivery | §4.2, §4.3, §4.6 |
| `Access.tla` | OwnershipProof, GrantProof, zkview, zkavk, BalanceAttestation; PullChallenge with `chan_bind` | §5.1 — §5.8 |
| `Architecture.tla` | Multi-node composition; latest-state selection (F12); reorg-bound assumption | §6.3, §6.6 |
| `Assumptions.tla` | Axiomatized A1–A14 as TLA+ operators with stated security properties | — |
| `Adversary.tla` | PPT adversary as nondeterministic environment; capabilities per Pass-3 §2 | — |

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

**Deliverable:** updated audit ([`audit/2026-06-06.04.md`](../audit/) or amend Pass-3) carrying mechanical certificate references.

### Phase 5 — Documentation + sign-off (target: 1–2 days)

- All `certificate.txt` files committed.
- `formal/property/STATUS.md` table marked all green.
- Audit doc updated with hyperlinks to certificates.
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
| Time blowout past 2 weeks | medium | extend; the goal is 100%, not 100%-by-date | keep daily progress diary |

## 5 · Dependencies

### Hard

- **docs#40** ([Variant-2 on-chain redesign](https://github.com/zk-coins/docs/pull/40)) — the on-chain layer model in `Onchain.tla` MUST be built against the post-docs#40 form. Three options:
  1. **Wait for docs#40 to merge** — clean baseline, no rework.
  2. **Model against the docs#40 branch tip** — earliest start, requires re-base if docs#40 changes.
  3. **Model against current develop, retrofit after** — fastest start, but Phase 1 of Onchain.tla becomes throwaway work.

  **Recommendation: (1) wait, OR (2) model against branch.** The decision is the project lead's; documented here so it's not implicit.

### Soft

- Apalache tooling on the verification host.
- TLA+ + Apalache local IDE (optional, helps iteration).
- Reproducibility on m5me for nightly verifications.

## 6 · Progress

Per-property status — updated as Phase 3 advances.

| Property | Phase | Apalache status | Cross-check vs Pass-3 | Certificate |
|---|---|---|---|---|
| **P1** No-Forgery | not started | — | — | — |
| **P2** No-Double-Spend | Phase 0 (port) | TLC bounded only (legacy `FirstSpendWins.tla`) | matches Pass-3 HIGH | pending Apalache port |
| **P3** Balance Conservation | not started | — | — | — |
| **P4** Zero-Knowledge | not started | — | — | — |
| **P5** On-chain Privacy | not started | — | — | — |
| **P6** Client-Side Validation | not started | — | — | — |
| **P7** Issuance Authenticity v1 | not started | — | — | — |
| **P8** Transport Confidentiality + Auth | not started | — | — | — |
| **P9** Recovery Completeness | not started | — | — | — |
| **P10** Capability Discipline | not started | — | — | — |

Update protocol: every Phase-3 verification result (success or counter-example) updates this table in the same PR.

## 7 · Definition of done

The 100% Verification Initiative is **complete** when **all** of the following hold simultaneously:

1. Every row of §6 Progress is "verified" with a non-empty Apalache certificate.
2. Every divergence between Apalache and Pass-3 is reconciled (resolution recorded in the per-property `notes.md`).
3. Reproducibility verified: a third party can clone `zk-coins/research`, install Apalache from a pinned version, and re-run every certificate.
4. The audit doc carries hyperlinks to each certificate.
5. The project lead signs off after reading the final cross-check table.

Anything short of all five is **not** "100%" and the work continues.

## 8 · Reproducibility contract

Every verification must be re-runnable by a third party. Each `formal/property/Pn_<Name>/` directory contains:

- `property.tla` — the property and any inductive invariant
- `apalache.cfg` — Apalache configuration (version, init, next, invariants, timeout)
- `certificate.txt` — Apalache stdout from the successful run
- `notes.md` — Apalache version, command line, time taken, any decisions

A `Makefile` or `verify.sh` at the directory root executes every verification in one command. CI integration is a stretch goal.

## 9 · Honest residual after 100%

Even at 100% under this definition, the following remain:

- **A1–A14 are axioms.** If Poseidon-Goldilocks falls to a new algebraic attack (R1, narrowing through Dec 2026), every property depending on A3/A4 needs re-evaluation under the new bound. Apalache certificates are conditional on the axioms.
- **The reference implementation is separate.** Apalache verifies the spec; F15 still gates mainnet (the canonical verifier-data artefact must exist).
- **Novel adversary capabilities not in the Pass-3 §2 model** are by definition uncatchable here. The adversary model itself is human-authored.

These items are explicit in the §1.2 out-of-scope section and in the audit's §8 residual inventory. 100% means "100% under the stated axioms and adversary model" — the strongest claim a verification can make, and the honest claim.

## 10 · Authority

This plan was produced by Claude on 2026-06-06 in response to the project lead's declaration *"wir müssen das vollständig dokumentieren"*. The document is the canonical reference for the initiative; updates land via PR on `zk-coins/research` and supersede any earlier version on merge.
