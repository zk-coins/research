# zkCoins 100% Logical Verification — Certificate of Completion

**Spec baseline:** [`zk-coins/docs@b6972b8`](https://github.com/zk-coins/docs/commit/b6972b8) — `develop` tip including the merged [`docs#40`](https://github.com/zk-coins/docs/pull/40) Variant-2 on-chain redesign.
**Tool (pinned):** Apalache 0.58.0 (build 711dce6), Z3 4.14.1.0 (bundled), Temurin OpenJDK 17.
**Host class:** Apple Silicon (arm64), macOS (Darwin 25.5.0).
**Dates:** 2026-06-06 — 2026-06-07.
**Reproduce everything:** `formal/verify-all.sh` (one command; Apalache is the only dependency).

## Claim

Every security property the zkCoins v1 specification claims (P1–P10) is
**mechanically verified** with Apalache against the spec's clauses, with the
cryptographic primitives axiomatized as ideal functionalities (A1–A17,
[`README.md`](./README.md)) and the verification itself conditional on the four
meta-assumptions (M1–M4). Wherever a sub-claim is *not* covered by an
unbounded inductive proof, the certificate says so explicitly — there are no
silent scope reductions.

Every property package under [`property/`](./property/) contains the
formalized invariant (`property.tla`), a reproducible runner (`verify.sh`),
the full Apalache transcript (`certificate.txt`), and the modeling/decision
record (`notes.md`) including **vacuity probes** (the invariant is shown not
to be trivially true) and **negative controls** (deleting the load-bearing
spec rule makes Apalache produce a counterexample).

## Phase-4 reconciliation — Apalache verdict vs Pass-3 manual audit

The Pass-3 audit (`audit/2026-06-06.03.md`, snapshot `01ae663`) reached HIGH
confidence on every property by game-style manual argument. The table below is
the M2/M4 trip-wire check: divergence between the mechanical verdict and the
manual label would indicate a translation or property-statement error.

| Property | Pass-3 label | Apalache verdict | Resolution |
|---|---|---|---|
| P1 No-Forgery | HIGH | verified (provenance unbounded; signature-level bounded + reduction) | **confirmed** |
| P2 No-Double-Spend | HIGH (subject to F16 wording) | verified unbounded (abstract + full on-chain machine) | **confirmed**; F16's rollback pin (merged `docs#35`) is the modelled behaviour |
| P3 Balance Conservation | HIGH (creator-bound v1 model) | verified unbounded | **confirmed**, same v1 framing (supply discipline, not protocol cap) |
| P4 Zero-Knowledge | HIGH | verified at the composition level (publication-gate flow unbounded); indistinguishability = A2 | **confirmed**; the hyperproperty half is explicitly the A2 axiom, exactly as Pass-3 conditioned on A2 |
| P5 On-chain Privacy | HIGH on-chain / MEDIUM network | verified (publisher-only-link unbounded); network half out of scope | **confirmed and strengthened post-`docs#40`**: the per-record on-chain surface Pass-3 analysed (rotating `Pk_i`, raw `nf`s, the accepted `k_j` input-count leak) no longer exists — the chain now carries only the constant-size `BatchInscription`; `k_j` is bundle-only; the publisher pubkey is the new, sole on-chain identity. Network-layer hygiene stays MEDIUM/operational, as Pass-3 said |
| P6 Client-Side Validation | HIGH | verified unbounded (receive gate composed over the on-chain machine) | **confirmed** |
| P7 Issuance Authenticity v1 | HIGH | verified unbounded | **confirmed**; cross-version (v1/v2) distinctness is structural in the `asset_id` version binding |
| P8 Transport Conf. + Auth | HIGH (with F17 LOW) | verified unbounded | **confirmed**; the F17 fix (`ack_nonce`, merged `docs#36`) is the modelled and verified behaviour — the LOW finding is closed in spec and model |
| P9 Recovery Completeness | HIGH correctness / MEDIUM liveness | verified: safety unbounded; liveness via enabledness surrogate | **confirmed with the same split**: correctness mechanical; temporal liveness not certifiable in Apalache 0.58.0 (no fairness support — the genuine `WF ⇒ ◇□` form throws `NotImplementedError`), surrogate + Pass-3's MEDIUM label stand |
| P10 Capability Discipline | HIGH | verified unbounded (3 dynamic invariants; spend-escalation structural) | **confirmed — after a real M4 catch**: the first encoding of the cross-host-replay and spend-escalation conjuncts was *proven vacuous* in review (the model hardcoded the host binding; the spend conjunct reduced to a tautology). The model was fixed so the chan_bind gate is genuinely load-bearing (counterexample control now fires), and spend-escalation is honestly recorded as structural. This is the process working as designed |

**Divergences found: none on any property verdict.** One audit-text delta is
recorded for traceability (not a divergence): Pass-3's P2/P5 prose describes the
pre-`docs#40` on-chain mechanism (raw nullifiers + scanner first-spend-wins);
`docs#40` relocated that obligation into the publisher's `AggregateBatchProof`
and shrank the on-chain surface. The claims are unchanged or strengthened; the
per-property `notes.md` carry the wording-delta paragraphs.

## What "verified" means here — and what it does not

- **Unbounded** = the inductive 3-check pattern (`Init ⇒ IndInv`,
  `IndInv ∧ Next ⇒ IndInv'`, `IndInv ⇒ INV`): the invariant holds in every
  reachable state, for any number of transitions. Data-domain carriers
  (universe sizes per instance) are finite parameters — intrinsic to SMT-based
  checking; per-package uniformity arguments and larger-instance confirmations
  are recorded in `notes.md`.
- **Bounded / structural / surrogate** sub-results are individually labelled in
  the table above and in each certificate (P1 signature-level, P2 continuity,
  P4/P5 structural surface facts, P9 liveness, P10 spend-escalation).
- **Axioms A1–A17** (cryptographic primitive strength) are *consumed, not
  proven*: if a primitive falls below its axiom, no spec-level proof recovers
  (R1–R4 in the Pass-3 §8 residual inventory; Poseidon margin watch through
  Dec 2026).
- **Meta-assumptions M1–M4** ([`README.md`](./README.md)): Apalache/Z3
  soundness, TLA+↔spec translation fidelity, adversary-model completeness,
  property-statement correctness. M2/M4 were actively exercised: the review
  loop caught and fixed two Phase-1 fidelity gaps (a vacuous PCD binding; a
  transition signature bound to the wrong message) and one Phase-3 vacuity
  (P10) — each is documented where it occurred.
- **The reference implementation is out of scope** (F15 remains the
  deployment gate); this certifies the **specification**.

## Sign-off

- [ ] Project lead review and sign-off — pending.

Produced under the 100% Logical Verification Initiative
([`100-percent-verification-plan.md`](./100-percent-verification-plan.md));
working PR: [`research#10`](https://github.com/zk-coins/research/pull/10).
