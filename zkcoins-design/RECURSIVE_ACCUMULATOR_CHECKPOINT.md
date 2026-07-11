# Recursive Accumulator Checkpoints — removing the DA retention wall without leaving Bitcoin

**Status:** Proposal / concept (pre-cryptographic-review)
**Scope:** the global nullifier accumulator, fresh-sync, and long-term off-chain retention (spec §1.7.10, §2.2, §2.5, §3.6, §3.7)
**Targets:** `R-D7-3` (unprunable monotonic BatchBundle storage), `P17` (economic sustainability of long-term DA), and the fresh-sync half of `P12` — **not** the live-progress DA problems (see §7).
**Relation to other proposals:** an alternative to [`ACCUMULATOR_SELF_PUBLISH.md`](./ACCUMULATOR_SELF_PUBLISH.md) (which resolves DA by reverting to on-chain nullifiers, sacrificing constant on-chain size). This proposal keeps the constant-size `BatchInscription` and attacks retention instead. The two are mutually exclusive top-level directions; §8 compares them.

---

## 1. TL;DR

The DA problem that hurts zkCoins long-term is **not** "coins can be stolen" (they can't — DA is liveness, never safety) but **"every `BatchBundle` must be retained forever by an unrewarded MUST, and a fresh trustless verifier must fetch and re-verify all of them from genesis."** The project's own concept review calls this the *"most irreversible long-term wall"* (`RISKS.md` R-D7-3) and concedes it is *"only deferred, not removed without a DA layer."*

This proposal argues that conclusion is too pessimistic **for the retention/fresh-sync axis specifically**, and that the cure is already in zkCoins' toolbox:

> Maintain a **rolling recursive proof `Π_n`** that attests, in constant size, that the current accumulator root `R_n` (and anchors-MMR root `A_n`) is the honest genesis-to-`n` fold of every admitted batch. A fresh node verifies **one** proof `Π_c` at a checkpoint `c` instead of replaying `c` batch proofs, downloads a **self-verifying nullifier-set snapshot** (checked against the proven `R_c`), and then only needs the bundles for the small window `(c, n]`. Everything before `c` becomes **discardable by the whole network**.

This uses only primitives zkCoins already ships — the same **cyclic PCD recursion** the `AggregateBatchProof` (`C_batch`) already performs at the intra-batch level, the existing **anchors MMR**, and the Poseidon SMT — and it adds **no auxiliary chain, no token, and no trusted setup** (the proof system is FRI-transparent). It is the "in-house, elegant" path.

It does **not** cure the *live-progress* DA attacks (publish-and-withhold liveness DoS; selective-serving fork) documented in [`../notes/da-problem-zkcoins-analyse.md`](../notes/da-problem-zkcoins-analyse.md). Those are about the availability of the *current* bundle and are out of scope here (§7).

---

## 2. The problem, precisely

Today a fully-trustless (Path-A) verifier must, per spec §3.6 / §3.7:

1. scan every `BatchInscription` (on-chain, cheap, **Bitcoin-DA-guaranteed**),
2. fetch every `BatchBundle` (off-chain, ~100 KB recursive proof + all `SpendRecord`s each, **DA-fragile**, `k=3`),
3. verify every `AggregateBatchProof`,
4. fold each `prev_root → new_root` transition to build the nullifier SMT and the anchors MMR.

Step 1 is O(N) but backed by Bitcoin. Steps 2–3 are the wall: **unbounded, DA-fragile, and unrewarded**. The nullifier set itself is unprunable (uniformly-distributed keys, §3.7), so storage grows monotonically and the cost of *becoming* a fresh trustless verifier grows without bound. Rational actors therefore drift to Path-B (trust a node), which **concentrates the nullifier-set custody on a shrinking archival set** — a slow-acting centralization of the very property the project sells as trustless. That erosion, not theft, is the real damage.

---

## 3. Why the tools already exist

Three existing pieces make this a *lift*, not an invention:

- **`C_batch` inner-mode chaining (§2.2 cl. 4, §2.5).** The batch aggregator is already a cyclic recursive circuit whose inner node consumes **two child `AggregateBatchProof`s** and enforces *"left child's `new_root` == right child's `prev_root`; carry `prev_root`…`new_root` forward."* A chain-level checkpoint proof is **exactly this construction lifted one level**: instead of composing sub-batches within one batch, it composes batches within the whole chain. Same primitive, same public-input shape, same Poseidon SMT transition witness.

- **The anchors MMR (§1.7.10).** An append-only Merkle Mountain Range already accumulates the `member_root` of every `completed` batch, with in-circuit `extends(anr, anr')` **consistency proofs** and `O(log n)` membership proofs. It is currently *derived, not consensus-bearing* — nobody holds a succinct proof that the MMR root is the honest fold; a node still replays to build it. The spec even notes: *"A future version MAY commit the anchors root inside the `BatchInscription`."* The checkpoint proof is the missing succinct attestation over exactly this structure.

- **FRI-transparent recursion.** zkCoins' proofs need **no trusted setup** (only the BitVM bridge verifier uses a Groth16 ceremony, per the roadmap). Adding a recursion layer adds **no ceremony** — unlike a Groth16-based checkpoint, which would.

---

## 4. Construction

### 4.1 The chain-state proof `Π`

Define a cyclic PCD circuit `C_chain` with public inputs `(nf_root, anchors_root, n, chain_commit)` where `n` is the number of admitted batches folded and `chain_commit` binds the ordered sequence of inscribed `(prev_root, new_root, member_root)` triples (e.g. a running Poseidon hash, one absorb per batch).

- **Base:** `Π_0` attests the empty state — `nf_root = E₂₅₆`, `anchors_root = anr_empty`, `n = 0`, `chain_commit = ε`.
- **Step:** `Π_i` consumes `Π_{i-1}` (verified cyclically) **and** batch `i`'s `AggregateBatchProof` (verified under `C_batch`'s verifier data), and enforces:
  1. `Π_{i-1}.nf_root == batch_i.prev_root` (chain continuity — identical to `C_batch` cl. 4, one level up);
  2. `batch_i.new_root == Π_i.nf_root` (carry the fold forward);
  3. the anchors-MMR append of `batch_i.member_root` advances `Π_{i-1}.anchors_root → Π_i.anchors_root` (the existing MMR append gadget);
  4. `chain_commit` absorbs `(prev_root, new_root, member_root, m)` of batch `i`.

