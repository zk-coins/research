# BitVM Bridge Research for Shielded CSV

Last updated: 2026-05-07

## Executive Summary

A trustless bridge between Shielded CSV and Bitcoin L1 via BitVM is **feasible with existing technology**. All building blocks exist separately — they just haven't been assembled for Shielded CSV yet.

## BitVM Evolution

### BitVM1 (October 2023)
- Two-party only, fixed verifiers at compile time
- Up to 70 transactions for dispute, weeks to resolve
- ~1 GB on-chain footprint

### BitVM2 (August 2024)
- **Permissionless verification** — anyone can challenge
- 2-round dispute: max 3 transactions (Claim → Challenge → Disprove)
- **1-of-n honesty model** at setup, permissionless at runtime
- 2-4 MB per chunk (fits in a Bitcoin block)
- **Mainnet proven**: June 3, 2025 — first full unhappy-path, 42 blocks (7.5 hours), cost: 14.9M sats (~$16,000)

### BitVM3 (July 2025)
- Garbled circuits with RSA for 1000x cost reduction
- **WITHDRAWN** — security break discovered

### Glock (January 2026, Alpen Labs / Liam Eagen)
- Designated-verifier SNARKs instead of RSA
- 430-550x more efficient than BitVM2
- In development

### Argo (January 2026, Ideal Group / Robin Linus, Liam Eagen, Ying Tong Lai)
- 2000x more efficient than BitVM3
- "Industry-leading garbled circuits for off-chain SNARK verification"
- In development

## SNARK Verification on Bitcoin L1

BitVM2 can verify **Groth16 SNARK proofs** on Bitcoin:
- Groth16: ~22,000 field multiplications over bn254, script ~1 GB split into 4 MB chunks
- FFlonk: ~14,000 field multiplications + hash function
- PLONK: Supported but less efficient (800-900 byte proofs vs 300 bytes)
- STARKs: Wrapped into Groth16 first, then verified

**Verification is optimistic** — proof is only checked on-chain during disputes.

## SP1 Proof Path (zkCoins → Bitcoin)

zkCoins uses SP1 (Succinct) for proof generation. The verification path:

1. SP1 generates proof (internally a STARK)
2. SP1 wraps STARK into **Groth16 proof** (recursive compression)
3. BitVM2 verifies the Groth16 proof on Bitcoin

SP1 has native BLAKE3 support making Bitcoin verification 5x cheaper than SHA256.
Succinct confirms this is usable today. Alpen Labs, Babylon, Nubit, ZeroSync build on it.

## Live BitVM Bridges (May 2026)

| Project | Status | Technology | Token |
|---------|--------|-----------|-------|
| Bitlayer | Mainnet since Jul 2025 | BitVM2 | YBTC (1:1 BTC) |
| Citrea | Mainnet since Jan 2026 | BitVM2 (Clementine) | cBTC |
| BOB | Testnet | BitVM3/Glock | native BTC |
| Alpen (Strata) | Development | Glock | — |

## Robin Linus Connection

**Critical insight:** Robin Linus authored both protocols:
- **BitVM** (2023) — Compute anything on Bitcoin
- **zkCoins** (2023) — Client-side validation with ZK proofs
- **Shielded CSV** (2025, with Jonas Nick + Liam Eagen) — Privacy protocol on Bitcoin
- **Argo** (2026, with Liam Eagen + Ying Tong Lai) — 2000x cheaper verification

Shielded CSV was designed with BitVM bridging in mind. He has described Shielded CSV as "the most interesting thing you can do with BitVM."

## Bridge Mechanism for zkCoins

### Peg-In (BTC → zkCoins)
1. User locks BTC in BitVM2 contract (Taproot address, two spend paths)
2. Shielded CSV side verifies the Bitcoin deposit (light client)
3. Shielded coins are minted to user's zkCoins account

