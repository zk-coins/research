# RISKS — Consolidated Concept-Review Risk Matrix

Aggregated from the seven dimension files: [D1](D1.md) (property completeness),
[D2](D2.md) (model-vs-reality), [D3](D3.md) (recovery & operator trust),
[D4](D4.md) (liveness & incentives), [D5](D5.md) (comparison with prior art),
[D6](D6.md) (end-to-end UX), [D7](D7.md) (scaling).

This is a faithful aggregation, not a re-analysis. Severities are carried over at
their **honest** value as graded in the source dimension; nothing has been
softened to make the consolidated picture look better. Where two or more
dimensions found the same conceptual risk, one **canonical ID** is kept, the
others are **folded** into it (listed in the "Folds" column and counted once),
and the fold is stated explicitly so each distinct risk is counted exactly once.

A structural caveat that frames the whole matrix (established identically in D1,
D2, D4, D6): **P1–P10 is a safety set.** It proves the protocol cannot forge,
double-spend, or leak under its axioms; it is silent on liveness, availability,
contention, incentives, UX and scale. Almost every risk below lives in that
silent region — it is therefore *not* contradicted by the green certificate, and
that is exactly the point.

## How dedup was done (the four flagged cross-dimension repeats)

- **Sequential single-writer accumulator** appears in D2/D4/D5/D7. Canonical
  **R-D2-5** (fullest mechanism + griefing analysis); folds **R-D4-2**
  (chain-bid monopoly), **R-D4-3** (stale-force griefing), **R-D7-2** (numeric
  throughput envelope), and the comparative differentiator in **D5 §specific-2**.
- **Off-chain BatchBundle DA gating accumulator progress + honest-node
  divergence** appears in D1/D2/D5(/D7-volume). Canonical **R-D2-8** (honest-node
  divergence at same tip); folds **R-D1-2** (P12 availability half), **R-D5-2**
  (blast-radius-vs-paper). The *storage-volume* face is a genuinely distinct
  failure and is kept separate as **R-D7-3**; the *incentive* root cause is kept
  separate as **R-D4-4**.
- **Operator holds `ivk`+`ovk`+`op` = lifetime full view, non-rotatable,
  "trustless" framing gap** appears in D3/D5/D6(/D2-10). Three mechanistically
  distinct risks are preserved: **R-D3-3** (full-plaintext view honeypot; folds
  D5-specific-3, R-D6-4, R-D2-10), **R-D3-2** (keys non-rotatable / no operator
  eviction; folds R-D6-9), **R-D3-9** (the "trustless" framing/marketing gap;
  folds R-D6-3).
- **Seed-alone does not restore funds / recovery availability uncertified**
  appears in D3/D5/D6. Canonical **R-D3-1** (effective-`k=1` fund loss); folds
  **R-D5-1**, **R-D5-6**, **R-D6-1**, **R-D6-8**. The *uncompensated-storage*
  incentive driving it is kept separate as **R-D4-4**; the *partial silent loss*
  variant is kept separate as **R-D3-13**.

## Master risk matrix

Severity scale: critical = direct/irreversible loss of user funds or permanent
unrecoverable state; high = stuck funds / safety-relevant divergence / total
privacy break / structural centralization or scale wall; med = degraded
UX/liveness/griefing/scoped leak; low = cosmetic or strongly bounded.
Mitigation cost: low = doc/wallet-policy; med = protocol/spec mechanism +
client work; high = redesign or new economic/consensus layer.

