# Recursive Accumulator Checkpoints — compressing historical verification without hiding the DA boundary

**Status:** Proposal / concept, pre-cryptographic-review; **blocked on objective live-admission semantics**
**Scope:** global nullifier accumulator, anchors MMR, fresh sync, and long-term off-chain retention (spec §1.7.10, §2.2, §2.5, §3.6, §3.7)
**Targets:** reduce the storage and replay costs behind `R-D7-3`/`P17` and the historical half of `P12`; does **not** by itself solve live data availability or remove every long-term DA dependency
**Relation to other proposals:** potential alternative/complement to [`ACCUMULATOR_SELF_PUBLISH.md`](./ACCUMULATOR_SELF_PUBLISH.md), subject to the prerequisites and pruning gates below

---

## 1. Decision summary

A rolling recursive proof can replace verification of all historical `AggregateBatchProof`s with one constant-size verification. A self-checked state package can also replace historical `BatchBundle`s as the source of the current nullifier set and proof-serving indexes.

That is valuable **compression**, but it is not yet a complete DA cure:

1. zkCoins v1 does not define an availability-independent canonical admission result under selective bundle serving. A checkpoint cannot prove that it folded the *canonical* history until that live rule is fixed.
2. A Merkle-root-checked snapshot has trustless **integrity**, not guaranteed **availability**. At least one complete copy must remain obtainable.
3. Existing `CoinProof` bundles do not carry all portable anchoring witnesses needed after their creating `BatchBundle` is deleted.
4. The anchors MMR still needs enough retained structure to validate historical roots and generate membership/extension proofs.

Accordingly, this proposal changes the standing verdict from “historical proofs can never be compressed” to “historical proof verification is recursively compressible.” It does **not** change `R-D7-3`/`P17` to “solved” until the prerequisites and pruning gates in §§4–7 are implemented and reviewed.

---

## 2. Security boundary

### 2.1 What recursion can prove

Given an ordered sequence of valid `AggregateBatchProof`s, a cyclic circuit can prove in constant size that:

- every batch transition is valid;
- each `prev_root → new_root` transition chains from its predecessor;
- each batch's `member_root` is appended to the anchors MMR;
- the resulting nullifier root and anchors root equal the proof's public outputs.

This removes O(N) recursive-proof verification for a fresh node.

### 2.2 What recursion cannot prove from the current protocol

Proof validity does not establish which of several on-chain candidates is canonical when availability differs by observer. In particular, the current §3.6 state machine permits the following views:

- Node A fetches the first valid candidate `r0 → r1` and admits it.
- Node B cannot fetch it, remains at `r0`, and later admits `r0 → r2`.

A checkpointer can build an internally valid proof for either branch. “The proof verifies” therefore does not imply “this is the unique Bitcoin-canonical zkCoins history.” This is the live-DA/selective-serving problem, now inherited by checkpoint selection.

No ZK circuit can prove that an off-chain object was globally unavailable. A local timeout, replica count, or claim that a fetch failed is not an objective Bitcoin fact.

### 2.3 Narrow safety claim

Loss or withholding of DA does not reveal a spend key or let an attacker forge another user's signature. Partial DA can nevertheless split the global nullifier view and cause cross-view double credit. This document therefore uses:

- **custody safety** for “no foreign key/coin forgery”; and
- **ledger safety** for “honest verifiers agree on the spend/nullifier state.”

Checkpoints must preserve both; “DA is only liveness” is not a sufficient system-level claim.

---

## 3. Existing primitives and required new work

The construction can reuse:

- `C_batch`'s cyclic recursion pattern and `prev_root → new_root` chaining;
- the Poseidon nullifier SMT;
- the anchors MMR append, membership, and consistency relations;
- a transparent FRI-based proof system, so no trusted setup is introduced.

It still requires a new circuit and protocol objects. `C_chain` verifies one prior `C_chain` proof plus a `C_batch` proof, updates a separate MMR state, binds Bitcoin-visible header data, and uses its own pinned verifier data. It is not merely a reuse of the existing `C_batch` public-input shape, and its cost must be measured rather than assumed.

