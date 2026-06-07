# zkCoins Concept Review — does the idea hold up?

**What this is.** A structured, adversarial review of the **conceptual viability** of the
zkCoins protocol — *not* its cryptography. The Apalache initiative
([`../CERTIFICATE.md`](../CERTIFICATE.md)) already machine-verified that the spec is
internally consistent and that P1–P10 hold at the composition level under axioms
A1–A17 and meta-assumptions M1–M4. That answers *"is the spec self-consistent?"* It
does **not** answer the project lead's actual question: *"is the idea behind the
concept reliable — before we invest in implementation?"* This review answers that one.

**Spec baseline:** [`zk-coins/docs@b6972b8`](https://github.com/zk-coins/docs/commit/b6972b8) (post-`docs#40`).
**Method:** eight dimensions, each an independent analyst pass plus an adversarial-critic
and quality/logic review round; honesty mandated over optimism. Sources: the spec, the
Shielded CSV paper, the project notes, and the verification artifacts' own honest scope
caveats.

## Bottom line

> **The concept is viable — under conditions.** The *core idea* is sound, genuinely
> differentiated, and the safety core is real (machine-verified). But the concept as
> currently framed carries **serious conceptual risks that must be resolved or
> explicitly accepted before implementation investment**, and several of them are
> **intrinsic** — they cannot be closed by more verification, only by a design change,
> a scope change, or honest de-marketing.

Concretely, the answer splits by ambition:

- **As a niche, lower-volume, privacy-focused settlement tool for technically capable
  users** — the concept is **viable under the conditions below.**
- **As the headline pitch (mass-market, "trustless", censorship-resistant payments at
  scale)** — the concept is **not viable as-is**: four of the Top-5 risks directly
  attack exactly those claims, and two are intrinsic to the post-`docs#40` architecture.

This is not a crypto failure. P1–P10 stand. It is that **P1–P10 are the wrong half of
the question for viability**: they are safety properties, silent on liveness,
availability, incentives, recovery, UX, and scale — which is where every serious finding
below lives (and where meta-assumptions M3/M4 quietly absorb the missing goals).

## The dimensions

| File | Dimension | Distinct risks | Headline |
|---|---|---|---|
| [D1](./D1.md) | Property completeness (P11+) | 5 | P1–P10 don't cover censorship, accumulator DA, multi-device, proof-of-payment, issuer continuity |
| [D2](./D2.md) | Model-vs-reality gap | 10 | The model excludes the ≥6-block reorg — the one event that loses finalised funds; honest-node divergence under partial DA |
| [D3](./D3.md) | Recovery + operator trust (highest priority) | 12 | Seed restores keys, not funds; operator holds `ivk+ovk+op` = lifetime full view, non-rotatable |
| [D4](./D4.md) | Liveness + incentive compatibility | 9 | No liveness is certified; publishers can fee-snipe the single writer slot; long-term DA is an uncompensated commons |
| [D5](./D5.md) | Comparison with prior art | 7 | Inherits Shielded CSV's data-availability + seed-alone-unrecoverable problem and *sharpens* the DA failure |
| [D6](./D6.md) | End-to-end UX walk-throughs (9 journeys) | 14 | "Seed is my money" and "an address is enough to receive" are both false here, uncorrected |
| [D7](./D7.md) | Scaling | 7 | ~10⁴ tx/day central throughput envelope — 2–3 orders below the project's own stated goals |
| [RISKS.md](./RISKS.md) | Consolidated risk matrix | **42 total** | 2 critical, 16 high, 22 medium, 2 low |
| [GAPS_AGAINST_P1_P10.md](./GAPS_AGAINST_P1_P10.md) | Missing properties | P11–P21 | which gaps are closeable vs intrinsic |

## Top-5 conceptual risks

(Full matrix and per-risk mitigation/cost in [RISKS.md](./RISKS.md).)

1. **Seed restores keys, not funds (R-D3-1, critical).** Value lives only in off-chain
   `CoinProof` bundles; it is *not* seed-derivable. For a lone self-hoster the
   recommended `k=3` replica set collapses toward `k=1`, so a node loss can permanently
   destroy a spendable balance despite a perfect seed backup. P9 certifies recovery
   *safety* (no false-accept) but **not** recovery *availability*. Intrinsic floor;
   mitigable in degree (client-enforced independent replication + a "this is your real
   backup" UX) but never to "seed alone is enough."

2. **Sequential single-writer accumulator (R-D2-5, high).** The accumulator advances one
   `BatchInscription` per tip, globally, in Bitcoin order. This caps throughput
   (~10⁴ tx/day, D7), enables a funded publisher to fee-snipe every slot (de-facto
   exclusive writer = ordering/metadata/censorship control without breaking a rule, D4),
   and lets a cheap adversary stale-force rivals into wasting ~100KB recursive proofs.
   Intrinsic to the design's total-order; relieving it forfeits the single global
   accumulator.

3. **Off-chain bundle DA gates accumulator progress + honest-node divergence (R-D2-8,
   high).** Post-`docs#40`, nullifiers and the aggregate proof live in the off-chain
   `BatchBundle`; a verifier that cannot fetch it cannot validate the root transition.
   Two honest nodes at the same Bitcoin tip can therefore hold different accumulators and
   give opposite double-spend answers during a DA gap — and a light client cannot detect
   that its node is DA-behind. P6's "identical classification at the same tip" is exactly
   the guarantee reality withholds. Sharper than the base Shielded CSV paper (which kept
   nullifiers on-chain).

4. **Operator holds `ivk+ovk+op` = lifetime full view; non-rotatable; "trustless"
   framing (R-D3-3 / R-D3-9, high).** The realistic mass-market path (no own infra)
   hands a foreign operator the full viewing + transport keys — full plaintext history,
   forever, with no rotation and no eviction on operator switch. Custody stays safe;
   privacy does not. The headline "no trusted operator" is true for *custody* and false
   for *privacy* on the only path most users will take.

5. **Uncompensated long-term data-availability commons (R-D4-4, high).** Relays MUST
   retain bundles unprunably and serve them with no protocol-level fee. Classic
   tragedy-of-the-commons; long-tail bundles (needed years later for recovery) have no
   naturally incentivised holder — the concrete mechanism behind risks 1 and 3.

(The ≥6-block-reorg fund loss, R-D2-1, is the only other *critical* — excluded from the
Top-5 on low likelihood and partial "wait longer" mitigation, but it is the precise case
the verification model cannot see, since A12 assumes it away.)

## What is genuinely strong (stated honestly)

- The **safety core is real and machine-checked**: no forgery, no double-spend, balance
  conservation, capability discipline — verified unbounded, with the honest sub-scopes
  documented.
- **No own chain, no token, no consensus change, no trusted setup, no custodial
  operator** — a genuinely lean trust base versus Zcash/Aztec/Lightning.
- **One global anonymity set** (no per-pool fragmentation), shielded-only (no transparent
  dilution), constant-size proofs that hide history even from the recipient.
- The team's **own honesty discipline is good**: the verification certificates already
  label their bounded/structural/surrogate scopes rather than overclaiming.

## Conditions for "viable"

The concept is viable **if** the project:

1. **Re-frames the guarantees truthfully** — drop or qualify "trustless" and
   "your seed is your money" for the foreign-operator and recovery paths; ship the
   honest trust-config table (D3, D6) in the product, not a footnote.
2. **Treats data availability as a first-class safety concern**, not an operational
   afterthought: client-enforced independent `k`-replication with a pre-spend gate, an
   independence-attestation mechanism, and a sustainability model for long-tail bundle
   storage (P16/P17). Without this, recovery and accumulator-progress claims are unbacked.
3. **States the scope honestly**: low-volume / niche-privacy / settlement, **not**
   PayPal-scale payments — the throughput ceiling is ~2–3 orders below the published
   goal (D7). Either accept the niche, or design a concurrency path that gives up the
   single total order.
4. **Adds the missing properties** that are closeable (P13 multi-device, P19 bounded
   sender obligation, P21 honest-node convergence, P11 inclusion-resistance in its
   enabledness form) and **explicitly accepts** the intrinsic limits (P12 DA, P14
   proof-of-receipt, P16 recovery floor, P18 key rotation, P20 throughput).
5. **Keeps the reference-implementation gate (F15)**: the safety proofs are spec-level;
   the Zcash Orchard counterfeiting bug (a circuit-implementation soundness flaw,
   undetected for years) is exactly this project's open implementation risk.

## What this review does NOT claim

- It does not re-open the cryptography or the P1–P10 proofs — those stand.
- It does not assert any of these risks is unsolvable; several are. It asserts they are
  **currently unresolved or intrinsic**, and that **at least the Top-5 must be addressed
  or explicitly accepted before implementation investment** — which was the question.

*Concept review conducted 2026-06-07 against `docs@b6972b8`. Reviewed in an analyst +
adversarial-critic + quality/logic loop per dimension. The verification artifacts this
review builds on land in [`research#10`](https://github.com/zk-coins/research/pull/10).*
