# GAPS against P1–P10 — what the verified property set does not cover

Aggregated from [D1](D1.md)–[D7](D7.md). This document maps the conceptual gaps
surfaced across the seven dimensions onto the verified property set, names the new
properties (P11+) the concept needs, and — honestly — flags which gaps are
**not closeable by more verification** (intrinsic concept limits) versus
**closeable by adding a property or extending the model**.

## Framing: what P1–P10 actually is

P1–P10 is a **safety set at the spec-composition level, axiom-conditional, and
single-party-in-isolation**:

- **Safety, not liveness.** P1 (no-forgery), P2 (no-double-spend), P3
  (conservation/supply-discipline), P4 (zero-knowledge), P5 (on-chain
  unlinkability), P6 (client-side validation), P7 (issuance authenticity), P8
  (transport confidentiality+auth), P10 (capability discipline) are all "nothing
  bad can happen" statements. Only P9 (recovery completeness) touches liveness —
  and **its liveness half is not verified**: Apalache 0.58.0 has no fairness
  support, the genuine `WF ⇒ ◇□` form throws `NotImplementedError`, and the
  fairness-free temporal form returns a *counterexample*. P9 ships a safety
  "enabledness surrogate," graded MEDIUM. So the proof base guarantees the
  protocol cannot *lie or steal*; it guarantees almost nothing about whether the
  user can *make progress*.

- **Axiom-conditional, three stacked layers.** (i) cryptographic axioms A1–A17
  (consumed, not proven); (ii) meta-assumptions M1–M4 (tool soundness,
  translation fidelity, **adversary-model completeness M3**, property-statement
  correctness M4); (iii) per-property sub-scopes (P4/P5 indistinguishability =
  axiom A2; P5 network-layer out of scope; P9 liveness surrogate). Two axioms in
  particular bracket out the real risk: **A12** (no reorg ≥6 blocks) makes the
  one fund-losing event *unreachable by construction*, and **A13**
  (eclipse-resistance / single honest chain view) collapses all honest nodes to
  one accumulator, hiding DA-divergence.

- **Single-party-in-isolation, silent on contention.** Each Pᵢ pits one adversary
  against one honest victim's local checks. There is no property about two honest
  parties competing for a slot, ordering fairness, one user griefing another's
  batch stale, or a user's own two devices disagreeing.

**The decisive observation (M3 is the door).** A goal that was never *stated*
cannot be *mis-stated*, so M4 (property correctness) never fires on it, and M3
(did we model the right adversary/goal at all?) silently absorbs it. The
verification is a faithful proof of an **incomplete specification of goals** —
P1–P10 answer "is each thing the spec claims true?" with a defensible YES, and
are silent on "are these the right and complete set of things a private,
Bitcoin-anchored money must guarantee?" Every gap below walks through M3.

## Gap → adjacent-P → proposed new property (P11+)

The table consolidates D1's P11–P15 with the property-shaped gaps surfaced in
D2–D7. "Achievable here?" is the honest verdict on whether the property can hold
in *this* design or requires a design change.