`Π_n` is **constant-size and constant-verify-time in `n`** (cyclic recursion, exactly like the per-account proof and the aggregate proof). It attests: *"`nf_root` is the correct SMT fold of a batch sequence whose ordered commitments are `chain_commit`, and `anchors_root` is the matching MMR."*

### 4.2 Binding `Π_n` to Bitcoin

`Π_n` proves internal validity but not *"this is the canonical Bitcoin history."* The verifier closes that gap cheaply and **without any off-chain fetch**: it scans the inscription **headers** (on-chain, 231 B each, Bitcoin-DA-guaranteed), recomputes `chain_commit` from the inscribed `(prev_root, new_root, member_root, m)` sequence in canonical order (§3.6 step 4), and checks it equals `Π_n.chain_commit`. Header scanning is the O(N) part that Bitcoin *already* guarantees; what disappears is fetching and verifying the heavy off-chain proofs.

### 4.3 The self-verifying nullifier-set snapshot

`Π_c` proves the **root** `R_c` is honest, but a Merkle root does not enumerate leaves — and a node still needs the leaf set to (a) build insertion witnesses for new batches and (b) serve Path-B non-membership paths. So the checkpoint is paired with a **snapshot**: the occupied nullifier set (~32 B per `nf` plus sparse-SMT structure) as of batch `c`.

