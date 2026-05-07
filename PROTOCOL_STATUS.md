# Protocol Implementation Status

Current state of the zkCoins implementation compared to the [Shielded CSV paper](https://eprint.iacr.org/2025/068) (Nick, Eagen, Linus — January 2025).

Last updated: 2026-05-07

## Goal

Build a private Bitcoin wallet based on Shielded CSV: transactions require only 64 bytes on-chain (a nullifier), coin proofs are constant-size ZK proofs exchanged directly between sender and receiver, and the transaction history is hidden from everyone except the participants.

## Architecture

```
Paper (Sept 2024)
  ShieldedCSV/ShieldedCSV ─── Protocol reference (Rust, crypto = stubs)
  BitVM/zkCoins ──────────── Plonky2 recursive proof PoC (historical)
  ZeroSync/ZKCoins ────────── First functional prototype (SP1 zkVM)
    └─ zk-coins/server ────── Our fork (production deployment)
```

Our server is derived from the ZeroSync prototype. We kept the SP1 proving system and added production infrastructure (multi-environment deployment, encrypted wallet, auth flows, CI/CD). The protocol itself is unchanged from ZeroSync.

## What the Paper Specifies

A Shielded CSV payment works as follows:

1. **Sender** creates a transaction spending coins and updating their account state
2. **Sender** signs the state transition with a Schnorr signature using sign-to-contract (binding the transaction hash to the signature)
3. **Publisher** collects nullifiers from multiple senders, half-aggregates the signatures (NISSHAC), and posts one `AggregateNullifier` (~64 bytes per account) to Bitcoin
4. **Receiver** gets the coin + ZK proof directly from the sender (off-chain)
5. **Receiver** verifies the proof and checks that the nullifier is on-chain

Key properties: privacy (proof reveals nothing beyond validity), constant-size proofs (independent of transaction history), permissionless publishing, trustless fees, and reorg protection.

## Implementation Status

### Fully Implemented

| Component | Paper Reference | Our Implementation |
|---|---|---|
| Sparse Merkle Tree | Section 3.5 — Non-membership proofs for spent coins | `program/src/merkle/sparse_merkle_tree.rs` — 256-bit depth, inclusion + non-inclusion proofs |
| Merkle Mountain Range | Section 3.6 — Append-only accumulator | `program/src/merkle/merkle_mountain_range.rs` — History tracking with proof generation |
| ZK Proof Generation | Section 3.7 — Proof-Carrying Data | SP1 zkVM circuit in `program/src/main.rs` — Recursive proof verification |
| Balance Conservation | Section 4.2 — Sum of inputs = sum of outputs | Enforced in circuit: `AccountState::send_coins()` checks balance |
| Coin Ancestry Chain | Section 4.2 — Recursive proof of valid history | Previous proof verified inside circuit before state transition |
| Bitcoin Inscription Publishing | Section 2 — Data posted via Taproot | `publisher.rs` — Commit/reveal pattern, txid prefix `4242` |
| Blockchain Scanning | Section 2 — Monitor chain for nullifiers | `scanner.rs` — Polls Esplora every 30s, filters by prefix |
| Account State Transitions | Section 4.2 — AcctState updates | `account_server.rs` — Create account, send coins, receive coins |
| Schnorr Commitments | Section 4.1 — Sign state transitions | `shared/src/commitment.rs` — Schnorr sign + verify |

### Partially Implemented

| Component | Paper Reference | Gap |
|---|---|---|
| Account Model | Section 2 — `(id, balance, nullifier_pk, spent_accum_value)` | Missing `nullifier_pk` and `spent_accum_value` fields. Current: `(owner, balance, public_key)` |
| Compliance Predicate | Section 4.2 — 8 verification rules | 5 of 8 rules implemented (balance, ancestry, coin proofs, non-membership, state hash). Missing: nullifier advance, sign-to-contract verification, conditional NAV |
| MMR Purpose | Section 3.6 — Accumulates nullifiers | Currently accumulates commitment history roots instead of nullifiers |

### Not Implemented

| Component | Paper Reference | Description |
|---|---|---|
| **Nullifier System** | Section 2 | The core privacy mechanism. No `(PublicKey, Signature)` nullifier pairs published. Current system uses inscription content, not cryptographic nullifiers. Double-spend prevention relies on server trust, not on-chain nullifiers. |
| **NISSHAC** | Section 4.1 | Non-Interactive Schnorr Signature Half-Aggregation with Commitments. Allows aggregating n signatures into ~64 bytes. Current: individual Schnorr signatures, no aggregation. |
| **Sign-to-Contract** | Section 4.1 | Embeds transaction hash in signature nonce: `R = R' + H(R', tx_hash)G`. Binds nullifier to specific transaction cryptographically. Current: message signed directly. |
| **AggregateNullifier Format** | Section 2 | `(public_keys[], aggregate_signature, fee_account_commitment)`. Current: raw `Commitment` struct in inscription. |
| **Scanner Signature Verification** | Section 4.2 | Verify aggregate signatures when scanning blocks. Current: only txid prefix matching (`4242`), no cryptographic verification. |
| **Nullifier PK Rotation** | Section 4.2 | Each transaction generates a fresh nullifier public key. First key deterministically derived from account ID. Prevents parallel state chains. |
| **Global Nullifier Accumulator** | Section 3.6 | ToS-accumulator (MMR) tracking all published nullifiers. Enables membership proofs for coin validity and prefix proofs for finalization. |
| **Conditional NAV** | Section 4.2 | Conditional nullifier accumulator value protects against blockchain reorganizations. Transaction becomes no-op if reorg invalidates dependencies. |
| **Trustless Publisher Fees** | Section 4.2 | Three-predicate system: `payment_init` / `payment_finalize` / `payment_finalize_fee`. Publisher is guaranteed fee payment for being first to post nullifier. |
| **Publisher Batching** | Section 2 | Aggregate multiple users' nullifiers into single blockchain transaction via half-aggregation. |
| **Shared Accounts** | Section 5.1 | t-of-n ownership via MuSig2 or FROST threshold signatures. |
| **Time-locked Transactions** | Appendix A.1.1 | Locktime field in nullifier, enforced by accumulator. |
| **Atomic Swaps** | Appendix A.1.2 | PTLC-based swaps between Shielded CSV and Bitcoin. |
| **Multi-Asset Support** | Appendix A.1.3 | Asset type field in CoinEssence, per-asset balance tracking. |

## What We Added Over ZeroSync

Infrastructure and UX improvements (not protocol changes):

| Feature | Description |
|---|---|
| Multi-environment deployment | `IS_MAINNET`, `NETWORK_NAME`, `PUBLISHER_KEY` env vars. DEV on Mutinynet, PRD on Mainnet. |
| Encrypted wallet storage | IndexedDB + AES-GCM (replaces plaintext localStorage) |
| Seed phrase + Passkey auth | BIP-39 mnemonic and WebAuthn PRF-based key derivation |
| Signed send requests | Schnorr-signed API calls from frontend |
| CI/CD pipeline | ARM64 Docker builds, auto-deploy via SSH + Cloudflare Tunnel |
| Atomic state persistence | `atomic_write()` prevents corruption on crash |
| Mutex poison recovery | `lock_or_recover()` prevents cascade failures |
| Network correctness | `Network::Signet` for Mutinynet (was `Network::Testnet`) |
| Publisher key from env | Panics on mainnet with default test key |

## Upstream References

| Source | What It Provides |
|---|---|
| [ShieldedCSV/ShieldedCSV](https://github.com/ShieldedCSV/ShieldedCSV) | Complete protocol logic for everything missing (NISSHAC, AggregateNullifier, Compliance Predicates, Conditional NAV, Fees). Crypto primitives are stubs — need real implementations. |
| [ZeroSync/ZKCoins](https://github.com/ZeroSync/ZKCoins) | Our primary upstream. Working SP1 proofs, Bitcoin inscriptions, SMT + MMR. Same gaps as our fork. |

## Implementation Roadmap

Ordered by dependency chain:

### Phase 1: Nullifier Foundation
1. Extend `AccountState` with `nullifier_pk` and `spent_accum_value`
2. Implement nullifier PK rotation (fresh key per transaction, first key = account ID)
3. Repurpose or add second MMR as global nullifier accumulator

### Phase 2: Signature Cryptography
4. Implement sign-to-contract in Schnorr signatures
5. Implement Schnorr half-aggregation (NISSHAC)
6. Define `AggregateNullifier` format and publishing

### Phase 3: Verification
7. Scanner: verify aggregate signatures (not just prefix matching)
8. Extend compliance predicate: nullifier advance + sign-to-contract verification in ZK circuit

### Phase 4: Protocol Completion
9. Conditional NAV (blockchain reorg protection)
10. Trustless publisher fees (three-predicate payment flow)
11. Publisher batching (aggregate multiple nullifiers per TX)

### Phase 5: Extensions
12. Shared accounts (t-of-n, MuSig2/FROST)
13. Time-locked transactions
14. Atomic swaps (PTLC)
15. Multi-asset support
