# Perpetual Futures on zkCoins L2 — Design Notes

> Draft | 2026-05-11
>
> A perpetual futures exchange built on the issuer-bonded L2 protocol. Targets the Hyperliquid use case (high-volume on-chain perps) with privacy and Bitcoin settlement, without an own chain or token.

This document depends on:
- [`l2-protocol-design.md`](l2-protocol-design.md) — protocol primitives (assets, SSS, bond/slashing, force-exit)
- [`sss-trust-model.md`](sss-trust-model.md) — validity hierarchy and receiver trust profiles
- [`threat-model.md`](threat-model.md) — adversarial scenarios applicable to venue users

---

## TL;DR

- A perpetuals venue is itself an asset under the L2 protocol. Its issuer = SSS = exchange operator.
- The operator bonds Bitcoin on-chain. Their bond economically backs sub-second soft-finality for trades.
- Positions, orders, balances, PnL: all ZK-shielded. Only the operator sees order flow during their epoch.
- Liquidations are SSS-triggered with ZK proof of trigger conditions. No mempool race.
- Trade execution: sub-second. Bitcoin anchoring: every 1–10 min for hard finality.
- No protocol token. No own chain. No federation hidden behind "decentralized" wording.

---

## 1. What This Is — And What It Is Not

**This is**: a venue operated by a known, bonded operator with cryptographic guarantees that:
- Order matching is honest (ZK-provable correctness)
- Positions are unforgeable (ZK-proven state transitions)
- Liquidations are mechanical (ZK-proven trigger conditions)
- Equivocation is economically punished (slashing of operator bond)
- Funds are non-custodial (margin held in script paths, not by operator)

**This is not**:
- A blockchain or own consensus layer
- A token launch
- A "trustless" system in the maximalist sense — it is **economically trustless** via bonds
- Hyperliquid in volume (the architecture caps at hundreds to low thousands of TPS, not 100k+)

The right comparison is **a dark-pool perpetuals venue with cryptographic auditability**. Not the largest by volume, but the most defensible on privacy and integrity guarantees.

---

## 2. The Venue as an L2 Asset

The exchange itself is registered as an L2 asset:

```
GenesisCommitment {
    asset_id:       VenuePerps
    deployer_pubkey: operator_pubkey
    bond_outpoint:  <bond UTXO>
    metadata: {
        name: "Venue Perpetuals",
        privacy_mode: Shielded,
        venue_type: "perpetual_futures",
        supported_markets: ["BTC-PERP", "ETH-PERP", ...],
        max_leverage_per_market: {...},
        funding_interval_seconds: 3600,
        liquidation_threshold_bps: { initial: 1000, maintenance: 500 }
    },
    issuer_signature: ...
}
```

The operator's role is multi-faceted:
- Issuer (defines the venue)
- SSS (signs state transitions)
- Sequencer (orders incoming trades)
- Matcher (runs the order book matching engine)
- Liquidator (triggers ZK-proven liquidations)
- Funding rate calculator (signs hourly funding settlements)

All these roles are bound to one Schnorr key — the operator's. Any equivocation across any role uses the same slashing primitive.

---

## 3. Account Model

### 3.1 Trader account state

Each trader has a per-venue account:

```
TraderAccount {
    account_id:    H(trader_master_pubkey || venue_asset_id)
    current_pubkey: rotating BIP32 child key
    margin_balance: amount (shielded, in venue's collateral asset)
    positions: [
        Position {
            market_id,
            size,           // signed, positive = long
            entry_price,    // average entry
            margin_alloc,   // isolated margin alloc (if isolated)
            last_funding_index
        },
        ...
    ],
    open_orders_root: SMT root of open orders
    realized_pnl: amount
}
```

The account state transitions on every order placement, fill, liquidation, funding rate application, or withdrawal. Each transition is ZK-proven.

### 3.2 Margin currency

The venue declares one or more accepted collateral assets at genesis. Typically: a wrapped BTC variant (e.g. `zkBTC` from a reputable issuer) and/or a stablecoin. Cross-asset margin requires the venue to interface with multiple L2 SSSs — or to operate the collateral asset itself.

For MVP, assume **single-asset collateral** (one wrapped BTC variant). Cross-asset margin is a phase-2 feature.

---

## 4. Order Flow

### 4.1 Order submission

```
1. Trader signs LimitOrder { market, side, size, price, time_in_force }
   with current rotating key
2. Sends to operator via signed gRPC / WebSocket
3. Operator validates:
   - signature against trader's known pubkey
   - margin sufficiency via ZK-provable margin check
   - order conforms to market rules
4. Operator inserts into order book
5. Operator responds: { order_id, soft-attestation }
```

Order acceptance latency target: 10–50 ms.

### 4.2 Matching

The operator runs a standard CLOB. When orders match:

```
1. Operator computes new TraderAccount states for both sides:
   - maker: position update, margin reservation update
   - taker: position update, margin reservation update
2. Operator generates a Trade Batch Proof (SP1):
   - validates: signatures, margin sufficiency at fill time,
     correct price (within order specs), correct position math
3. Operator issues SoftFinalityAttestations to both parties
4. Trade is added to pending_batch for periodic Bitcoin anchoring
```

Match-to-attestation latency target: 50–200 ms.

### 4.3 Funding rate

At each funding interval (e.g., hourly):

```
1. Operator computes funding rate from market imbalance:
   funding_rate = clamp(premium_index, -0.5%, +0.5%) over interval
2. For each open position, computes funding payment
3. Updates all relevant TraderAccount margin balances
4. Generates a single Funding Batch Proof covering all updates
5. Inscribes the proof on Bitcoin
```

The funding calculation is deterministic from the trade stream — anyone with venue data can independently verify the rate. The operator's signature simply attests to having applied it correctly.

### 4.4 Liquidations

When a position's margin ratio falls below the maintenance threshold:

```
1. Operator detects liquidation condition (via mark price + position state)
2. Operator generates Liquidation Proof:
   - Position is real and outstanding
   - Mark price (from oracle, see §6) makes maintenance margin insufficient
   - Liquidation price computed by formula
3. Operator forcibly closes position, applies penalty, distributes to:
   - Counterparty (liquidator keeper bounty)
   - Insurance fund
4. Updates trader's margin balance
5. Attestation issued
```

Liquidations are **operator-triggered** but **fully ZK-proven**. The trader cannot dispute a valid liquidation. The operator cannot fake one.

If the operator fails to liquidate a falling position (negligence), the insurance fund absorbs the loss. If the insurance fund is depleted, the operator's bond is partially slashable for ADL (auto-deleveraging) cases — see §7.

---

## 5. Privacy Properties

### 5.1 What is hidden

| Datum | Visible to Operator | Visible to Counterparty | Visible Publicly |
|---|:-:|:-:|:-:|
| Order price/size | yes | only if filled | no |
| Position size | yes | no | no |
| Position direction (long/short) | yes | no | no |
| Margin balance | yes | no | no |
| Realized PnL | yes | no | no |
| Open interest per trader | yes | no | no |
| Liquidation events on your account | yes | yes (counterparty: maybe) | no |
| Aggregate market stats | yes | yes | yes (published) |
| Funding rate | yes | yes | yes |

### 5.2 Public market data

The venue publishes for auditability:
- Aggregate open interest per market
- Aggregate volume per epoch
- Funding rate history
- Mark price history
- Insurance fund balance (auditable via ZK proof against the bond)
- Cumulative fees collected

This is what regulators and market participants need to assess the venue's health. It doesn't reveal individual positions.

### 5.3 The operator-trust residual

The operator sees everything in real time. This is the irreducible trust point — same as any centralized exchange seeing order flow during the matching phase. Mitigations:

**Encrypted mempool for orders**: orders submitted under a threshold-decryption scheme that only opens after the matching epoch closes. Prevents operator front-running. Cost: latency increase to ~100–500 ms (decryption round).

**Sequencer rotation across multiple operators**: harder than it sounds — see §10 for why this re-introduces cross-SSS fork problems unless carefully designed. Probably defer to v2.

For v1, operator front-running is mitigated by **reputation + bond**: a documented case of operator front-running is a slashing condition (specifically defined in the bond contract). This is enforced by a cryptographically authenticated operator order-log snapshot that the operator cannot alter post-hoc.

---

## 6. Oracle Design

Perpetuals require external price data for:
- Mark price (for PnL and liquidations)
- Index price (for funding rate calculation)

### 6.1 Operator-signed oracle

The operator signs a sequence of price commitments:

```
PriceCommitment {
    market_id, timestamp, price, source_set,
    operator_signature
}
```

The operator commits to a price feed with these properties:
- Multiple sources (e.g., median of Coinbase, Binance, Kraken APIs)
- Published every N seconds, monotonic timestamps
- Past values cannot be retroactively changed (each signs the previous hash)

### 6.2 Oracle slashing

The operator equivocates the oracle by signing two different prices for the same timestamp. This is **detectable** if any third party records the public price feed and compares. The same slashing primitive applies (two sigs over different messages from the same key).

For a deeper guarantee: **third-party oracle audit nodes** that independently sample the same external sources and publish their own commitments. If the operator's prices systematically diverge from the audit nodes, the operator's bond can be slashed via a specific oracle-deviation clause in the bond contract.

This is **not a perfect oracle**. A motivated, well-financed attacker who controls upstream exchanges could feed the operator (and all audit nodes) bad data. This is the same vulnerability every DEX has. Mitigation: use multiple independent upstream sources, slash the operator if they ignore divergence.

### 6.3 Alternative: outsourced oracle