| ID | Title | Dimension(s) | Folds (counted here) | Severity | Likelihood | User-impact (phrase) | Mitigation option | Mit. cost | Residual after mitigation |
|---|---|---|---|---|---|---|---|---|---|
| **R-D2-5** | Sequential single-writer accumulator: throughput ceiling + MEV/chain-bid monopoly + cheap stale-force griefing | D2,D4,D5,D7 | R-D4-2, R-D4-3, R-D7-2, D5-spec-2 | High | High | Payments cap at ~0.17 tx/s central; publishing centralizes; rivals' proofs burned | Maximize batch size `m`; permissionless prev_root-leasing/coordination; cheap commit-ticket before heavy proving; quantify ceiling | High | Throughput stays sequential-bound; concentration reduced not removed (intrinsic to no-consensus) |
| **R-D2-8** | Off-chain BatchBundle DA gates accumulator progress; two honest nodes diverge at same tip (no anyone-can-verify-progress property) | D1,D2,D5 | R-D1-2 (P12), R-D5-2 | High | Medium | A receiver can credit a network-known double-spend during a DA gap; "is this root canonical?" not answerable by all | Make Path-B query of bundle-verified root normative; per-node accumulators + bounded-divergence/eventual-agreement property; incentivized archival role for BatchBundles | High | Divergence rare + self-healing, never impossible without on-chain nullifiers |
| **R-D3-1** | Seed restores keys but NOT funds; self-delivered change/state bundle reaches effective `k=1` → live balance unrecoverable on node death | D3,D5,D6 | R-D5-1, R-D5-6, R-D6-1, R-D6-8 | Critical | Medium | "I have my seed so my money is safe" is false; balance silently gone | Client-enforced ≥2 independent-replica pre-spend gate; surfaced funds-recoverability indicator; mandate disclosure | Med | "All replicas lost ⇒ funds gone" is true by construction; only made rarer |
| **R-D3-3** | Operator holds `ivk`+`ovk`+prover witness = full lifetime plaintext view (incoming+outgoing+graph); a complete privacy honeypot | D3,D5,D6,D2 | D5-spec-3, R-D6-4, R-D2-10 | High | High | Hosted operator sees every amount, asset, counterparty forever | Honest framing; minimize witness exposure; diversified/per-relationship accounts | Med | Foreign-node user inherently trusts operator for privacy (theft-proof, not private) |
| **R-D3-2** | Viewing/transport keys non-rotatable; a former/breached operator keeps lifetime read access; only escape is abandoning the account | D3,D6 | R-D6-9 | High | Medium | Leaving a provider does not cut off its view; revocations silently reset on switch | Diversified retire-able incoming-view keys; guided migration flow; fold revocation into seed-recoverable state | High | Without re-keying, eviction = new identity (intrinsic to fixed hardened-child design) |
| **R-D3-9** | "Trustless / no trusted operator" framing is misleading for the realistic infra-less user (default deployment is the most-trusting config) | D3,D6 | R-D6-3 | High | High | Users believe "trustless" means private; it means theft-proof only | Replace headline with "operator can't steal; in hosted mode operator sees your full history"; promote foreign-node row to default framing | Low | Framing fixable; underlying privacy trust remains |
| **R-D2-1** | ≥6-block reorg loses credited/finalised funds — exactly the fund-losing case axiom A12 excludes by construction | D2 | — | Critical | Low (mainnet) | A `completed`, credited coin can be double-spent away from receiver after a deep reorg | State A12 dependency in the no-double-spend headline; per-asset high-value confirmation-depth policy; optional checkpoint/fraud-window | Med | "Wait longer" trades latency for tail safety; never reaches zero; no zkCoins-layer cure |
| **R-D5-3** | Circuit/recursion soundness bug → undetectable counterfeiting; no non-ZK supply backstop; privacy hides the breach (Zcash-Orchard class) | D5 | — | High | Low–Med | Supply silently inflated; impossible to audit because shielded | Treat F15 circuit soundness as top gate; external audit pre-mainnet; per-asset non-ZK auditable issuance-ceiling backstop | High | Recursion enlarges TCB; backstop limits blast radius, can't prove circuit correct |
| **R-D7-3** | Bundle DA is unprunable, `k=3`, retained-forever: tens of PB/5yr at 1x, EB-scale at 100x; no pruning/archival design exists | D7,D4 | — | High | Medium | Storage grows monotonically forever; nobody can afford to be a full node at scale | Erasure-coded archival tiers; epoch checkpoints to drop pre-checkpoint bundles; accumulator snapshotting | High | Most irreversible long-term wall; only deferred, not removed without a DA layer |
| **R-D4-4** | Long-tail DA is an uncompensated, unprunable, monotonic storage commons → rational under-provision; coins become permanently unspendable years later | D4,D3,D5 | R-D4-7, R-D3-13(incent) | High | High | A coin whose every replica was dropped is permanently unspendable; recovery false-rejects | Storage-fee/retrieval market; paid archival tier; proofs-of-retrievability + challenge/slashing | High | Without an incentive, §4.6 "MUST retain" is unenforceable; this is P9's bracketed MEDIUM-liveness gap |
| **R-D1-1** | Censorship/inclusion of spends not guaranteed; "permissionless self-publish" is a cost-shift (proving + privacy-puncturing UTXO + race), unreal for phone wallets | D1,D4,D6 | R-D4-1 | High | Medium | A publisher cartel can freeze a thin client's funds (safe but unspendable) | Normative self-publication enabledness property; costed emergency self-publish path for UTXO-less thin clients | High | Strong form needs ≥1 willing reachable publisher — an economic liveness assumption, uncertifiable |
| **R-D3-13** | Partial bundle-store loss silently reduces balance with no error; seed gives no independent coin enumeration to cross-check | D3 | — | High | Low–Med | Balance quietly shrinks; user cannot tell a coin ever existed | Independent coin-count attestation / receipt log; cross-check enumeration | Med | Silent partial loss is intrinsic to data-as-credential; detection improvable not eliminable |
| **R-D3-8** | No forward secrecy on viewing keys + undeletable replicated ciphertexts → one future `ivk` leak retroactively de-anonymises entire history | D3 | — | High | Low–Med | A single later key leak exposes the account's whole financial past, forever, with no remediation | Forward-secret/rotatable incoming-view keys; bounded ciphertext retention | High | "One key, all history, forever" is structural to current key hierarchy |
| **R-D3-10** | `k=3` replica-independence MUST is unenforceable/unverifiable; young-network default is single-provider `k=1` masquerading as `k=3` | D3 | — | High | High | Users believe they have 3-way durability; one provider's exit loses everything | Replica-independence attestation (signed operator identities / pinned long-term keys); client diversification | Med | Bootstrap centralization persists until an independent operator market exists |
| **R-D4-6** | Heavy recursive proving (economies of scale) + winner-take-all fees + serialized slot race → professionalized publisher oligopoly | D4,D5 | D5-spec(Aztec) | High | High | The few professional publishers concentrate privacy + censorship surface | Explicit fee-market / anti-oligopoly design (smoothing, reservation, proof-sharing) | High | Permissionless *entry* ≠ competitive equilibrium; concentration is economic, not attack |
| **R-D7-4** | Detect-tag scan is not server-filterable; recipient candidate set grows with TOTAL global traffic; mobile breaks ~10–100x; FMD mis-framed as OPTIONAL | D5,D6,D7 | R-D5-7, R-D6-7 | Medium | High | Phone sync bandwidth/battery scales with whole network; pushes users to delegate `ivk` | Promote FMD to REQUIRED-beyond-niche; operator-side scan default; state the volume threshold | Med | Narrowing relay set trades scan cost for anonymity-set size; bandwidth wall remains at extreme scale |
| **R-D1-3** | Multi-device single-seed consistency is detection, not prevention; silent staleness → same-counter fork only detected after an unsafe spend | D1,D6 | R-D6-5 | Medium | Med–High | Two devices desync; a stale-device spend hard-stops the wallet with an opaque "resolve fork" | State detection guarantee as property; deterministic loss-free fork-resolution; pre-spend freshness gate + shared-relay invariant | Med | Loss-free recovery from a fork currently unspecified; needs a designed flow |
| **R-D4-5** | Receiver never-ACK imposes unbounded retain+retry obligation on the sender; ACK is uncompensated post-receipt altruism → rational under-ACK | D4,D6,D2 | R-D6-10 | Medium | High | A lazy/offline recipient leaves a payment "delivering…" forever in the sender's UI | ACK deadline + sender give-up "delivered-unacknowledged" state; decouple custody-safe-drop from ACK (prove `k`-replication of the blob) | Low | Pure convention today; bounding it is straightforward |
| **R-D4-8** | Cleartext `0x4242` marker is a trivial L1 fingerprint: a majority-hashrate / regulator-pressured miner can blanket-censor and halt the global accumulator | D4,D5 | D5-tornado-ref | Medium | Low today / high-impact | Regulatory kill-switch: protocol stalls network-wide if miners drop the marker | Less-fingerprintable/keyed marker; document the majority-censorship liveness-halt residual | Med | Cannot hide *that* an inscription exists; only raise blanket-censorship cost |
| **R-D2-3** | Client crash mid-Send (persistence race): input consumed on-chain before change `CoinProof` durably self-delivered → change unrecoverable, no protocol recovery | D2 | — | High | Medium | A crash in a publisher-timed window loses the change coin's value | Normative crash-safe write-ordering: persist outgoing+change bundles & begin self-delivery before releasing the SpendRecord; model a Crash action | Med | Window is publisher-timed; wallet engineering shrinks it, can't fully sequence inclusion |
| **R-D1-4** | No receiver non-repudiation / portable proof-of-payment; S8 withhold + S2 equivocation leave neither side able to hold the other to account | D1 | — | Medium | Medium | "Did you pay me?" / "I never got it" disputes have no protocol-level receipt | Define portable `ack_nonce`-bound receipt; state plainly proof-of-*receipt* needs recipient cooperation | Med | Proof-of-receipt impossible without recipient cooperation (intrinsic to store-and-forward) |
| **R-D3-6** | Emergency recovery has no anonymous-retrieval mode; forces identity or incoming-history-cardinality disclosure to untrusted operators | D3,D6 | R-D6-11 | Medium | Medium | At the user's most vulnerable moment, recovery doxxes them to operators they must beg | PIR-style / oblivious bundle fetch (future version) | High | Some signal leaks to whoever holds your bundles; reducible not zero |
| **R-D3-4** | A single prover can grief spend-liveness (slow/garbage proving); escape only if another honest prover is reachable | D3 | — | Medium | Medium | User cannot spend until they switch provers | Node portability (exists); maintain reachable alternative provers | Low | Liveness depends on an alternative willing prover existing |
| **R-D3-5** | A single dishonest node can induce a stale-anchor self-fork / spend-halt (DoS + alarming UX), not theft; only multi-node querying mitigates | D3 | — | Medium | Medium | Hosted single-node user gets a scary "account forked" halt caused purely by their operator lying | Default multi-node fan-out for meaningful value | Med | Single-foreign-node users remain exposed to the DoS |
| **R-D3-7** | Revocation set is per-node runtime state, not seed-restored; a node switch silently un-revokes previously revoked grants | D3 | — | Medium | Medium | Grants the user thought were revoked silently reactivate on a new node | Fold revocation into seed-recoverable state; make grant expiry a MUST | Med | Folded under R-D3-2 framing in UX, distinct mechanism here |
| **R-D2-2** | Network partition during the ACK window: double-delivery idempotency asserted-not-verified; unbounded sender retention under long partition | D2 | — | Medium | Medium | Possible double-credit (likely benign but unverified); sender storage pinned indefinitely | Compose Transport+receive gate, prove credit-idempotency; specify receiver ACK de-dup | Med | Unbounded-retention-under-partition is inherent (can't give up safely without risking custody) |
| **R-D2-4** | Publisher delay + stale-retry limbo: spender sees opaque ~1h limbo, and resubmission can waste a publisher's Bitcoin fee (assigned to no one) | D2 | — | Medium | High | Funds in limbo with no progress signal; wasted-fee cost re-priced onto spenders | Spender-observable signed progress receipt; specify who eats the wasted fee; window in confs not wall-clock | Med | Safety idempotency already holds; UX/economic only |
| **R-D2-9** | Fee spikes / mempool eviction / publisher UTXO-dust: a spike can invalidate in-flight batches via the 100-block anchor bound; under-funded dominant publisher stalls everyone | D2 | — | Medium | High (during spikes) | Sends stall or get invalidated and re-proved during fee spikes | Publisher RBF/funding-UTXO SLAs; re-check the 100-block anchor bound vs worst-case confirmation time | Med | Fee markets are an external Bitcoin reality; cost/liveness exposure remains |
| **R-D2-6** | Three unrelated clocks (block height vs node-local wall-clock vs confirmation depth) drift; issuance window bound to height ≠ wall-clock intent; cross-node grant-expiry inconsistency | D2 | — | Low–Med | Medium | View grants accepted by one node, rejected by another near expiry; "valid until" semantics surprise | Document all expiry/window semantics as height-or-node-clock; skew margin near expiry | Low | Skew between independent operators is the norm; documentation-level |
| **R-D2-7** | Adversarial timing: deadline-edge BatchBundle withholding, reorg-timed republication to flip a racing winner, selective ACK-suppression griefing | D2 | — | Medium | Medium | Attacker maximizes inconsistency window / flips <6-conf race / pins sender storage for ~zero cost | Timing-aware adversary model to bound windows; minimum honest-fetch quorum; safe bounded give-up tied to blob k-replication | Med | Liveness/griefing with only availability mitigations; no protocol cure |
| **R-D5-4** | Network-layer privacy (P5 MEDIUM, not certified) + colluding-recipient linkability (coins minted together linkable, EAE analogue) | D5 | — | Medium | Medium | Off-chain graph reconstructable by a delivery-channel observer / colluding recipients | Carry as named residual; per-relationship accounts; warn against multi-recipient transactions | Med | On-chain graph removed; off-chain graph leakage is the known P5 ceiling |
| **R-D5-5** | Unrefusable inbound / compliance taint: bearer coins to a single per-account address cannot be cryptographically rejected (Tornado-dusting analogue) | D5 | — | Medium | Medium | A user receives "poisoned" coins they cannot refuse, creating compliance exposure | Wallet-level "uncollected/ignored" state | Low | Cannot prevent inbound at protocol level with single-address model |
| **R-D7-5** | MAX_IN_COINS=8 imposes a `log_8 N` consolidation tax on active receivers; consolidation sends are the most expensive proofs and compete for the same sequential slot | D7 | — | Medium | High | Active merchants burn scarce throughput on housekeeping that makes no payment | Document the cap as a throughput dial; background auto-consolidation; larger cap for merchant nodes | Med | Small cap → fragmentation tax; large cap → proving tax; no free setting |
| **R-D7-6** | MAX_IN_COINS not pinned in the spec (`SpendRecord.k: u8`, structurally ≤255); a throughput/fragmentation-defining parameter left as an unstated implementation constant | D7 | — | Medium | High (certain) | Spec/impl disagree on a load-bearing parameter | Pin MAX_IN_COINS normatively in the spec | Low | Documentation gap, fully closeable |
| **R-D7-1** | Stated throughput goals (104 tx/s "surpasses PayPal"; "bounded by L1, one commitment per TX") inherited from pre-#40 model; overstate the shipped ceiling by ~2–3 orders of magnitude | D7 | — | High | High (certain) | Public capacity claims are wrong for the shipped design | Restate ceiling as `(batches/block)×m`; publish honest ~10⁴ tx/day envelope | Low | Documentation; the underlying ceiling (R-D2-5) is the real limit |
| **R-D7-7** | Cold from-seed recovery requires full re-scan + re-verify of all global history (~1.8 TB/~18M verifies at 1x/5yr; ~180 PB at 100x) → collapses onto local-backup at scale | D7 | — | Medium | Medium | Trustless cold recovery is the first casualty of growth; re-introduces a backup dependency | Epoch checkpoints / accumulator snapshots to bound rescan; document the volume limit | High | Global unprunable accumulator makes cold rebuild scale with everyone's history |
| **R-D1-5** | v1 issuer continuity is a single point of failure (no succession/multi-sig); supply-observability is a design choice not stated as a checkable property | D1,D6 | R-D6-14 | Medium (cont.) / Low–Med (obs.) | Low–Med | Asset frozen if creator key lost; holders assume protocol-enforced scarcity (honor-system) | State supply-observability as a property; name issuer-succession/multi-sig as required v2; disclose honor-system supply at mint/accept | Med | Continuity needs a v2 issuance feature; observability formally stateable now |
| **R-D3-11** | No "wait for finality before first post-recovery spend" rule; rushed recovery inside the reorg window can produce a reorg-invalidated transition | D3 | — | Medium | Low | A user who recovers and immediately spends inside the reorg window can have it invalidated | Normative "wait for `completed` (≥6 conf) before first post-recovery spend" in §4.5 | Low | Documentation/policy; fully closeable |
| **R-D6-12** | Five-way, partly-ambiguous status vocabulary (`pending`-confs / `pending`-DA / `completed` / `failed` / `mint-verified`) is hard to surface without confusing or alarming users | D6 | — | Medium | High | Users cannot tell "confirming" from "data unavailable" from "issuer-attested" | Human-designed status copy distinguishing the two `pending` causes and `mint-verified` | Low | UX-only |
| **R-D6-2** | Receive circularity: you cannot pay an address that has never been online to publish a signed Invoice/profile; breaks "an address is enough to receive" | D6 | — | High | High | Pasting a fresh address fails; "tell them to open their app" | Auto-publish signed profile at account creation; clear actionable error for never-online addresses | Med | Resolution requires `addr_sig` under `sk₀`; a one-time online step is intrinsic |
| **R-D6-6** | ~60-min 6-conf wait on every received payment is the dominant latency; unfit for point-of-sale without a risk-bearing low-conf acceptance policy | D6 | — | Medium | High | Every received payment takes ~an hour to be safely creditable | Documented low-conf acceptance policy for low-value/POS, with risk shown | Low | Bitcoin finality cannot be engineered away; only a stated-risk policy |
| **R-D6-13** | No offline-payment concept: every settlement/value-bearing step needs connectivity; "private cash on Bitcoin" framing invites an offline-cash expectation | D6 | — | Medium | Medium | A handed-over bundle is not settled cash; naive treatment risks a double-spend | State plainly that offline payment is out of scope | Low | Intrinsic — safe credit requires accumulator anchoring (online) |

## Distinct risk count

**42 distinct conceptual risks** after dedup (canonical IDs in the matrix above).
Folded-in duplicates that are counted within a canonical row (not separately):
R-D4-1, R-D4-2, R-D4-3, R-D4-7, R-D5-1, R-D5-2, R-D5-6, R-D5-7, R-D6-1, R-D6-3,
R-D6-4, R-D6-5, R-D6-8, R-D6-9, R-D6-10, R-D6-11, R-D6-14, R-D7-2, plus the D2-10
operator-rationality and the D5 comparative-differentiator notes. (Original raw
finding count across the seven files was ~70 IDs; dedup to 42 distinct.)

## Severity tally (after dedup)

| Severity | Count | IDs |
|---|---|---|
| **Critical** | 2 | R-D3-1, R-D2-1 |
| **High** | 16 | R-D2-5, R-D2-8, R-D3-3, R-D3-2, R-D3-9, R-D5-3, R-D7-3, R-D4-4, R-D1-1, R-D3-13, R-D3-8, R-D3-10, R-D4-6, R-D2-3, R-D7-1, R-D6-2 |
| **Medium** | 22 | R-D7-4, R-D1-3, R-D4-5, R-D4-8, R-D1-4, R-D3-6, R-D3-4, R-D3-5, R-D3-7, R-D2-2, R-D2-4, R-D2-9, R-D2-7, R-D5-4, R-D5-5, R-D7-5, R-D7-6, R-D7-7, R-D3-11, R-D6-12, R-D6-6, R-D6-13 |
| **Low / Low–Med** | 2 | R-D2-6 (low–med), R-D1-5 (mixed med/low–med) |
| **Total** | **42** | |

(R-D2-1 is Critical at low likelihood on mainnet; R-D6-2 is graded High by D6 as
a UX-adoption blocker. Both severities are carried at the source grade per the
honesty mandate.)

## TOP-5 risks

Selected on severity × likelihood × how-fundamental, with concept-gaps preferred
over ops-gaps. The two Criticals and the most-fundamental, highest-likelihood
Highs win; pure-documentation Highs (R-D7-1) and bounded-likelihood Criticals
(R-D2-1) are weighed but not chosen — see the justification at the end.

### 1. R-D3-1 — Seed restores keys, not funds (effective `k=1` → unrecoverable balance)

**Why top-5.** This is the only **Critical** with non-trivial (Medium)
likelihood, and it is the sharpest contradiction between the system's deepest
user mental model ("my seed is my money") and its reality. The spendable *value*
of a coin lives only in its off-chain `CoinProof` bundle and "cannot be derived
from the seed or a hash"; recovery is a data-availability problem, not a
key-derivation problem. P9 certifies recovery never accepts a *forged* coin but
explicitly does **not** certify that you get your *real* coins back — the
liveness half returns a counterexample without fairness. It folds the same gap
seen across D5 and D6.

**Failure scenario.** A self-hoster's only node holds the latest self-delivered
change/state bundle at effective `k=1` (own node = replica #1; sender dropped its
copy after ACK; the "third" advertised relay was the same box). The disk dies.
The seed restores identity and scan keys but the change bundle — the spend
credential for the next spend — exists nowhere reachable. The live spendable
balance is gone, with the user believing they "backed up correctly."

**Recommended mitigation.** Client-enforced ≥2 **independent**-replica pre-spend
gate (the wallet MUST NOT report a balance "safe" until ≥2 independent holders
are confirmed), a surfaced funds-recoverability indicator distinct from "seed
saved," and a mandated wallet disclosure that the seed alone does not restore
funds.

**Cost / feasibility.** **Medium** and feasible — it is wallet policy + UX, not a
redesign. But the residual is intrinsic: "all replicas lost ⇒ funds gone" is true
by construction. Mitigation makes the loss *rare and warned-about*, not
impossible.

### 2. R-D2-5 — Sequential single-writer accumulator (throughput ceiling + MEV + griefing)

**Why top-5.** The single most under-appreciated *structural* risk: it is
**High/High**, it is the design's correctness backbone (it is what makes
first-spend-wins a clean total order), and it simultaneously caps the headline
capability and hands an attacker a cheap latency weapon and a centralization
driver. It is the canonical fold of four dimensions (D2/D4/D5/D7) — the single
most cross-cutting finding in the review.