---

## 4. Prerequisite: objective live admission

Before a checkpoint can be a trustless replacement for genesis replay, the base protocol must define one canonical result for every on-chain candidate sequence, independent of which relay answered a particular node.

The rule must cover at least:

1. whether scanning continues past a `pending`-due-to-DA inscription;
2. when such an inscription becomes terminal;
3. whether a later-arriving earlier bundle triggers rewind and canonical replay;
4. how two nodes with different bundle observations converge;
5. what objective evidence makes a candidate admissible or skippable.

A fail-closed local timeout is insufficient: one node may have the bundle and admit while another times out. Exposing `member_root` on-chain is also insufficient: it binds data but does not make the proof/data available.

Candidate design directions, each with an explicit cost/trust trade-off:

| Direction | Objective validity/ordering | DA assumption | Main cost |
|---|---|---|---|
| Put sufficient nullifier/validity data on Bitcoin | yes | Bitcoin | larger on-chain footprint |
| Put the aggregate validity proof on Bitcoin and define deterministic state transitions | proof validity yes; member data/recovery still separate | Bitcoin for proof, off-chain for other data | ~proof-size on-chain cost |
| External DA certificates/committee | only under the certificate's security assumption | external quorum/network | adds consensus/trust and failure modes |
| Current `k=3` relay rule + local timeout | **no** | observer-dependent | does not close selective serving |

Until one direction is specified, implemented, and reviewed, a recursive checkpoint is an **acceleration hint**, not a trustless Path-A replacement.

---

## 5. Checkpoint construction after the prerequisite is met

### 5.1 Bitcoin-visible admission commitment

The current `BatchInscription` contains:

`(publisher_pubkey, prev_root, new_root, bundle_locator, block_anchor, signature)`.

It does **not** contain `member_root` or `m`; those values exist only behind:

`bundle_locator = Hc("BatchBundle", prev_root ‖ new_root ‖ u32-be(m) ‖ member_root)`.

Therefore a fresh verifier cannot recompute a commitment over on-chain `(prev_root, new_root, member_root, m)` tuples without fetching the historical bundles. The checkpoint must instead bind exact Bitcoin-visible data.

Define for every admitted inscription:

```text
header_digest_i = Hc(
  "ChainHeader/v1",
  network_tag,
  bitcoin_block_hash,
  bitcoin_height,
  reveal_tx_index,
  reveal_txid,
  serialize(BatchInscription_i)
)

chain_commit_i = Hc("ChainFold/v1", chain_commit_{i-1}, header_digest_i)
```

The location fields prevent the same valid inscription from being transplanted to a different position or network. A fresh verifier scans Bitcoin and recomputes these digests from on-chain bytes.

**Important:** the verifier must know which headers were *admitted*. Under zkCoins v1 that classification still depends on off-chain availability. Section 4 must therefore be resolved first, or the commitment must cover every discovered candidate and `C_chain` must prove the protocol's objective admit/reject transition for each one. “Unavailable to this checkpointer” cannot be a provable reject reason.

### 5.2 `C_chain`

After canonical admission is objective, define `C_chain` with public inputs:

`(nf_root, anchors_root, admitted_count, chain_commit, checkpoint_height)`.

- **Base:** empty SMT root, empty anchors root, count `0`, empty fold commitment.
- **Step:** verify `Π_{i-1}` and batch `i`'s `AggregateBatchProof`, then enforce:
  1. prior `nf_root == batch.prev_root`;
  2. output `nf_root == batch.new_root`;
  3. `Hc("BatchBundle", prev_root ‖ new_root ‖ u32-be(m) ‖ member_root)` equals the on-chain `bundle_locator` in the witnessed inscription;
  4. publisher signature/S2C and every other admission condition not already made objective outside the circuit are verified consistently;
  5. `member_root` is appended to the prior anchors MMR root;
  6. `chain_commit` absorbs the exact `header_digest_i`;
  7. only batches beyond the protocol finality depth are folded.