The venue can declare it uses Chainlink / Pyth / DIA as authoritative. The operator becomes an oracle relayer — they sign attestations that they read the upstream oracle correctly. Same slashing model.

Trade-off: outsources oracle trust to a third party. Their incentives and security guarantees become the venue's. Simpler integration, weaker security story.

---

## 7. Insurance Fund and Bond Sizing

### 7.1 Insurance fund

Funded from:
- Liquidation penalties (e.g., 50% of liquidation fee goes to insurance)
- A portion of trading fees (e.g., 5%)

Used to:
- Cover bad-debt positions (negative-margin positions that couldn't be closed cleanly)
- Backstop oracle disputes
- Pay slashing claims that exceed operator bond

The fund is held in a separate L2 asset, fully auditable. Its balance is publicly known.

### 7.2 Operator bond

The operator bond size must cover:

```
bond_required ≥ max_burst_exposure + safety_factor × typical_daily_volume
```

Where `max_burst_exposure` is the maximum value the operator could fraudulently invalidate in a single equivocation event.

For a venue doing $100M daily volume with $10M peak hourly exposure: realistic bond sizing is $10M–$30M (10–30 BTC at current prices). This is substantial but achievable for a regulated operator.

Bond can be:
- Single Bitcoin UTXO held by operator
- Multisig with insurance underwriter (operator + 2-of-3 from auditor consortium)
- Pool of UTXOs aggregated for capacity

### 7.3 ADL (Auto-Deleveraging)

If a counterparty cannot be liquidated cleanly because margin is exhausted AND the insurance fund is depleted, the system enters ADL:

1. Identify the highest-leverage profitable counterparties on the opposite side.
2. Forcibly close those positions at the mark price.
3. Use the closed PnL to make the unliquidatable position whole.

This is standard CEX practice. The ZK proof ensures ADL targets are selected per a deterministic rule (highest leverage × highest PnL first), not arbitrary operator choice.

If ADL still doesn't suffice (extreme tail event), the operator bond is partially slashed via a specific bond contract clause. This is the final backstop and very rarely activated.

---

## 8. Force-Exit for Traders

A trader can force-exit their account state without operator cooperation:

```
ForceExitClaim {
    trader_account_proof:  ZK proof of last known balance + open positions
    last_anchor:           Bitcoin block height of last operator batch
    challenge_period:      72 blocks (~12 hours) for operator to refute
}
```

The challenge period is **shorter than the L2 protocol default** of 144 blocks ([`l2-protocol-design.md`](l2-protocol-design.md) §7.1). The asset-specific shortening is justified by perpetuals' time-sensitive nature: an unresponsive operator on a perp venue causes ongoing PnL drift, so the protocol biases toward faster trader recovery. The trade-off is reduced operator response time for legitimate refutations; if this proves too tight in practice, the parameter can be revisited.

If operator doesn't refute within the challenge period:
- Open positions are closed at last anchored mark price
- Margin balance + position closed PnL is paid out from operator's collateral pool on Bitcoin
- Trader exits cleanly

This is the trader's protection against:
- Operator going offline indefinitely
- Operator refusing withdrawal requests
- Operator censoring specific traders

The trade-off: the trader gets the last anchored price, not the current price. For active traders this is acceptable (recent anchor is ≤10 minutes old).

---

## 9. Performance Targets

| Metric | Target | Hyperliquid (Reference) |
|---|---|---|
| Order ack latency | 10–50 ms | ~50 ms |
| Match-to-attestation latency | 50–200 ms | ~200 ms |
| Trades per second | 500–2000 | 10,000+ |
| Markets supported | 10–30 | 200+ |
| Bitcoin hard-finality | 6 confs (~60 min) | ~10 min on own L1 |
| Concurrent users | 10,000 | 100,000+ |

The honest assessment: this venue cannot match Hyperliquid on raw throughput. Bitcoin DA and SP1 proof generation are the bottlenecks.

**Where this venue wins**:
- Privacy (Hyperliquid is fully transparent)
- Settlement is on Bitcoin, not on a custom L1
- No own token required for participation
- Cryptographic integrity proofs at every step
- Regulatory clarity (operator is a real, identifiable, regulated entity)

The TAM is the segment of derivatives traders who value the above. Realistic TAM: $100M–$1B daily volume, not $10–20B. Profitable at this scale, but a different positioning.

---

## 10. What v1 Skips

To ship a credible v1 in 12–18 months, defer:

| Feature | Rationale |
|---|---|
| Decentralized sequencer | Re-opens the cross-SSS fork problem from L2 design. Single operator + bond is sufficient for v1. |
| Cross-margin | Single-position-isolated-margin is far simpler and acceptable for v1. |
| Cross-asset margin | Single collateral asset, no multi-asset balancing. |
| Encrypted mempool | Operator front-running mitigated by reputation + slashing v1. Encrypted mempool is a v2 hardening. |
| Mobile app | Web-only v1. |
| Spot trading | Perps-only v1. Spot can be added as separate L2 asset later. |
| Options | Defer entirely. Different risk model. |

What v1 must have:
- Working ZK margin/liquidation circuits
- Functional operator bond with slashing tested
- Force-exit fully implemented and tested on testnet
- Insurance fund accounting
- Honest privacy claims (operator-trusted, audit-loggable)

---

## 11. Roadmap

### Phase 0 — Research (3 months)
- SP1 circuit complexity analysis for margin + liquidation
- Bond script formal verification
- Force-exit dispute mechanism design
- Oracle audit-node protocol

### Phase 1 — MVP on Bitcoin Signet (6 months)
- Single market: BTC-PERP
- Isolated margin only, up to 10x leverage
- Single operator, bonded on Signet (test coins)
- Web wallet (WASM)
- Manual liquidation triggers initially, automated via keeper pattern by end of phase

### Phase 2 — Mainnet Beta (6 months)
- 3-5 markets
- Up to 20x leverage
- Mainnet operator bond (real BTC)
- Keeper network for liquidations
- Market maker API (signed order submission)
- Encrypted mempool for orders (sequencer-blind order matching)

### Phase 3 — Production (12 months+)
- 20+ markets
- Cross-margin (within single collateral asset)
- Up to 40x leverage on liquid markets
- GPU proof generation (Succinct Network integration)
- Operator federation option (M-of-N operators for institutional users)
- Sub-account architecture for trading teams

---

## 12. Honest Positioning

Marketing language that is **true** for this design:

- "Perpetual futures with private positions, settled on Bitcoin"
- "Cryptographically auditable order matching and liquidations"
- "No own token. No own chain. Bitcoin-native settlement."
- "Operator-bonded — equivocation is on-chain slashable"
- "Force-exit guaranteed — traders cannot be censored or trapped"

Marketing language that **must not be used** (it would invite ridicule from sophisticated reviewers):

- "Trustless" without qualification (it is economically trustless, not mathematically)
- "Decentralized" while having a single operator
- "No coordinator" while having an SSS/sequencer
- "Hyperliquid killer" (volume math doesn't support it)
- "Sub-second Bitcoin finality" (Bitcoin finality is 60 min; soft finality is sub-second)

Use the differentiator that is real: **privacy + Bitcoin settlement + cryptographic integrity**, sold at a price point and to a customer segment that values these specifically.

---

## 13. Open Questions

1. **Maker rebate and fee schedule**: standard pattern is positive rebates for makers, fees for takers. How does this interact with ZK privacy (rebate flows are visible aggregates but not per-trader)?

2. **Bridging to external collateral**: practical mechanism for users to deposit Bitcoin into the venue's collateral pool. Federated peg vs. BitVM2 vs. trusted custodian? Affects the trust story significantly. See [`../bitvm-bridge-research.md`](../bitvm-bridge-research.md) for the BitVM2 bridge analysis — concretely the Citrea Clementine and Bitlayer YBTC reference implementations are the closest existing prior art.

3. **Cross-venue arbitrage**: how does this venue interact with Hyperliquid, Binance, etc., for arbitrageurs? Likely they connect manually via account funding; no on-chain bridge needed.

4. **Insurance fund top-up dynamics**: simulation needed for various market stress scenarios.

5. **Regulatory positioning**: operator is necessarily identifiable. Likely needs explicit regulatory wrapper (e.g., VARA license in UAE, or a Swiss DLT-trading-facility license). Not a research question, but a strategic prerequisite.

6. **Cold start liquidity**: how does the venue bootstrap order book depth without market-maker incentives? Probably needs a managed liquidity-bootstrap phase with operator-funded MM positions.

7. **Mark price manipulation defense**: if mark price comes from external exchanges, what prevents an attacker from manipulating the external price briefly to trigger liquidations on this venue? Standard defenses (price band, time-averaged, multi-source) — but exact parameters need stress-testing.

---

## 14. Why This Is Worth Building

The core competitive position:

> Hyperliquid is winning by being fastest and most transparent.
> This venue wins by being the **most private and most auditable** alternative.
> Both can coexist. They serve different customer segments.

The traders who value privacy:
- Institutional desks (positions are trade secrets)
- Market makers (inventory exposure is competitive intelligence)
- Whale traders (avoid being hunted)
- Treasury management (hedging without revealing strategy)

These customers are sophisticated. They will look at the architecture and ask the questions raised in earlier conversation analysis: where's the trust, what's slashable, what's force-exitable. This design has honest answers to all those questions.

That's the differentiator that can be defended. Not "Hyperliquid but better at everything" — that doesn't fly. But "Hyperliquid for those who genuinely cannot afford the transparency" — that's a real market.