| New | Property (one-line game statement) | Adjacent P | What that P does NOT cover | Formal / operational | Source risks | Why fundamental | Achievable in this design? |
|---|---|---|---|---|---|---|---|
| **P11** | **Censorship/inclusion resistance.** An honest, fee-paying spender's `SpendRecord` eventually reaches a `completed` inscription, given the spender retains the ability to self-publish. | P2/P6 (what happens *once anchored*) | nothing guarantees a spend *gets* anchored; self-publish is a cost-shift, not a guarantee | Operational (weak self-publication-enabledness invariant is formal) | R-D1-1, R-D4-1 | "censorship-resistant money" reduces to "be a whale" for thin clients | **Partly** — enabledness is statable; the strong form needs ≥1 willing reachable publisher = an economic liveness assumption, **not certifiable**. Needs a costed thin-client self-publish path (design change). |
| **P12** | **Accumulator progress verifiable by anyone, anytime (DA safety).** No adversary can drive the accumulator into a state whose `prev_root→new_root` transition no honest party can validate, and two honest nodes at the same tip do not permanently disagree on the canonical, verifiable root. | P6 (client-side validation, per-node) | the network's only consensus object now depends on off-chain `BatchBundle` availability; honest nodes diverge at the same tip under partial DA | Hybrid (admission rule formal; availability operational) | R-D2-8, R-D1-2, R-D5-2 | one missing off-chain blob can freeze/split the global double-spend ledger for everyone — the closest thing to a chain-halt | **Bounded only** — divergence can be made rare + self-healing (normative bundle-verified-root rule, per-node-accumulator model, incentivized archival), but **impossibility requires on-chain nullifiers**, which #40 removed. Intrinsic residual. |
| **P13** | **Multi-device / single-seed consistency.** Two honest devices from one seed cannot be led into divergent states without the divergence being detected and safely halted before any unsafe spend — and the loser's funds remain recoverable, not merely "safe but stuck." | P2 (+ §6.3 same-counter rule) | P2 is single-lineage; nothing bounds the silent-staleness window or guarantees loss-free fork resolution | Partly formal (detection formal; loss-free recovery operational) | R-D1-3, R-D6-5 | multi-device-on-one-seed is a first-class supported, common scenario; current answer is detection-then-manual | **Yes for detection** (statable invariant + shared-relay/pre-spend-freshness gate); **needs a design addition** for a deterministic loss-free fork-resolution procedure (currently unspecified). |
| **P14** | **Receiver non-repudiation / proof-of-payment.** A payer who completed a payment can produce third-party-verifiable evidence that the payment was made and delivered. | P8 (transport conf+auth) | P8 + the ACK are *private* retry artefacts, not a portable receipt; neither side can hold the other to account (S2/S8) | Mostly operational (ACK-binding core formal) | R-D1-4 | the brand pitch is "verifiable proof I sent it," yet no non-repudiation property exists | **Proof-of-send: yes** (promote the `ack_nonce`-bound ACK to a portable receipt — formal core). **Proof-of-receipt: no** — impossible without recipient cooperation (intrinsic to any store-and-forward channel); state the limit. |
| **P15** | **Issuer continuity + supply observability.** Holders can keep using an asset if the creator disappears, and can detect creator over-issuance against any off-chain supply commitment. | P3 (conservation-relative-to-issued), P7 (issuance authenticity) | P3 silently assumes honest issuance accounting; P7 says nothing about creator-key loss or succession | Observability formal; continuity operational | R-D1-5, R-D6-14 | for any non-toy asset, irrevocable creator-bound mint authority is a single point of failure | **Observability: yes** (statable checkable property). **Continuity: no in v1** — needs a v2 issuance feature (succession / multi-sig); a design change, honestly a known v1 boundary. |
| **P16** | **Recovery availability / liveness.** A held real bundle is not merely gate-admissible but is *eventually returned* to a recovering owner. | P9 (recovery completeness — safety half only) | P9 proves "never accepts a forged coin," NOT "returns your coins"; the liveness half is uncertified surrogate-only | Operational (and currently uncertifiable in the pinned tool) | R-D3-1, R-D4-4, R-D5-1, R-D5-6, R-D6-8, R-D7-7 | the funds-loss modes live entirely in this uncertified gap; "seed = money" is false | **No, not as a hard guarantee** — "all replicas lost ⇒ funds gone" is true by construction (value not seed-derivable). Achievable only *probabilistically* via a paid/incentivized DA layer (R11 below); intrinsic floor remains. |
| **P17** | **Economic sustainability of long-term DA.** Serving the long tail of `BatchBundle`/`CoinProof` data indefinitely is incentive-compatible, so honest retention is the rational equilibrium. | (none — no P touches incentives) | the entire incentive/liveness layer is outside P1–P10; §4.6 "MUST retain" is uncompensated fiat | Operational (economic) | R-D4-4, R-D7-3, R-D4-6 | uncompensated unprunable monotonic storage is a textbook commons; coins go permanently unspendable | **Requires a design change** — a storage-fee market / paid archival tier / erasure-coded DA with proofs-of-retrievability. Not closeable by verification; the "no token/no consensus" stance is the obstacle. |
| **P18** | **Operator-view eviction / key rotation.** A user can rotate viewing/transport keys to strip a former or breached operator of read access without abandoning the account/address. | P10 (capability discipline), P5 | P10 governs grants the node honors; nothing lets the user retire `ivk/ovk/op` themselves; grants don't rotate | Operational / design | R-D3-2, R-D3-8, R-D6-9 | a hosted user who changes providers cannot cut off the old one; one future `ivk` leak exposes all history forever | **No in the current key hierarchy** — `ivk/ovk/op` are fixed hardened seed children with a 1:1 account↔address map; eviction = new identity. Achievable only via a diversified/rotatable incoming-view-key redesign. |
| **P19** | **Bounded sender obligation / delivery termination.** A sender's retain-and-retry obligation terminates in bounded time via a safe give-up state, even if the receiver never ACKs. | P8 (+ §4.2 ACK rule) | the ACK rule sets no deadline and no safe give-up; obligation is literally unbounded | Formal (statable as a bounded-liveness/termination property) | R-D4-5, R-D6-10, R-D2-2 | rational receivers under-ACK; senders carry an unbounded one-sided storage/bandwidth tax | **Yes** — decouple custody-safe-drop from ACK-receipt: a provably `k`-replicated blob makes the sender's drop safe without an ACK. A clean, low-cost design addition. |
| **P20** | **Sustained throughput / progress under contention.** The accumulator makes payment progress at a stated rate without unbounded wasted re-proving, and no single writer can monopolize the write slot. | (none — P1–P10 silent on throughput/MEV) | the sequential `prev_root` write-lock, its ceiling, and the chain-bid/stale-force griefing are entirely unmodelled | Operational (economic/contention) | R-D2-5, R-D7-2, R-D4-2, R-D4-3 | the design's correctness backbone is also a hard global serialization bottleneck + cheap latency weapon | **Bounded only** — amortization (large `m`, permissionless prev_root-leasing, commit-tickets) helps; true concurrency would forfeit the clean total order P2 relies on. Intrinsic ceiling. |
| **P21** | **Honest-node accumulator convergence (bounded divergence + eventual agreement).** Any two honest nodes' accumulator views, parameterized by each node's fetched-bundle set, diverge by a bounded amount and eventually agree. | P6 (per-node), and the *assumption* A13 | A13 collapses all honest nodes to one view, so the "identical classification at same tip" guarantee assumes away the divergence | Formal (statable once A13 is dropped and per-node accumulators are modelled) | R-D2-8 | A13+full-DA "is the whole ballgame and it is assumed, not proved" | **Yes to state, bounded to satisfy** — modellable by replacing the single global `Acc` with per-node accumulators; the *eventual-agreement* premise still rests on DA availability (ties to P12/P17). |