The snapshot's integrity is **self-verifying against the checkpoint-proven `R_c`**: recompute the SMT root from the snapshot and check equality with `Π_c.nf_root`. This is the decisive property — **the snapshot can come from any source, even a fully untrusted one, because a bad snapshot cannot hash to the proven root.** Malicious withholding of the snapshot dissolves: any single honest copy anywhere in the world suffices, and no one can feed you a forged one.

### 4.4 Fresh-sync with checkpoints

A node joining at tip `n`, given the latest checkpoint at `c`:

1. verify `Π_c` (one recursive verification) and bind it to Bitcoin (§4.2) — trust `R_c`, `A_c`;
2. download + self-check the nullifier snapshot against `R_c` (§4.3);
3. fetch and verify only the bundles for the window `(c, n]` and fold them normally (§3.6).

Cost drops from **O(N) DA-fragile bundle fetch+verify** to **O(1) proof + O(set) self-verifying snapshot + O(window) bundles.** Batches `≤ c` — their 100 KB proofs and full `SpendRecord`s — are **discardable network-wide**.

### 4.5 The checkpointer role

Extending `Π` is a permissionless, **stateless-in-the-cryptographic-sense** role (like the publisher): the output is publicly verifiable, so a checkpointer is trusted for **liveness only**, never correctness. Two viable cadences:

- **Continuous:** the publisher of batch `i` also extends `Π_{i-1} → Π_i` (folds its own batch in). Makes publishing heavier and *stateful* (needs `Π_{i-1}`).
- **Epochal (recommended):** an independent checkpointer folds a range `(c, c']` every epoch (e.g. daily / every K batches). Publishers stay light; only the checkpointer carries the rolling proof.

Either way, the proof is checkpointed to relays like any bundle; because it is self-verifying, one honest replica suffices.

---

## 5. What it removes vs. what it does not — precise ledger

| Data | Today | With checkpoints |
|---|---|---|
| Own `CoinProof` bundles | retain forever (= key custody) | **unchanged** — this is self-custody, not a network burden |
| Historical `AggregateBatchProof`s (100 KB × N) | fetch+verify all on fresh sync; retain forever | **discardable ≤ c**; verify one `Π_c` instead |
| Historical `SpendRecord`s (for verification) | retain forever | **discardable ≤ c** for consensus |
| Nullifier **set** (32 B × count) | held by every Path-A node, unprunable | still needed, but **snapshotted + self-verifying** → sourceable from anywhere, withholding-proof |
| Bundles in window `(c, n]` | — | retain until next checkpoint (bounded) |

**Does not solve:**

- **Seed-only backup recovery** (§4.5 recovery): re-scanning old bundles to recognise one's *own* `SpendRecord`s. Discarding bundles `≤ c` removes this **backup** path — but primary recovery is `CoinProof` self-delivery to one's own relays (§4.2), which is independent. Honest cost: the redundant recovery path narrows to "since last checkpoint." Mitigable: a wallet can self-archive its own historical `SpendRecord`s (small, self-interested), or checkpoints can retain a per-account detection index.
- **Live-progress DA** (publish-and-withhold; selective-serving fork): these concern the *current* bundle's availability and are orthogonal (§7).

---

## 6. Does this rebut `P12`'s "impossibility requires on-chain nullifiers"?

