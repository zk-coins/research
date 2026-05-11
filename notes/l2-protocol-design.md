# zkCoins L2 — Issuer-Bonded Protocol Design

> Draft | 2026-05-11
>
> A Bitcoin Layer 2 for arbitrary issued tokens (NFTs, memecoins, wrapped BTC, stablecoins) with private state, full Bitcoin finality after 6 confirmations, and economically-secured sub-second soft finality via the issuer.

---

## TL;DR

- Anyone can deploy a token on Bitcoin via a single inscription: the **Genesis Commitment**.
- The deployer's key is permanently bound to the token as its sole **Verifier**.
- All state transitions are ZK-proven and recorded as nullifiers on Bitcoin.
- **Hard finality**: 6 Bitcoin block confirmations (standard Bitcoin security).
- **Soft finality**: instant, via Verifier signature, backed by an on-chain bond with cryptographic slashing on equivocation.
- No new chain. No global consensus. No token gating. Just Bitcoin + ZK.

---

## 1. Motivation

We accept three constraints established by prior analysis:

1. Sub-confirmation finality on Bitcoin cannot be reliably achieved by off-chain attestation alone (mining bribery defeats it).
2. Distributed attestor schemes with free per-transaction choice fork the network state.
3. The only robust paths are (a) wait for 6 confirmations, or (b) introduce on-chain economic security that punishes equivocation.

Path (b) is the basis of this design. The novel insight: **the token issuer is the natural single source of authoritative ordering for that token, because they have unique economic interest in their own asset's integrity.**

---

## 2. Core Insight: Issuer = Verifier

When a user deploys a new asset, they post a **Genesis Commitment** to Bitcoin:

```
GenesisCommitment {
    asset_id:       blake3(deployer_pubkey || nonce || token_metadata),
    deployer_pubkey: secp256k1 X-only pubkey,
    bond_outpoint:   Bitcoin UTXO holding the verifier bond,
    metadata: {
        name, symbol, decimals, supply_cap,
        token_type: { Fungible | NFT | SemiFungible },
        privacy_mode: { Shielded | Transparent | Hybrid }
    },
    issuer_signature: schnorr_sig over the above
}
```

The genesis commitment establishes two facts simultaneously:

- The asset exists, with the deployer holding sole issuance rights.
- The deployer's pubkey is the **only authorized Verifier** for state transitions of this asset.

There is no separate registration step. There is no permission needed. Anyone with a Bitcoin output and the willingness to bond can issue.

### Why this resolves the multi-verifier fork problem

In the earlier discussion we hit a wall: free per-receiver verifier choice forks the network state. The fix here is structural:

- Each asset has exactly one Verifier (its issuer).
- All transactions on an asset must be verifier-signed to be considered for soft-finality.
- Receivers don't choose verifiers per transaction — they choose whether they trust the **issuer of the asset they are receiving**.

If a receiver doesn't trust the issuer of `MemeCoinXYZ`, they simply don't accept payments in that token. Trust is per-asset, not per-transaction.

This also matches the natural economic reality: nobody accepts a stablecoin without trusting the issuer's solvency. The protocol just makes this trust relationship explicit and cryptographically bounded.

---

## 3. Architecture

### 3.1 Components

```
┌─────────────────────────────────────────────────────────┐
│ Holder Wallet (BIP32 + ZK-Account per asset)            │
│   - Holds shielded state for each asset owned           │
│   - Signs transfers with current account key            │
│   - Can verify any incoming proof independently         │
└─────────────────────┬───────────────────────────────────┘
                      │ signed transfer request
                      ▼
┌─────────────────────────────────────────────────────────┐
│ Verifier (one per asset = issuer)                       │
│   - Sequences transactions for its asset                │
│   - Generates / verifies SP1 ZK proofs                  │
│   - Holds and updates the asset's commitment tree       │
│   - Signs soft-finality attestation                     │
│   - Posts batched nullifiers to Bitcoin                 │
└─────────────────────┬───────────────────────────────────┘
                      │ batched inscription
                      ▼
┌─────────────────────────────────────────────────────────┐
│ Bitcoin L1                                              │
│   - Genesis inscriptions (asset existence)              │
│   - Nullifier inscriptions (state transitions)          │
│   - Bond UTXOs with slashing scripts                    │
│   - Force-exit paths for holders                        │
└─────────────────────────────────────────────────────────┘
```