Whether Bitcoin header/transaction inclusion is checked inside `C_chain` or by the external verifier must be fixed in the security specification. If external, the verifier scans Bitcoin and compares the complete ordered `chain_commit`; if internal, `C_chain` needs an authenticated Bitcoin-header/inclusion relation and its assumptions must be explicit.

The recursive output can be constant-size and constant-verify-time in the admitted batch count. Proving time remains at least linear in newly folded batches.

### 5.3 Checkpoint package

A usable checkpoint is not only `Π_c`. It is a versioned manifest:

```text
CheckpointPackage_v1 = {
  network_tag,
  checkpoint_height,
  checkpoint_block_hash,
  admitted_count,
  chain_commit,
  nf_root,
  anchors_root,
  chain_proof,
  nullifier_snapshot_hash,
  anchors_index_hash,
  completed_batch_index_hash,
  format_version
}
```

The referenced payloads are:

- **nullifier snapshot:** occupied nullifiers plus canonical SMT encoding sufficient to recompute `nf_root` and serve new insertion/non-membership witnesses;
- **anchors proof-serving index:** enough MMR leaves/internal nodes to validate historical `anchors_root`s and generate membership/extension proofs;
- **completed-batch index:** maps Bitcoin-visible admitted headers/`bundle_locator`s to MMR positions and `member_root`s, authenticated to the proven state.

Every encoding, domain tag, ordering rule, and hash must be normative. A root match gives integrity; completeness follows only if recomputing the specified structure from the full payload yields the proven root.

### 5.4 Availability and discovery

The package and all referenced payloads remain DA objects. “Any single honest copy suffices” means a malicious source cannot forge them; it does not guarantee a copy exists or will answer.

Before pruning source bundles, the protocol needs:

- at least `k` independent durable holders for the complete package;
- authenticated discovery of the latest final checkpoint;
- a retention/incentive policy for snapshots and MMR indexes;
- rebuild rules from the previous durable checkpoint;
- optional erasure coding/chunking with a full-root/completeness check;
- a maximum checkpoint window so the uncheckpointed bundle tail is bounded.

The nullifier snapshot remains O(total nullifiers), approximately 32 bytes per occupied key plus structure. It grows forever. Checkpointing removes historical proof replay and can reduce bytes substantially, but does not make Path-A state O(1) or remove the long-term storage economy.

---

## 6. Coin portability and pruning gate

Existing `CoinProof` bundles contain the creating proof, output inclusion proof, an optional `anchor_hint`, and the creating proof's anchors opening. The receive path may still fetch from the historical `BatchBundle`:

- the creating `SpendRecord`;
- its member path to `member_root`;
- evidence that this `member_root` belongs to a completed admitted batch;
- MMR consistency evidence for historical `anchors_root`s.

Deleting every pre-checkpoint `SpendRecord` can therefore make a long-offline recipient unable to verify/fold an otherwise valid coin. This is a spendability/recovery regression, not merely a loss of a redundant seed scan.

Before batch pruning, define a portable anchoring witness, for example:

```text
PortableAnchorWitness_v1 = {
  creating_spend_record,
  batch_member_root,
  member_path,
  batch_inscription_id,
  mmr_leaf_index
}
```

Together with `Π_c`, the authenticated completed-batch/MMR indexes, and a generated membership/extension proof, this must let a fresh node perform every §2.3.3/clause-10 check without the original `BatchBundle`.

Required migration rules:

1. New `CoinProof` deliveries include or receive an ACK-tracked follow-up containing the portable witness once their batch is known.
2. Existing coins created before activation retain access to their historical BatchBundles or undergo witness refresh.
3. The anchors index remains available long enough to generate proofs for dormant coins and historical `anchors_root`s.
4. A BatchBundle is prunable only after its aggregate validity is covered by a final checkpoint **and** the protocol's portable-witness obligations for its members are satisfied.