`GAPS_AGAINST_P1_P10.md` (P12) argues accumulator-progress verifiability by anyone is impossible-to-guarantee without on-chain nullifiers. The checkpoint construction narrows that claim for the **historical** axis: you do **not** need nullifiers on-chain to give a late joiner everything it needs, if you have (1) **Bitcoin-guaranteed** availability of the *root/header* sequence (already true — it's in the inscriptions), (2) a **succinct validity proof** that the root is the honest fold (`Π`), and (3) a **self-verifying** leaf snapshot (checkable against the proven root, hence trustless from any source). That triple reconstructs the "anyone can obtain and verify the state" property that on-chain nullifiers provide — **for history**. It does *not* rebut P12 for the **live tip** (the current batch still gates on its bundle). So P12's residual shrinks from "all of history + the tip" to "the tip only." That is a real reduction, and it is the honest limit of the claim.

---

## 7. Out of scope (do not overclaim)

The two *live-progress* attacks in [`../notes/da-problem-zkcoins-analyse.md`](../notes/da-problem-zkcoins-analyse.md) — **publish-and-withhold** (§3.6 step 5 precedes the fail-able steps, so a locator to a never-served bundle hangs `pending` forever and, under serial commitment, can freeze anchoring for a few dollars) and **selective serving** (a valid bundle shown to only part of the network → accumulator fork) — are about the *current* bundle and are **not** addressed here. They need their own fix (e.g. a fail-closed timeout on unfetchable locators, or on-chain member-root commitment). This proposal is strictly about **retention and fresh-sync**.

---

## 8. Comparison to the alternatives

| Approach | Constant on-chain size | Removes retention wall | Bitcoin-only | Token/consensus | Trusted setup |
|---|---|---|---|---|---|
| **Recursive checkpoint (this)** | ✅ keeps `BatchInscription` | ✅ history discardable ≤ c | ✅ | none | none (FRI) |
| Revert to on-chain nullifiers ([`ACCUMULATOR_SELF_PUBLISH.md`](./ACCUMULATOR_SELF_PUBLISH.md)) | ❌ per-tx bytes return | ✅ Bitcoin holds nullifiers | ✅ | none | none |
| Paid pinning / storage-fee market | ✅ | ⚠️ deferred, not removed | ✅ | needs a fee/market primitive | none |
| Auxiliary-chain DA (ePrint 2025/569) | ✅ | ✅ | ❌ breaks "not a sidechain" | aux-chain consensus | varies |

The checkpoint is the only row that keeps **both** constant on-chain size **and** the Bitcoin-only positioning while genuinely removing (not deferring) the retention wall.

---

## 9. Open problems (honest, for cryptographic review)

1. **Checkpointer liveness/incentive.** If the latest `Π` is lost, rebuilding requires replaying from the last durable checkpoint (needs bundles back to it). So DA shifts from "all bundles" to "latest `Π` + bundles since it" — **much** smaller, but not literally zero. Needs the same archival-incentive thought as bundles, on a far smaller object.
2. **Reorg composition.** `Π` must only fold `completed` (≥6-conf, §3.9-stable) batches; a checkpoint at finality depth is reorg-safe by the same assumption the anchors MMR already relies on. Needs explicit statement that checkpoints lag the tip by ≥ finality.
3. **Proving throughput.** One recursive fold per batch (epochal: per range). Constant output size (~100 KB like `AggregateBatchProof`); the question is sustained prover cost — the `plonky3` benchmarks (`../benchmarks/`) are the place to project it.
4. **Snapshot format + transport.** Compact sparse-SMT snapshot encoding, incremental snapshots between checkpoints, and the `/v1/` service to serve/verify them.
5. **Interaction with account anchors (§2.1 cl. 10).** Receives prove `extends` against the anchors MMR; a checkpoint that lets nodes drop pre-`c` structure must preserve the ability to serve `extends`/membership for any historical `anchors_root` a live coin might still reference. Likely fine (the MMR peaks + proven `A_c` suffice), but must be shown.

---

## 10. Verdict

The recursive-checkpoint path is **conceptually sound, uses only in-house primitives, and changes the standing verdict on the project's single most-irreversible long-term wall** (`R-D7-3`) from *"only deferred"* to *"removable for history without an auxiliary DA layer."* It does not touch the safety core, does not require a token or a foreign chain, and adds no trusted setup. The costs are honest and bounded: a small residual DA dependency on the latest proof, a narrowed seed-only backup-recovery path, and prover cost to be measured. It is the highest-leverage response to the DA criticism because it converts the sharpest external attack surface into a differentiator using tools zkCoins already ships.

**Recommended next step:** a `plonky3` spike (mirroring `../spikes/plonky3-recursion-spike/`) that folds K real `AggregateBatchProof`s into one `C_chain` proof and measures fold-time + verify-time + snapshot size, to convert this concept into a go/no-go.