### Peg-Out (zkCoins → BTC)
1. User burns shielded coins
2. Operator fronts BTC to user immediately
3. Operator claims reimbursement via BitVM2 contract
4. On fraud: anyone can challenge (on-chain SNARK verification)

### Trust Model
- Setup: 1-of-N (one honest signer suffices)
- Runtime: permissionless (anyone can challenge)
- Worst case: funds burned, not stolen
- One honest challenger keeps the system secure

## Costs

| Scenario | BitVM2 (today) | Glock/Argo (projected) |
|----------|---------------|----------------------|
| Happy path | ~50,000 sats (~$53) | ~100-1,600 sats |
| Dispute | ~14.9M sats (~$16,000) | ~35,000-100,000 sats |

## Speed

- Peg-in: 6+ Bitcoin confirmations (~1 hour)
- Peg-out happy path: Instant (operator fronts)
- Dispute resolution: < 8 hours (proven on mainnet)
- Challenge period: ~1.5 days (Citrea reference)

## Structural Limitations

- **Fixed deposit sizes** (0.1, 0.5, 1, 10 BTC — not suitable for small amounts)
- **Operator capital**: ~200% of bridged BTC as total system collateral
- **Fee vulnerability**: Malicious provers can exhaust challenger collateral during fee spikes
- **Complexity**: Pre-signed transaction graphs, timelocks, edge cases — hard to audit

## What's Missing for zkCoins

1. **Shielded CSV ↔ BitVM2 integration spec** — no concrete design document
2. **Light client for Bitcoin deposits** — CSV side needs to verify on-chain BTC locks
3. **Operator network** — who fronts BTC for withdrawals?
4. **Proof compression** — Shielded CSV proofs must fit in BitVM2 dispute chunks
5. **Challenge economics** — incentive model for watchtowers/challengers

## Implementation Strategy

### Phase 1: Trusted Setup (Launch)
- N-of-M federation multisig
- Simple mint/burn against locked BTC
- Verifiable reserves on-chain
- Ship fast, limit deposit amounts

### Phase 2: BitVM Bridge
- Build on existing Citrea/Bitlayer reference implementations
- Use SP1 → Groth16 wrapping for on-chain verification
- Implement operator network with overcollateralization
- Permissionless challenging

### Phase 3: Glock/Argo Optimization
- Migrate to Glock/Argo when production-ready
- 430-2000x cost reduction makes bridge viable for smaller amounts
- Same trust model, dramatically lower fees

## Key References

- [BitVM2 Paper](https://bitvm.org/bitvm2)
- [BitVM Bridge Whitepaper](https://bitvm.org/bitvm_bridge.pdf)
- [SNARK Verifier in Bitcoin Script](https://bitvm.org/snark.html)
- [SP1 Is Bitcoin Ready](https://blog.succinct.xyz/bitcoin-sp1/) — Succinct
- [Citrea Clementine Bridge](https://docs.citrea.xyz/essentials/clementine-trust-minimized-bitcoin-bridge)
- [Clementine Whitepaper](https://citrea.xyz/clementine_whitepaper.pdf)
- [Glock: Verification on Bitcoin](https://www.alpenlabs.io/blog/glock-verification-on-bitcoin) — Alpen Labs
- [Ideal Group](https://ideal.group/) — Robin Linus, Liam Eagen, Ying Tong Lai
- [Shielded CSV Paper](https://eprint.iacr.org/2025/068)
- [Bitlayer BitVM Bridge Launch](https://www.coindesk.com/business/2025/07/16/bitlayer-s-bitvm-bridge-debuts-its-mainnet-offers-trust-minimized-bitcoin-defi)
- [BOB BitVM Bridge Testnet](https://www.coindesk.com/tech/2025/07/02/bitcoin-defi-project-bob-launches-bitvm-bridge-testnet)
- [BitVM3 Security Break](https://github.com/BitVM/BitVM) — README note
- [Bitcoin L2s in 2026: Reality Check](https://www.hozk.io/articles/bitcoin-l2s-in-2026-a-reality-check)