Because a publisher cannot necessarily prove that every recipient has durably received its witness, the exact pruning condition and responsibility split among sender, recipient, publisher, and archival nodes is an open protocol decision. Until it is resolved, v1 BatchBundles remain non-prunable.

---

## 7. Precise remove/retain ledger

| Data | Potential result after all gates | Remaining obligation |
|---|---|---|
| Historical `AggregateBatchProof`s | replaceable by `Π_c` | checkpoint proof must be available and canonically bound |
| Historical `SpendRecord`s in public BatchBundles | conditionally prunable | every live/dormant coin needs a portable copy/witness |
| Nullifier set | not prunable by age | snapshot remains O(total nullifiers) and must be served |
| Anchors MMR | large bundle payloads removable | proof-serving index/historical consistency data remains |
| Completed-batch metadata | compressible/authenticatable | mapping to headers, locators, member roots, and MMR positions remains |
| Bundles after checkpoint | bounded by cadence | must remain available until a later final checkpoint |
| Own `CoinProof`/state bundles | unchanged custody data | owner/replicas retain them |

This is a meaningful reduction from “all proofs + all records + all state forever” to “current state + compact authenticated indexes + per-coin custody witnesses + a bounded tail.” It is not zero DA and not constant total storage.

---

## 8. Failure and adversarial test matrix

The design is not ready for a cryptographic go/no-go until an executable model or conformance harness covers:

| Case | Required invariant |
|---|---|
| valid first batch served only to half the nodes | all conforming nodes eventually select one root or halt identically |
| earlier DA-pending batch appears after a later batch | deterministic rewind/replay/terminal-state result |
| locator never resolves | bounded, identical protocol result; no observer-local fork |
| two valid batches race on one `prev_root` | Bitcoin-order winner is unique under the objective admission rule |
| checkpointer omits an earlier candidate | verifier rejects the checkpoint |
| checkpointer proves a valid non-canonical branch | verifier rejects the checkpoint |
| checkpoint/snapshot withheld | old checkpoint recovery path is specified; no false availability claim |
| snapshot truncated or has duplicate/missing keys | root/completeness verification rejects it |
| latest checkpoint proof lost | rebuild succeeds from a defined prior durable checkpoint and retained tail |
| checkpoint near a reorg | finality lag prevents folding unstable admissions |
| recipient offline across several checkpoints | portable witness still permits receive/fold |
| historical `anchors_root` presented to fresh node | MMR index produces a verifiable consistency proof |
| mixed software versions | activation/version rules prevent divergent admission |

Formal properties should extend the existing per-node accumulator model rather than assume uniform bundle availability.

---

## 9. Implementation sequence

1. Specify and model objective live admission, late bundle arrival, and convergence.
2. Choose the Bitcoin/external-DA trade-off and update the base protocol.
3. Specify `header_digest`, `chain_commit`, activation, finality, and reorg rules byte-for-byte.
4. Specify checkpoint package and canonical snapshot/MMR-index formats.
5. Specify `PortableAnchorWitness_v1` and migration/pruning obligations.
6. Build a recursion spike using real `AggregateBatchProof`s; measure fold time, verification time, proof size, snapshot size, MMR-index size, and rebuild bandwidth.
7. Run the adversarial test matrix and independent cryptographic review.
8. Only then change `R-D7-3`/`P17` verdicts or permit network-wide pruning.

---

## 10. Verdict

Recursive accumulator checkpoints are a promising way to compress historical verification and remove the need to retain every old aggregate proof. They preserve constant-size checkpoint verification and require no trusted setup.

They do **not**, in the current zkCoins v1 protocol, prove a unique canonical history under selective DA; a snapshot is not withholding-proof; and existing coin/anchors witnesses are insufficient for unconditional BatchBundle deletion. The proposal should proceed as a research spike only after objective live admission is designed. Until all pruning gates pass, the honest claim is:

> Checkpoints can substantially reduce historical verification and storage, but they shift and restructure — rather than eliminate — zkCoins' long-term data-availability obligations.
