# Trustless BTC↔zkCoins Bridge Research

Last updated: 2026-06-06

## Decision

**The zkBTC bridge will be built on Glock — no BitVM2 intermediate, no federation V0.** (User decision, 2026-06-06.)

Rationale:
- Glock's fraud-proof reduces to **one 64-byte Schnorr signature** vs BitVM2's multi-MB dispute chunks — structurally a match for the Variant-2 constant-per-batch `BatchInscription` model that just landed in [zk-coins/docs#40](https://github.com/zk-coins/docs/pull/40).
- 430-550× on-chain efficiency claim vs BitVM2 means the per-peg-in/out economics work for retail amounts, not just whole-BTC-class deposits.
- Liam Eagen (Glock author) is also the Shielded CSV co-author; Argo (Robin Linus + Eagen + Lai) is the parallel garbling research line. We share the same author cluster, maximising design-compatibility likelihood.
- Citrea cBTC and Bitlayer YBTC have demonstrated that BitVM2 works in production, but Strata's full migration BitVM2→Glock is a strong vote of confidence from the Alpen team in their own next-generation construction. Building on BitVM2 now would mean migrating in 12-24 months anyway.

What this excludes:
- No federation-multisig V0 as a stepping stone. Trust-branding for zkBTC is "as trustless as Bitcoin allows" — a federation V0 would dilute that.
- No BitVM2 reference implementation; no operator/watchtower work against BitVM2.
- This is **not v1** of zkCoins. Variant-2 spec is just shipped; zkBTC is v3+ territory after Glock matures.

What is still open:
- **Glock mainnet date is unknown** as of June 2026. Alpen is "finalising Glock"; Starknet × Alpen is the first announced production adopter, targeting mainnet "in 2026". Realistic range: 12-24 months from now.
- **No public audit of Glock yet.** Paper is reviewable ([ePrint 2025/1485](https://eprint.iacr.org/2025/1485), Aug 2025); external audit results not published.
- **Plonky2 → DV-Pari conversion path** for the zkCoins proof system is not yet demonstrated. Needs direct conversation with Eagen / Linus before serious implementation.

## Executive Summary

A trustless bridge between Shielded CSV and Bitcoin L1 via Glock is **feasible with existing technology**. All building blocks exist separately — they just haven't been assembled for Shielded CSV yet.

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

### Glock (August 2025, Alpen Labs / Liam Eagen) — OUR CHOSEN PATH
- Garbled Circuits + Designated-Verifier SNARK (DV-Pari, "currently smallest known SNARK")
- Binary elliptic curves for synergies with the GC scheme
- Cut-and-Choose + Verifiable Secret Sharing + Adaptor Signatures for malicious security
- **Fraud proof = single 64-byte Schnorr signature** (vs multi-MB BitVM2 chunks)
- 430-550× on-chain efficiency vs BitVM2; Glock25 variant claims 550×
- Paper: [ePrint 2025/1485](https://eprint.iacr.org/2025/1485) (local: [glock-paper.pdf](glock-paper.pdf))
- bitcoindev announcement: [groups.google.com/g/bitcoindev/c/g_-Tfmjz0pw](https://groups.google.com/g/bitcoindev/c/g_-Tfmjz0pw)
- Alpen blog: [alpenlabs.io/blog/glock-verification-on-bitcoin](https://www.alpenlabs.io/blog/glock-verification-on-bitcoin)
- **Status June 2026:** No public mainnet date. Starknet × Alpen partnership announced 15.10.2025 as first production adopter, targeting "in 2026" — realistic range 12-24 months. Strata bridge migrated from BitVM2 to Glock.

### Argo (January 2026, Ideal Group / Robin Linus, Liam Eagen, Ying Tong Lai)
- 2000× more efficient than BitVM3 (the withdrawn one), industry-leading garbled circuits for off-chain SNARK verification
- Parallel research line to Glock, same author cluster
- Paper: [ePrint 2026/049](https://eprint.iacr.org/2026/049) (local: [argo-mac-paper.pdf](argo-mac-paper.pdf))
- **Status June 2026:** Earlier-stage research than Glock; Glock is the practical near-term target. Argo may eventually supersede or augment Glock.

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

## Implementation Strategy — Glock-direct

(Earlier 3-phase plan with a Federation V0 and BitVM2 intermediate has been **discarded** — see the Decision section at the top. The path below replaces it.)

### Phase 0 — Watch & monitor (now → Glock mainnet)
- Track Alpen Labs Glock progress (paper revisions, testnet, audit publication)
- Track Starknet × Alpen bridge as the reference deployment
- Track Argo (Linus's parallel direction) — may supersede Glock or run alongside
- No zkCoins-side bridge code in this phase

### Phase 1 — Plonky2 → DV-Pari conversion (when Glock mainnet ~6 months out)
- Direct conversation with Eagen and Linus to confirm the proof-system conversion is sound
- Prototype the conversion against the zkCoins compliance predicate ([Proofs §2](https://github.com/zk-coins/docs/blob/develop/docs/specification.md#2--proofs--state-transitions))
- Document the bridge inscription format alongside the existing constant-per-batch `BatchInscription` (likely a new inscription type, fixed-size, distinct marker)

### Phase 2 — zkBTC asset on zkCoins (Glock mainnet ready)
- New `IssuanceTerms_v2_glock_bridged` schema (the v1 issuance terms in the current spec are single-issuer; v2 binds to a Glock contract address rather than a `creator_pubkey`)
- Peg-in proof circuit: SPV-proof of Bitcoin lock + Glock garble verification
- Peg-out: burn-and-redeem against Glock-locked BTC
- Operator network + watchtower economics — model directly from Alpen Strata reference implementation, not from BitVM2 Clementine
- Trust model: garbler/evaluator + Cut-and-Choose, worst case = funds-burned-not-stolen (same family as BitVM2 but with Glock's tighter on-chain dispute footprint)

## Key References

### Local archives (this repo)
- [glock-paper.pdf](glock-paper.pdf) — Glock: Garbled Locks for Bitcoin (Eagen, Aug 2025) · also at [ePrint 2025/1485](https://eprint.iacr.org/2025/1485)
- [argo-mac-paper.pdf](argo-mac-paper.pdf) — Argo MAC: Garbling with Elliptic Curve MACs (Eagen, Lai, Jan 2026) · also at [ePrint 2026/049](https://eprint.iacr.org/2026/049)
- [bitvm2-bridge-paper.pdf](bitvm2-bridge-paper.pdf) — BitVM2: Bridging Bitcoin to Second Layers · also at [bitvm.org/bitvm_bridge.pdf](https://bitvm.org/bitvm_bridge.pdf)
- [bitvm-paper.pdf](bitvm-paper.pdf) — BitVM: Quasi-Turing Complete Computation on Bitcoin (Aumayr et al.) · also at [ePrint 2024/1995](https://eprint.iacr.org/2024/1995)
- [shieldedcsv-paper.pdf](shieldedcsv-paper.pdf) — Shielded CSV (Nick, Eagen, Linus) · also at [ePrint 2025/068](https://eprint.iacr.org/2025/068)

### External
- [Glock: Verification on Bitcoin — Alpen Labs blog](https://www.alpenlabs.io/blog/glock-verification-on-bitcoin)
- [Glock bitcoindev announcement](https://groups.google.com/g/bitcoindev/c/g_-Tfmjz0pw)
- [Starknet × Alpen Glock Bridge announcement](https://www.starknet.io/blog/starknet-alpen-bitcoin-glock/)
- [BitVM2 Paper](https://bitvm.org/bitvm2)
- [SNARK Verifier in Bitcoin Script](https://bitvm.org/snark.html)
- [SP1 Is Bitcoin Ready — Succinct](https://blog.succinct.xyz/bitcoin-sp1/)
- [Citrea Clementine Bridge](https://docs.citrea.xyz/essentials/clementine-trust-minimized-bitcoin-bridge)
- [Clementine Whitepaper](https://citrea.xyz/clementine_whitepaper.pdf)
- [Ideal Group](https://ideal.group/) — Robin Linus, Liam Eagen, Ying Tong Lai
- [Bitlayer BitVM Bridge Launch](https://www.coindesk.com/business/2025/07/16/bitlayer-s-bitvm-bridge-debuts-its-mainnet-offers-trust-minimized-bitcoin-defi)
- [BOB BitVM Bridge Testnet](https://www.coindesk.com/tech/2025/07/02/bitcoin-defi-project-bob-launches-bitvm-bridge-testnet)
- [BitVM3 Security Break](https://github.com/BitVM/BitVM) — README note
- [Bitcoin L2s in 2026: Reality Check](https://www.hozk.io/articles/bitcoin-l2s-in-2026-a-reality-check)