**Failure scenario.** Under any non-trivial adoption, publishers race the same
`prev_root`; only one batch lands per Bitcoin block uncoordinated, so the central
throughput envelope is ~0.17 tx/s (≈2–3 orders below the stated goal). A
well-capitalized publisher chain-bids every tip slot, becoming a de-facto
exclusive writer that sees and orders the entire global spend flow (privacy +
censorship surface concentrated); it stale-forces rivals, burning their recursive
proofs for only a fee premium while earning fees on its own batch — a *profitable*
griefing strategy that prices out small publishers.

**Recommended mitigation.** Maximize batch size `m` so payments-per-inscription
is high; specify a **permissionless** prev_root-leasing / coordination scheme; a
cheap commit-ticket before heavy proving to kill the wasted-work griefing; and
publish the honest throughput envelope.

**Cost / feasibility.** **High.** You cannot make the accumulator concurrent
without giving up the property the verification certifies; any in-block
batch-chaining is "a single sequencer in disguise." All real mitigations are
*amortization*, not removal — the sequential gate is intrinsic to "only Bitcoin,
no consensus."

### 3. R-D2-8 — Off-chain BatchBundle DA gates accumulator progress + honest-node divergence

**Why top-5.** **High/Medium** and the *deepest* model-vs-reality gap: the
verified property "two honest nodes at the same tip derive identical
classification" is exactly the property reality does not provide once nullifiers
and the aggregate proof live off-chain. It is the network's only consensus object
depending on off-chain data — the closest thing zkCoins has to a chain-halt — and
"the accumulator's progress is verifiable by anyone at any time" is not a stated
property (folds D1's P12 and D5's larger-blast-radius-than-the-paper finding).