### 3.2 State per asset

Each asset has an independent state tree. The verifier maintains:

```
AssetState {
    asset_id,
    commitment_history_root:  SMT root of all valid commitments
    nullifier_set_root:        SMT root of spent nullifiers
    supply_root:               total minted / burned tracker (for fungibles)
    pending_batch:             list of accepted transitions awaiting inscription
    last_anchor_height:        Bitcoin block where most recent batch confirmed
}
```

The verifier is **stateless from the protocol's perspective in one important sense**: anyone can reconstruct `AssetState` deterministically from Bitcoin history alone. The verifier is a convenience and a soft-finality oracle, not a custodian of the asset's truth.

### 3.3 Transaction flow

A holder Alice transferring 0.1 units of asset `X` to Bob:

```
1. Alice's wallet:
   - Constructs new account state for Alice (balance -= 0.1)
   - Constructs OutCoin for Bob (amount=0.1, recipient=bob_addr)
   - Generates SP1 proof:
       * Previous account state valid (recursive proof verify)
       * Balance arithmetic correct
       * Schnorr signature with rotated key
   - Sends to verifier X: { proof, new_state_hash, nullifier, out_coin_for_bob }

2. Verifier X:
   - Verifies SP1 proof
   - Checks nullifier not already in nullifier_set_root
   - Checks no conflicting commitment for Alice's current pubkey
   - Issues SoftFinalityAttestation: schnorr_sig over (asset_id, nullifier, block_height_promise)
   - Adds to pending_batch
   - Returns: { attestation, batch_id, expected_inscription_height }

3. Wallet → Bob (off-chain):
   - { coin_data, proof, attestation, inclusion_proofs }

4. Bob's wallet verifies:
   - SP1 proof valid ✓
   - Verifier signature valid against asset's Genesis pubkey ✓
   - Nullifier not yet inscribed (still pending) — accepted as soft-final
   - OR: nullifier already inscribed + 6 confirmations — accepted as hard-final

5. Verifier publishes batch:
   - Inscription contains: batch_root, ZK proof of batch validity,
     list of nullifier hashes (one per transition in batch)
   - Batched commit-tx + reveal-tx via Taproot inscription
```

Throughput is limited by:
- Verifier compute (proof generation), realistic ~100–1000 TPS per verifier
- Bitcoin inscription throughput for batch anchoring (one batch every 1–10 minutes)

---

## 4. Finality Model

Two finality levels, both economically/cryptographically grounded:

### 4.1 Soft Finality — Verifier-Attested

A transaction is **soft-final** when:
- Verifier signature over the transaction exists
- Verifier's bond is sufficient to cover the transaction value

