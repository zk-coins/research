# notes/

Working drafts and design notes that build on top of the upstream Shielded CSV / zkCoins research. These are exploratory documents, not finalized specifications.

## Contents

| Document | Purpose |
|---|---|
| [l2-protocol-design.md](l2-protocol-design.md) | General L2 protocol design: issuer-bonded SSS, two-tier finality (6-conf hard / SSS-sig soft), multi-token, force-exit. The foundation that everything else builds on. |
| [sss-trust-model.md](sss-trust-model.md) | Comprehensive specification of the Single Signer Server (SSS) trust model: validity hierarchy, four receiver trust profiles, exhaustive worked examples for every conflict scenario, edge cases, interaction with bonds. The authoritative reference for finality and conflict resolution. |
| [threat-model.md](threat-model.md) | Systematic adversarial analysis of every fraud and attack scenario — per actor (sender, receiver, SSS, miner), multi-actor conspiracies, bond/slashing attacks, force-exit attacks, economic, privacy, network, and cross-asset attacks. Each with prerequisites, effect, mitigation, and residual risk. Summary matrix at the end. |
| [perpetuals-design.md](perpetuals-design.md) | Perpetual futures venue built on the issuer-bonded L2 model. Targets the Hyperliquid use case with privacy and Bitcoin settlement, without an own chain or token. Depends on `l2-protocol-design.md`. |

## Relationship to top-level documents

These drafts assume the reader is familiar with the parent repo's primary sources:

- [../PROTOCOL_STATUS.md](../PROTOCOL_STATUS.md) — what's implemented in the current ZeroSync-derived codebase vs. what the Shielded CSV paper specifies. Important for understanding which parts of the L2 design are buildable today vs. require protocol-level work first.
- [../bitvm-bridge-research.md](../bitvm-bridge-research.md) — BitVM2 bridge feasibility for Shielded CSV. Directly relevant to:
  - `l2-protocol-design.md` §6.2 (Wrapped Bitcoin variants)
  - `perpetuals-design.md` §13 Q2 (collateral bridging — "Bridging to external collateral")
- [../shieldedcsv-paper.pdf](../shieldedcsv-paper.pdf) — the original protocol paper (Nick, Eagen, Linus 2025).
- [../primary-sources/](../primary-sources/) — archived blog posts, mailing list discussions, the Robin Linus 2023 zkCoins gist.

## Status

All drafts in this directory are **internal design exploration**, not project commitments. They exist to:
- Make the architectural trade-offs explicit
- Document why certain attractive-sounding approaches (free attestor choice, off-chain consensus shortcuts) do not work
- Provide a concrete reference for discussions about what to build and what to skip

Honest framing in the drafts:
- "Trustless" is qualified as *economically trustless* via bonds, not mathematical
- Performance targets are realistic (hundreds to low thousands of TPS), not Hyperliquid-scale
- Marketing language that does not survive critical review is explicitly flagged

## Open invitations for review

Specific points where outside review would be valuable:

1. **Bond economics** (`l2-protocol-design.md` §5, §10 Q1): right size of operator bond relative to throughput and attack value.
2. **Slashing distribution mechanism** (`l2-protocol-design.md` §5.3): pro-rata vs. first-come for multi-victim equivocation events; concrete Taproot script construction.
3. **Cross-asset atomic operations** (`l2-protocol-design.md` §6.3, §10 Q5): standard for HTLC-style swaps is clear; the harder case is simultaneous updates across multiple SSS-controlled assets (e.g. perpetuals settlement touching both margin and position assets).
4. **Force-exit UX** (`l2-protocol-design.md` §7): how does a holder maintain the proofs needed to force-exit without continuous SSS interaction?
5. **Encrypted mempool for the perps venue** (`perpetuals-design.md` §5.3): operator front-running mitigation via threshold-decrypted order submission. Latency/security trade-off needs modeling.