(P11–P15 are D1's original IDs, carried verbatim. P16–P21 consolidate the
property-shaped gaps surfaced across D2–D7; P16/P17 sharpen D1's "recovery
liveness" rejection and D4's storage-commons into named properties, P18 from D3's
non-rotatability, P19 from D4/D6's ACK obligation, P20 from D2/D4/D7's sequential
accumulator, P21 from D2's A13 collapse.)

## Closeable by a property/model vs intrinsic concept limit

The honest dividing line — and the most important output of this document.

### Closeable by adding a property or extending the model (verification/spec can help)

- **P13 detection half**, **P21 bounded-divergence** — both become checkable
  invariants once per-node accumulators replace the A13-collapsed single view;
  these are genuine *modelling gaps*, not concept gaps.
- **P14 proof-of-send**, **P19 bounded sender obligation** — formally statable and
  largely follow from P8 + a clean design addition (portable receipt; custody-safe
  drop decoupled from ACK).
- **P15 supply-observability** — a checkable property today.
- **P11 self-publication-enabledness**, **P16 recovery-enabledness** — the *weak*
  (enabledness) forms are statable and checkable, analogous to the existing P9
  surrogate.
- **R-D7-1 / R-D7-6 / R-D3-11 / R-D2-6 / R-D6-12** and the other documentation
  findings in [RISKS.md](RISKS.md) — pure spec/UX hygiene, closeable without
  redesign.

### NOT closeable by more verification — intrinsic concept limits (need a design change or are floors)

- **P16 recovery liveness (hard form)** — *intrinsic*. The spendable value is not
  seed-derivable; "all replicas lost ⇒ funds gone" is true by construction. No
  fairness checker changes this; only a paid/incentivized DA layer (P17) lowers
  the probability. **This is the single most important intrinsic limit.**
- **P12 / P21 DA-divergence impossibility** — *intrinsic to off-chain
  nullifiers*. Making honest-node divergence *impossible* (not merely rare)
  requires putting the nullifier set on-chain, which #40 deliberately removed for
  privacy and cost. Verification can only certify *bounded* divergence + eventual
  agreement, never zero.
- **P17 long-term-DA economics** — *needs a design change*. Cannot be verified
  into existence; requires a storage-fee market / archival tier / erasure-coded
  DA. The "no token, no consensus, no central element" stance is precisely the
  obstacle.
- **P18 operator-view eviction** — *needs a key-hierarchy redesign*. With fixed
  hardened-child `ivk/ovk/op` and a 1:1 account↔address map, eviction = a new
  identity. No property closes this without diversified/rotatable view keys.
- **P20 throughput under contention** — *intrinsic*. The sequential single-writer
  accumulator is what makes first-spend-wins a clean total order; concurrency
  would forfeit the property P2 certifies. Only amortization, never removal.
- **P14 proof-of-receipt** — *intrinsic*. Impossible without recipient cooperation
  in any store-and-forward channel; the right move is to *state* the limit, not
  close it.
- **R-D2-1 (≥6 reorg)** — *intrinsic, policy-mitigated*. The only zkCoins-layer
  lever is "wait for more confirmations," which trades latency for tail safety and
  never reaches zero; there is no slashing/insurance/checkpoint at this layer.
- **R-D4-8 (cleartext marker)** — the protocol *cannot* hide that an inscription
  exists; a keyed marker only raises the cost of blanket censorship. Partial.

**Bottom line.** Roughly a third of the gaps (P13-detection, P14-send, P15-obs,
P19, P21, and the doc findings) are *closeable by stating a property or extending
the model* — these are faithful modelling gaps. The remainder (P16-hard,
P17, P18, P20, P12-impossibility, the reorg tail) are **intrinsic concept limits
or require a design change**: they sit in the liveness / availability / incentive
/ scale region that P1–P10 was never built to reach, and more verification — even
a perfect fairness checker — cannot manufacture the guarantee. The verified set
is a sound proof that zkCoins cannot forge, double-spend, or leak; the gaps above
are the honest statement of everything that soundness does not, and largely
cannot, settle.