**Failure scenario.** Node X fetched a BatchBundle and admitted its nullifiers;
Node Y cannot reach any replica and leaves the batch `pending`-due-to-DA. At the
*same* Bitcoin tip the two honest nodes hold different accumulators and give
opposite double-spend answers. A self-sovereign receiver querying Y is induced to
credit a coin X already knows is double-spent. §4.6 itself names the worst case:
universal unavailability "soft-forks the network."

**Recommended mitigation.** Make Path-B's "query the latest *bundle-verified*
root" normative and give light clients a way to detect a DA-behind serving node;
model per-node accumulators and prove *bounded-divergence + eventual-agreement*
rather than assuming a single global view (A13); add an incentivized archival role
for BatchBundles (which, unlike CoinProof bundles, have no natural long-term
holder).

**Cost / feasibility.** **High.** Honest-node divergence under partial DA is
intrinsic to "on-chain commits only a root." All answers are availability
mitigations that make divergence rare and self-healing; impossibility would
require putting nullifiers back on-chain (which #40 removed for privacy/cost).

### 4. R-D3-3 / R-D3-9 — Operator holds `ivk`+`ovk`+`op` = lifetime full view; "trustless" framing gap

**Why top-5.** Counted as the operator-honeypot risk cluster (R-D3-3 the
mechanism, R-D3-9 the framing; R-D3-2 non-rotatability reinforces). **High/High**:
it is the *default* deployment for any infra-less mass user, and it is the single
biggest honesty gap — the headline "Bitcoin-anchored · Shielded · Trustless" is
false for privacy in exactly the configuration most users will run. Sharper than
any peer system: no single third party in Zcash/Monero/Tornado/Lightning holds an
equivalent complete incoming+outgoing view of a user's private ledger.

**Failure scenario.** A phone user delegates `{ivk,ovk,op}` to a foreign operator
to receive 24/7. That operator now reads 100% of the account's amounts, assets,
counterparties and timing — forever, because the keys never rotate and switching
providers does not strip the old one. The user picked the only available operator
on a young network (R-D3-10's single-provider default) believing "trustless"
meant private; it meant theft-proof only.

**Recommended mitigation.** Replace/qualify the "trustless / no trusted operator"
headline with the precise claim — "your operator cannot steal your funds; in the
hosted configuration your operator can see your full transaction history" — and
promote the foreign-node row to the *default* framing. Longer term: diversified,
retire-able incoming-view keys so an operator can actually be evicted.

**Cost / feasibility.** Framing fix is **Low** cost and should ship immediately.
The underlying eviction/rotation fix is **High** (intrinsic to the fixed
hardened-child key hierarchy; today eviction = new identity). The honest framing
is the cheapest highest-integrity fix in the entire review.

### 5. R-D4-4 — Uncompensated long-tail DA storage commons → coins permanently unspendable

**Why top-5.** **High/High**, and the *incentive* root cause of the protocol's
graded MEDIUM-liveness gap (P9's bracketed-out failure mode). Chosen over the
bounded-likelihood Critical R-D2-1 and the pure-doc High R-D7-1 because it is a
fundamental concept gap (incentive design absent), certain under rational play,
and it is where coins actually become *permanently* lost at long horizons rather
than at a rare tail event.

**Failure scenario.** Indefinite, unprunable, monotonic bundle storage is
uncompensated — there is no fee, reward, or slashing for serving the long tail. A
rational operator serves its own users and prunes (or claims it checked the
≥3-peer guard and prunes anyway) old bundles nobody has asked for in years.
Detection is impossible until someone needs the bundle — during recovery, years
later — at which point the coin is permanently unspendable and the recovery
false-rejects.

**Recommended mitigation.** Design an incentive for long-tail DA: a
storage-fee/retrieval-payment market, a paid archival tier, or an erasure-coded
DA layer with proofs-of-retrievability and challenge/response slashing. Until
one exists, label long-tail DA an explicit under-provision risk consistent with
P9's MEDIUM grade.

**Cost / feasibility.** **High** — it requires a new economic layer the
"no-consensus, no-token" design has deliberately avoided. Without it, §4.6's
"MUST retain" is unenforceable, so this is both the most fundamental liveness gap
and the hardest to close within the current design philosophy.

### Why these five, and what was weighed but not chosen

The five span the concept's load-bearing failure axes: **funds-recoverability**
(R-D3-1), **throughput/centralization** (R-D2-5), **consensus-object
availability/consistency** (R-D2-8), **privacy-trust honesty** (R-D3-3/9), and
**long-term liveness economics** (R-D4-4). Each is High-or-Critical, each is
fundamental (a concept gap, not ops polish), and four of the five are intrinsic
limits that more verification cannot close.

Deliberately **weighed but not chosen**:

- **R-D2-1 (≥6 reorg, Critical)** — genuinely Critical and genuinely the
  fund-losing case A12 hides by construction, but Low likelihood on Bitcoin
  mainnet and *partially* policy-mitigable ("wait longer"). It loses the
  fifth slot to R-D4-4, which is High but *High-likelihood and certain under
  rational play*. R-D2-1 remains the most important thing to **state honestly in
  the no-double-spend headline**.
- **R-D5-3 (circuit soundness, High)** — catastrophic if it fires and the exact
  Zcash-Orchard 2026 failure class, but it is an **implementation** soundness
  question (F15), out of scope of the spec-level review, and Low–Med likelihood.
  It is the top *deployment* gate rather than a top *concept* risk.
- **R-D7-1 / R-D7-3 (throughput claims / unprunable DA volume)** — R-D7-1 is
  pure documentation (the real ceiling is R-D2-5, already chosen); R-D7-3 is the
  most *irreversible* wall but degrades gradually and overlaps R-D4-4's incentive
  root. Both are reflected through their canonical/adjacent top-5 entries.
- **R-D6-2 (receive circularity, High UX)** — a real adoption blocker, but a
  UX-honesty/onboarding gap with a Medium-cost fix (auto-publish profile), not a
  fund/consensus-level concept threat.