**Security argument**: the verifier cannot equivocate (sign two conflicting transitions of Alice's account) without producing a cryptographic slashing proof — two Schnorr signatures over different messages under the same key, fully verifiable on Bitcoin via Taproot script.

**Tradeoff**: latency milliseconds. Risk capped by bond size, not by mathematical guarantee.

### 4.2 Hard Finality — Bitcoin Confirmation

A transaction is **hard-final** when:
- Its nullifier is inscribed on Bitcoin in a block with ≥ 6 confirmations
- The inscribing batch's ZK proof is valid
- No conflicting earlier inscription exists for the same Alice pubkey

This is identical to standard Bitcoin security. The protocol inherits Bitcoin's finality, no more, no less.

### 4.3 Recovery from soft-final failures

If a soft-final transaction is later contradicted by hard-final state (e.g. miner bribery successfully reorders the inscription stream against the verifier's attestation), the receiver's recourse is:

1. Submit slashing proof to Bitcoin: shows verifier-signed transaction + conflicting canonical Bitcoin state.
2. Bond payout to victim per the bond contract's distribution rules.

The verifier's bond serves as economic insurance against any failure of soft-finality.

---

## 5. Bond and Slashing

### 5.1 Bond construction

Verifier bond is a Taproot UTXO with two spending paths:

```
Path A — Normal withdrawal (Verifier voluntary close):
    Conditions:
    - Verifier signature
    - Timelock: 90 days from last attestation involving this bond
    - Purpose: allows verifier to retire an asset cleanly

Path B — Slashing (Equivocation proof):
    Conditions:
    - Schnorr signature 1 by verifier over message m1
    - Schnorr signature 2 by verifier over message m2
    - m1 ≠ m2
    - Both reference the same asset_id and the same Alice pubkey
    - Validator script verifies: same key, different message ⇒ equivocation
    - Output: bond paid to claim address(es) per distribution rules
```

The slashing script is implementable in standard Bitcoin Taproot — no new opcodes needed. The Schnorr signature comparison is the standard verification primitive.

### 5.2 Bond sizing

The bond must satisfy:

```
bond_size > max(over any rolling window W):
    sum of soft-final transaction values that could be invalidated
    if the verifier equivocates
```

Practically, this means:
- Per-transaction soft-final cap: `bond_size / safety_factor`
- Verifier publishes their bond status (current balance, pending claims) so wallets can compute exposure
- Wallets refuse soft-final acceptance if the value exceeds the per-tx cap

For low-velocity assets (NFTs, small memecoins), a 1 BTC bond covers thousands of transactions. For high-velocity assets (stablecoins, perpetuals collateral), the bond must scale to the realistic burst exposure.

### 5.3 Multi-victim slashing

When equivocation harms multiple receivers simultaneously, the bond must be distributed fairly. Approaches:

**Pro-rata claim window**: First slashing proof submitted on-chain opens a claim window (e.g., 144 blocks ≈ 1 day). All affected receivers can register claims by submitting verifier-signed proofs of their unfulfilled transactions. After the window, the bond is distributed pro-rata.

Trade-offs:
- Pro-rata is fair but complex (multi-step claim flow).
- First-come-first-serve is simpler but encourages racing.

Recommendation: pro-rata for stablecoins / high-value assets, first-come for low-stakes assets where verifier equivocation is unlikely to be coordinated.

### 5.4 Bond top-up and rotation

The verifier can:
- **Top up** by adding new bond UTXOs (no protocol change, additional UTXOs increase capacity)
- **Rotate** by spending the existing bond to a new bond UTXO (preserves continuity via a continuation proof)

Bond drainage by repeated micro-slashing must be detected and the verifier paused. Wallets that observe ongoing slashing claims should require additional confirmations or refuse soft-finality entirely.

---

## 6. Multi-Token Support

The protocol scales naturally to arbitrary tokens because each asset has an isolated state tree and verifier.

### 6.1 Token types

| Type | Use Case | Specifics |
|---|---|---|
| **Fungible** | memecoins, stablecoins, wrapped BTC | balance arithmetic in proof |
| **NFT (1:1)** | unique digital assets | each unit has unique identifier in proof |
| **SemiFungible** | tickets, editions of N | fixed supply, individually identifiable |

### 6.2 Wrapped Bitcoin variants

Especially relevant: a Bitcoin-backed wrapped token (call it `zkBTC`) is just another asset under this protocol. The issuer commits to a custodial or BitVM-based peg. The protocol does not prescribe the peg mechanism — that's the issuer's responsibility.

This means: there can be multiple competing wrapped-BTC variants on the same L2, each from a different issuer with different trust assumptions. Holders pick the one whose bond and reputation they accept.

For the trustless peg mechanism specifically, see [`../bitvm-bridge-research.md`](../bitvm-bridge-research.md). BitVM2 bridges (live: Bitlayer YBTC, Citrea cBTC) are the natural construction. Trust model: 1-of-N at setup, permissionless challenging at runtime. Worst case is funds-burned, not funds-stolen.

### 6.3 Cross-asset transactions

A swap between two assets (e.g. zkBTC ↔ stablecoin) requires both verifiers to coordinate. Two natural approaches:

**Atomic swap via HTLC analog**: standard cross-chain swap construction, using ZK-hashlocks for privacy. Each verifier signs only their asset's leg.

**Cross-asset venue**: a separate verifier operates a swap venue (third asset issuance: the venue's LP shares). All swaps go through that venue, which itself bonds. This is the building block for DEX-style trading.

The perpetuals design (separate doc) builds on the cross-asset venue pattern.

### 6.4 Privacy modes

The issuer chooses the asset's privacy mode at genesis:

- **Shielded**: amounts, ownership, history all hidden. Verifier sees state, no one else. Standard zkCoins privacy.
- **Transparent**: balances and transfers public. Useful for treasury tokens, audit-requiring assets.
- **Hybrid**: amounts hidden, transaction graph visible (allows compliance hooks without full revelation).

These are configured once at genesis and cannot be changed for an existing asset.

---

## 7. Force-Exit and Liveness

A core property of any L2 claim is: **what happens if the verifier disappears?**

### 7.1 Force-exit mechanism

A holder can unilaterally exit an asset back to Bitcoin (or to a separate verifier, if the asset has a cross-verifier escape) without the original verifier's cooperation.

```
ForceExitClaim {
    holder_account_proof:  ZK proof that holder owns state X in asset Y
    last_known_anchor:     Bitcoin block height of last verifier batch
    challenge_period:      e.g., 144 blocks (1 day) for verifier to refute
}
```

Process:
1. Holder posts ForceExitClaim as Bitcoin inscription.
2. Verifier has `challenge_period` blocks to refute by showing either:
   - A later valid state for the holder
   - That the holder's claim is invalid (already spent)
3. If no refutation: claim is accepted, holder can spend their position.

### 7.2 Verifier offline scenarios

If the verifier is offline:
- New transactions cannot get soft-finality attestations.
- Holders can still verify each other's hard-final transactions by reading Bitcoin directly.
- Force-exit is always available, capped only by the challenge_period.

If the verifier is permanently dead:
- All holders force-exit within one challenge period.
- The asset is effectively wound down.

This makes the protocol resilient to verifier failure: the worst-case outcome is loss of soft-finality, not loss of funds.

### 7.3 Verifier transfer

The verifier role can be voluntarily transferred via a Bitcoin inscription signed by the current verifier. This allows:
- Sale of an asset's verifier role
- Migration to a federated verifier (M-of-N multisig as the verifier key)
- Emergency handoff if the verifier wants to retire

The asset's state continues uninterrupted; only the attestation key changes.

---

## 8. Privacy Properties

### 8.1 What is hidden

For a Shielded-mode asset:

| Datum | Visible to Verifier | Visible to Counterparties | Visible Publicly |
|---|:-:|:-:|:-:|
| Transfer amount | yes | only own side | no |
| Sender identity | rotating pubkey | no | no |
| Receiver identity | yes | yes (own side) | no |
| Account balance | yes | no | no |
| Total supply | yes | yes (verifier publishes) | yes |
| Transaction count | yes | no | yes (nullifier count) |
| Transaction graph | yes | no | no |

### 8.2 What is exposed

- Existence of transactions (each is one nullifier on chain).
- Approximate transaction rate (visible from inscription rate).
- The asset's total supply (must be auditable).
- The verifier's identity (it's the issuer, public from genesis).

### 8.3 Privacy from the verifier

This is the residual trust point. The verifier sees everything for accounts under its asset. Mitigations:

- **Blind-signed attestations** (research): receiver gets verifier sig without verifier learning the transfer details. Cryptographically possible, not trivial.
- **Multiple verifiers per asset class** (federation): no single verifier sees all transactions of a given user. Re-introduces the cross-verifier coordination problem.
- **Asset segmentation**: a user can spread holdings across multiple assets with different verifiers, fragmenting the per-verifier view.

For most use cases, accepting that the verifier knows your activity is comparable to accepting that your bank knows your activity. The key win is that **nobody else** does.

---

## 9. Comparison to Existing Approaches

| Property | zkCoins L2 (this design) | RGB | Taproot Assets | Stacks | Liquid |
|---|---|---|---|---|---|
| Bitcoin-anchored | ✓ | ✓ | ✓ | partial | partial |
| ZK privacy | ✓ | partial | ✗ | ✗ | ✗ |
| Sub-second soft finality | ✓ (bonded) | ✗ | ✗ | ✗ | ✓ (federated) |
| Hard finality | 6 BTC confs | 6 BTC confs | 6 BTC confs | own consensus | federation |
| No own token required | ✓ | ✓ | ✓ | ✗ (STX) | ✗ (federation key) |
| Issuer-controlled | ✓ | ✓ | ✓ | n/a | n/a |
| Force-exit | ✓ | partial | partial | ✗ | partial |
| Multi-asset native | ✓ | ✓ | ✓ | ✓ | ✓ |

The unique combination is: **ZK privacy + sub-second soft finality + 6-conf hard finality + no own chain or token.**

---

## 10. Open Questions

1. **Bond sizing economics**: what's the right bond-to-throughput ratio for different asset classes? Needs modeling under various attack scenarios (single equivocation, burst equivocation, sophisticated combined mining-bribery + equivocation).

2. **Slashing distribution**: pro-rata vs. first-come, exact challenge window, treatment of partial bonds. Needs formal spec for the Taproot script construction.

3. **Force-exit UX**: how does a holder build a ForceExitClaim without the verifier's data? Requires the holder to keep their own state proofs continuously up to date. Wallet UX challenge.

4. **Verifier rotation atomicity**: ensuring no transactions are lost or duplicated during a verifier key handover. Probably needs a coordinated handoff inscription pattern.

5. **Cross-asset atomic operations**: standard for HTLC-style swaps. Open: standard for more complex multi-asset transactions (e.g., perpetuals settlement requires simultaneous updates to margin asset + position asset).

6. **Blind attestation**: cryptographic construction that lets the verifier attest without seeing transaction content. Research direction.

7. **DA for verifier batches**: currently the verifier publishes the full batch data inscribed. For high-volume assets this may exceed inscription size limits. Need batched-batch aggregation or off-chain DA with on-chain hashes only.

---

## 11. Next Steps

Prerequisite reading: [`../PROTOCOL_STATUS.md`](../PROTOCOL_STATUS.md) — this design assumes the underlying Shielded CSV layer is fully implemented. The current codebase is missing the nullifier system, NISSHAC half-aggregation, sign-to-contract, and several other paper-specified primitives. The L2 design here is forward-looking; it cannot be deployed in production until those gaps are closed.

1. **Formalize the slashing script** in Bitcoin Script with Taproot. Write test cases for honest withdrawal and slashing paths.

2. **Implement reference verifier** as an extension of the existing ZeroSync ZKCoins server: add asset metadata to genesis, multi-asset state trees, attestation signing endpoint, bond status reporting.

3. **Implement reference wallet** support: per-asset account model, attestation verification, soft-finality UX, force-exit construction.

4. **Bond contract on Bitcoin testnet**: deploy a parameterized bond UTXO, test slashing flow end-to-end.

5. **Cross-asset venue spec**: separate document, foundational for perpetuals and DEX use cases.

6. **Formal security analysis**: economic model of bond sizing, simulation of various attack profiles, comparison to Lightning channel security model.

---

## Appendix A — Glossary

| Term | Meaning |
|---|---|
| **Asset** | A token issued under this protocol (NFT, fungible, semi-fungible) |
| **Genesis Commitment** | The initial Bitcoin inscription that creates an asset |
| **Verifier** | The single key authorized to attest state transitions for an asset (equals issuer at genesis) |
| **Attestation** | Verifier's Schnorr signature on a transaction, used for soft-finality |
| **Bond** | Bitcoin UTXO held by the verifier, slashable on equivocation |
| **Soft finality** | Acceptance based on verifier attestation + bond coverage |
| **Hard finality** | Acceptance based on 6 Bitcoin confirmations of the relevant nullifier |
| **Force-exit** | Unilateral withdrawal by a holder without verifier cooperation |
| **Nullifier** | The 64-byte on-chain commitment that proves a transition occurred |

---

## Appendix B — Relationship to Shielded CSV

This design extends the Shielded CSV protocol (ePrint 2025/068) in three ways:

1. **Asset model**: Shielded CSV is single-asset by default. This design generalizes to multi-asset with per-asset state trees.

2. **Verifier role**: Shielded CSV has no formal verifier — each node validates independently. This design introduces a privileged verifier per asset for soft-finality, while preserving the independent-validation property for hard-finality.

3. **Economic security layer**: Shielded CSV has no notion of bonds or slashing. This design adds them as a separate Bitcoin contract, orthogonal to the core CSV protocol.

The core ZK machinery (SP1 proofs, Schnorr aggregation, nullifier accumulators) is unchanged.
