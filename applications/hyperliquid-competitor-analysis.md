# zkCoins als Hyperliquid-Konkurrent: Vollständige Analyse

> Analyse erstellt am 2026-05-08 · letzte Konsistenz-Aktualisierung 2026-05-17
> Basierend auf: Deep-Dive aller zkCoins Repos (app, server, docs, research, marketing)
>
> **Product Vision (aktuelle Brand-Architektur A — zkCoins ist alles, kein separates "zkPerps"-Sub-Brand):** [zkCoins Exchange Vision](https://github.com/zk-coins/marketing/blob/develop/strategy/exchange/vision.md) · Live unter [zkcoins.exchange](https://zkcoins.exchange)
>
> Die in diesem Dokument durchgespielten Architektur-Varianten (insbesondere Variante C als "Favoritenlösung") behandeln zkPerps als eigenes Vertikal-Brand. Die finale Entscheidung war stattdessen Brand A: "zkCoins Exchange" als ein Produkt der zkCoins-Familie, gleichrangig zu Wallet (zkcoins.app), Explorer (zkcoins.space), Whitepaper (zkcoins.com) und Brand-Hub (zkcoins.info). Die technische Analyse unten bleibt unverändert gültig — nur das Naming und die Brand-Architektur sind anders entschieden.

---

## 1. Ausgangslage

### 1.1 Was ist Hyperliquid?

Hyperliquid ist eine dezentrale Perpetual-Futures-Börse auf einer eigenen L1-Blockchain:

- **Architektur**: Custom L1 mit HyperBFT-Konsens (~16 Validatoren, permissioned)
- **Performance**: ~200ms Block-Time, ~100k Orders/Sekunde
- **Produkt**: 183 Krypto-Perpetuals, USDC-marginiert, bis 40x Hebel
- **Orderbook**: Vollständiges Central Limit Order Book (CLOB) on-chain
- **HyperEVM**: EVM-kompatible Execution-Umgebung für DeFi-Apps
- **TVL**: Mehrere Milliarden USD
- **Schwächen**:
  - Validator-Set klein und permissioned (nicht wirklich dezentral)
  - Bridge-Sicherheit via Multisig
  - Validator können Positionen manuell schliessen (Jelly-Jelly-Vorfall März 2025)
  - **Null Privatsphäre** — alle Positionen, Liquidationen, PnL öffentlich sichtbar

### 1.2 Was ist zkCoins?

zkCoins implementiert das Shielded CSV-Protokoll (ePrint 2025/068, Nick/Eagen/Linus):

- **Kern**: Client-Side Validation mit rekursiven ZK-Proofs (SP1 zkVM)
- **Privacy**: Beträge, Sender, Empfänger und Transaktionsgraph vollständig verborgen
- **On-Chain**: Nur 64-Byte-Nullifier auf Bitcoin (kein eigener Konsens nötig)
- **Off-Chain**: Coin-Proofs direkt Sender → Empfänger (Peer-to-Peer)
- **Kryptografie**: Schnorr-Signaturen, Sign-to-Contract, Sparse Merkle Trees, MMR
- **Throughput**: ~100 TPS theoretisch (limitiert durch Bitcoin-Blockgrösse)
- **Status**: ~30-40% des Protokolls implementiert (funktionaler Prototyp)
- **Server**: Aktuell zentralisiert, aber architektonisch für Dezentralisierung designed

### 1.3 Kernfrage

**Kann man mit zkCoins-Technologie einen Hyperliquid-Konkurrenten bauen — ohne eigene Blockchain, mit dezentral verteilten Servern?**

---

## 2. Technologische Bausteine von zkCoins

### 2.1 Was zkCoins bereits kann

| Baustein | Status | Relevanz für Exchange |
|----------|--------|----------------------|
| Shielded Accounts (Balance-Tracking) | ✅ Implementiert | Margin-Konten |
| ZK-Proofs für Transfers (SP1 zkVM) | ✅ Implementiert | Settlement-Proofs |
| Schnorr-Signaturen + Key-Rotation | ✅ Implementiert | Order-Signierung |
| Sparse Merkle Tree (Non-Inclusion) | ✅ Implementiert | Double-Spend-Schutz |
| Merkle Mountain Range (History) | ✅ Implementiert | Commitment-History |
| Two-Phase Commit (Send → Commit) | ✅ Implementiert | Trade-Settlement |
| Bitcoin-Inscriptions (Nullifiers) | ✅ Implementiert | Finales Settlement |
| HD-Wallet mit BIP-32/39 | ✅ Implementiert | Wallet-Integration |
| AES-256-GCM verschlüsselter Storage | ✅ Implementiert | Client-Side Security |

### 2.2 Was fehlt und erweitert werden müsste

| Feature | Status | Aufwand |
|---------|--------|---------|
| Nullifier-System (vollständig) | ❌ Nicht implementiert | Hoch |
| NISSHAC Signatur-Aggregation | ❌ Nicht implementiert | Mittel |
| Multi-Asset-Support | ❌ Nicht implementiert | Mittel |
| Atomic Swaps (PTLC) | ❌ Nicht implementiert | Hoch |
| Shared Accounts (MuSig2/FROST) | ❌ Nicht implementiert | Hoch |
| Light Clients | ❌ Nicht implementiert | Hoch |
| Server-Dezentralisierung | ❌ Nicht implementiert | Sehr hoch |
| **Orderbook-Logik** | ❌ Komplett neu | Sehr hoch |
| **Margin-Engine** | ❌ Komplett neu | Sehr hoch |
| **Liquidations-Engine** | ❌ Komplett neu | Sehr hoch |
| **Oracle-System** | ❌ Komplett neu | Hoch |
| **Funding-Rate-Mechanismus** | ❌ Komplett neu | Mittel |

### 2.3 SP1 zkVM als Schlüsselelement

Der SP1 zkVM ist der kritischste Baustein. Er erlaubt es, **beliebigen Rust-Code** in einem ZK-Circuit auszuführen. Das bedeutet:

- Margin-Berechnungen können in ZK verifiziert werden
- Liquidations-Bedingungen können bewiesen werden, ohne Positionen offenzulegen
- Order-Matching kann off-chain passieren und via Proof verifiziert werden
- Account-State-Updates können atomar und privat sein

**Limitation**: Proof-Generierung ist CPU-intensiv. Aktuell:
- `create_account`: Funktioniert auf M3 Ultra
- `update_account`: Überschreitet Memory auf CPU (benötigt GPU oder Succinct Network)
- Latenz: Sekunden bis Minuten pro Proof

---

## 3. Fünf Architektur-Varianten

### Variante A: Privacy Layer über bestehendem Orderbook

```
┌─────────────────────────────────────────────┐
│  Klassisches Orderbook (Matching Engine)     │
│  - Centralized oder verteiltes Matching      │
│  - Sub-millisecond Latenz                    │
└──────────────────┬──────────────────────────┘
                   │ Matched Trades
┌──────────────────▼──────────────────────────┐
│  zkCoins Settlement Layer                    │
│  - ZK-Proofs für Margin-Verification         │
│  - Shielded Account Balances                 │
│  - Nullifiers auf Bitcoin                    │
└──────────────────┬──────────────────────────┘
                   │ 64-byte Nullifiers
┌──────────────────▼──────────────────────────┐
│  Bitcoin Blockchain (Settlement Finality)     │
└─────────────────────────────────────────────┘
```

**Idee**: Orderbook-Matching bleibt schnell und klassisch. Nur das Settlement nutzt zkCoins-Privacy. Positionen und Balances sind shielded, aber das Matching selbst ist transparent für den Matching-Server.

**Vorteile**:
- Höchste Performance (Matching unabhängig von ZK)
- Bewährte Orderbook-Technologie
- Privacy für Endnutzer (Balances, PnL verborgen)
- Bitcoin-Settlement für Finality

**Nachteile**:
- Matching-Server sieht alle Orders (kein vollständiges Privacy)
- Zentralisierungsrisiko beim Matcher
- Zwei separate Systeme zu maintainen
- Nicht wirklich "zkCoins-nativ"

**Bewertung**: ⭐⭐⭐ — Pragmatisch, aber halbherzig. Kein echtes Alleinstellungsmerkmal.

---

### Variante B: Dezentrales Server-Netzwerk mit ZK-Orderbook

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Server 1 │  │ Server 2 │  │ Server 3 │  ... (N Server)
│ (Prover) │  │ (Prover) │  │ (Prover) │
└─────┬────┘  └─────┬────┘  └─────┬────┘
      │             │             │
      └──────┬──────┘──────┬──────┘
             │ BFT Konsens │
      ┌──────▼─────────────▼──────┐
      │  Orderbook State (SMT)     │
      │  - Shielded Orders         │
      │  - Encrypted Matching      │
      │  - ZK-verified Settlements │
      └──────────────┬────────────┘
                     │ Nullifiers
              ┌──────▼──────┐
              │   Bitcoin    │
              └─────────────┘
```

**Idee**: Mehrere zkCoins-Server bilden ein BFT-Netzwerk. Jeder Server hält eine Kopie des Orderbook-States (als Sparse Merkle Tree). Orders werden verschlüsselt eingereicht. Matching passiert via Multi-Party Computation (MPC) oder sequenziell mit ZK-Verifikation.

**Vorteile**:
- Vollständig dezentral (kein Single Point of Failure)
- Privacy auch gegenüber Servern (via MPC)
- Bitcoin-Settlement
- Kein eigener Token nötig

**Nachteile**:
- **Extrem komplex** — MPC für Order-Matching ist ein offenes Forschungsproblem
- **Langsam** — BFT-Konsens + MPC + ZK-Proofs = hohe Latenz (Sekunden)
- Skalierung begrenzt durch langsamsten Server
- MPC-Protokolle für Orderbook-Matching existieren kaum in Produktion

**Bewertung**: ⭐⭐ — Akademisch interessant, praktisch in absehbarer Zeit nicht umsetzbar.

---

### Variante C: zkCoins Perpetual Protocol (Favoritenlösung)

```
┌─────────────────────────────────────────────────────────┐
│                    Client (Browser/WASM)                  │
│  - Wallet (BIP-32, Schnorr)                              │
│  - Position Management (local state)                     │
│  - ZK Proof Generation (SP1 client-side oder delegiert)  │
│  - Order Signing                                         │
└────────────┬──────────────────────────────┬──────────────┘
             │ Signed Orders                │ Commitments
┌────────────▼──────────────────────────────▼──────────────┐
│              Operator Network (N Nodes)                    │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │  Operator 1  │  │  Operator 2  │  │  Operator 3  │     │
│  │  (Sequencer) │  │  (Verifier)  │  │  (Verifier)  │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                 │              │
│         └────────┬────────┘────────┬────────┘              │
│                  │ Rotating Leader │                       │
│  ┌───────────────▼─────────────────▼───────────────────┐  │
│  │            Shared State (Replicated)                  │  │
│  │  - Orderbook (Price-Time Priority)                    │  │
│  │  - Margin Accounts (SMT, shielded balances)           │  │
│  │  - Position Registry (encrypted)                      │  │
│  │  - Oracle Feed (aggregated, signed)                   │  │
│  │  - Funding Rate State                                 │  │
│  └───────────────┬─────────────────────────────────────┘  │
│                  │                                        │
│  ┌───────────────▼─────────────────────────────────────┐  │
│  │            Settlement Engine                          │  │
│  │  - Batch matched trades                               │  │
│  │  - Generate aggregate ZK proofs (SP1)                 │  │
│  │  - Publish nullifiers to Bitcoin                      │  │
│  │  - Liquidation proofs                                 │  │
│  └───────────────┬─────────────────────────────────────┘  │
│                  │                                        │
└──────────────────┼────────────────────────────────────────┘
                   │ Batched Nullifiers (every N seconds)
            ┌──────▼──────┐
            │   Bitcoin    │
            │  (Finality)  │
            └─────────────┘
```

**Idee**: Ein Netzwerk von Operatoren (ähnlich Hyperliquid-Validatoren, aber offener) betreibt eine replizierte State-Machine. Ein rotierender Leader (Sequencer) matched Orders. Alle anderen Operatoren verifizieren via ZK-Proofs. Settlement wird in Batches auf Bitcoin publiziert.

#### Detailliertes Design

**Order Flow**:
1. Client signiert Order mit Schnorr (BIP-32 Key)
2. Order wird an Operator-Netzwerk gesendet
3. Sequencer fügt Order ins Orderbook ein (Price-Time-Priority)
4. Bei Match: Sequencer erstellt Trade-Record
5. Sequencer generiert ZK-Proof: "Trade ist gültig, beide Parteien haben genug Margin"
6. Verifier-Operatoren prüfen den Proof (schnell, O(1))
7. State wird atomar aktualisiert (Margin-Konten, Positionen)
8. Periodisch: Batched Nullifiers auf Bitcoin publishen

**Privacy-Modell**:
| Was | Sichtbar für Sequencer | Sichtbar für Verifier | Sichtbar on-chain |
|-----|----------------------|---------------------|-------------------|
| Order (Preis, Menge) | ✅ Ja (für Matching) | ❌ Nein (nur Proof) | ❌ Nein |
| Position (Size, Entry) | ✅ Ja (für Liquidation) | ❌ Nein (nur Proof) | ❌ Nein |
| Balance / Margin | ✅ Ja (für Validation) | ❌ Nein (nur Proof) | ❌ Nein |
| PnL | ✅ Ja (für Funding) | ❌ Nein | ❌ Nein |
| Trade-Existenz | ✅ Ja | ✅ Ja (Proof) | ✅ Ja (Nullifier) |
| Identität | ❌ Nein (Schnorr-Key) | ❌ Nein | ❌ Nein |

**Sequencer-Rotation**: Round-Robin oder stake-gewichtet. Bei Ausfall übernimmt nächster Operator. State ist repliziert, kein Datenverlust.

**Margin-Engine im SP1 Circuit**:
```
ZK-Circuit verifiziert:
1. account.balance >= initial_margin(position_size, leverage)
2. account.balance + unrealized_pnl >= maintenance_margin
3. oracle_price ist signiert von ≥ 2/3 der Operatoren
4. funding_rate korrekt berechnet aus Long/Short-Imbalance
5. Liquidation nur wenn maintenance_margin unterschritten
```

**Vorteile**:
- **Starke Privacy**: Nur der Sequencer sieht Order-Details, niemand sonst
- **Dezentral**: Operator-Netzwerk mit Rotation, kein Single Point of Failure
- **Bitcoin-Settlement**: Finality ohne eigenen Token
- **Skalierbar**: Sequencer kann schnell matchen, Proofs asynchron
- **Keine Blockchain nötig**: Replizierte State-Machine genügt
- **Erweiterbar**: SP1 zkVM kann beliebige Margin-Logik beweisen
- **zkCoins-nativ**: Baut direkt auf der existierenden Architektur auf

**Nachteile**:
- Sequencer hat temporär Einsicht in Order-Details
- Proof-Generierung ist latenz-bestimmend für Settlement
- Benötigt zuverlässige Oracle-Feeds
- Komplexität der Margin-Engine im ZK-Circuit

**Bewertung**: ⭐⭐⭐⭐⭐ — Realistisch umsetzbar, starkes Alleinstellungsmerkmal, baut auf zkCoins-Stärken auf.

---

### Variante D: Peer-to-Peer Derivatives (Intent-basiert)

```
┌──────────┐         ┌──────────┐
│ Trader A │ ◄─────► │ Trader B │
│ (Long)   │  Intent │ (Short)  │
└────┬─────┘ Matching└────┬─────┘
     │                    │
     │  ZK Proof          │  ZK Proof
     │  (Collateral)      │  (Collateral)
     │                    │
┌────▼────────────────────▼────┐
│   Intent Relay Network        │
│   - Broadcast intents         │
│   - Match Long ↔ Short        │
│   - No custody of funds       │
└──────────────┬───────────────┘
               │ Matched Pairs
┌──────────────▼───────────────┐
│   zkCoins Contract Server     │
│   - Escrow via shielded coins │
│   - Oracle-based settlement   │
│   - ZK-proof of PnL           │
└──────────────┬───────────────┘
               │ Nullifiers
        ┌──────▼──────┐
        │   Bitcoin    │
        └─────────────┘
```

**Idee**: Keine zentrale Börse. Trader broadcasten Intents ("Ich will BTC Long, 10x, 10'000 USDC Margin"). Ein Relay-Netzwerk matched kompatible Intents. Settlement via zkCoins Shielded Coins als Escrow.

**Vorteile**:
- Maximale Dezentralisierung (kein Sequencer)
- Maximale Privacy (Peer-to-Peer)
- Kein Orderbook = kein Front-Running
- Trustless Escrow via ZK-Proofs

**Nachteile**:
- **Keine Liquidität** — ohne Orderbook kein effizienter Preisfindungsmechanismus
- **Langsam** — Intent-Matching ist inherent langsamer als CLOB
- **Slippage** — Kein kontinuierliches Orderbook = schlechte Execution
- **Liquidation** — Wer liquidiert bei P2P? Oracle + automatischer Settlement nötig
- **UX-Katastrophe** — Nutzer müssen auf Gegenpartei warten

**Bewertung**: ⭐⭐ — Philosophisch elegant, praktisch unbrauchbar für aktiven Handel.

---

### Variante E: Shielded AMM (Automated Market Maker) für Perpetuals

```
┌────────────────────────────────────────────┐
│               Shielded AMM Pool             │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   Virtual AMM (vAMM)                │   │
│  │   - x * y = k (constant product)    │   │
│  │   - Kein echtes Asset im Pool       │   │
│  │   - Preis = f(Long OI, Short OI)    │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   Shielded Margin Vault (SMT)       │   │
│  │   - Encrypted positions              │   │
│  │   - ZK-verified margin               │   │
│  │   - Hidden open interest              │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   Liquidation Engine                 │   │
│  │   - ZK-proof: position < maint.     │   │
│  │   - Keeper network (permissionless) │   │
│  │   - Insurance fund (shielded)        │   │
│  └─────────────────────────────────────┘   │
│                                             │
└────────────────────┬───────────────────────┘
                     │ Operated by N Servers
              ┌──────▼──────┐
              │   Bitcoin    │
              └─────────────┘
```

**Idee**: Statt eines Orderbooks nutzen wir einen virtuellen AMM (wie Perpetual Protocol v1). Positionen werden gegen den vAMM eröffnet, nicht gegen eine Gegenpartei. Der gesamte State ist shielded via zkCoins-Technologie.

**Vorteile**:
- **Kein Matching nötig** — AMM ist automatisch
- **Immer Liquidität** — Kein Warten auf Gegenpartei
- **Einfacher zu dezentralisieren** — State-Updates sind deterministisch
- **Privacy** — Open Interest, Positionen, Liquidationen alle verborgen
- **Shielded Insurance Fund** — Niemand sieht den Fund-Stand (verhindert gezielte Angriffe)

**Nachteile**:
- **Slippage** — AMM hat inherent mehr Slippage als CLOB
- **Oracle-Abhängigkeit** — vAMM-Preis muss an Oracle gebunden werden
- **Kapitaleffizienz** — Schlechter als CLOB (kein echtes Orderbook)
- **Manipulation** — vAMM kann mit genug Kapital manipuliert werden
- **Markt hat sich von vAMMs abgewendet** — Perpetual Protocol v2 wechselte zu CLOB

**Bewertung**: ⭐⭐⭐ — Technisch einfacher, aber der Markt bevorzugt CLOBs. Nischenprodukt.

---

## 4. Vergleichsmatrix

| Kriterium | A: Privacy Layer | B: MPC-Orderbook | C: Operator Network | D: P2P Intents | E: Shielded AMM |
|-----------|:---:|:---:|:---:|:---:|:---:|
| **Privacy** | ◐ Teilweise | ● Voll | ◑ Stark | ● Voll | ● Voll |
| **Performance** | ● Hoch | ○ Niedrig | ◑ Mittel-Hoch | ○ Niedrig | ◑ Mittel |
| **Dezentralisierung** | ○ Gering | ● Voll | ◑ Stark | ● Voll | ◑ Stark |
| **Umsetzbarkeit** | ● Einfach | ○ Unrealistisch | ◑ Machbar | ◐ Schwierig | ◑ Machbar |
| **UX / Liquidität** | ● Gut | ◐ OK | ● Gut | ○ Schlecht | ◐ OK |
| **zkCoins-Synergie** | ○ Gering | ◑ Mittel | ● Hoch | ◑ Mittel | ◑ Mittel |
| **Alleinstellung** | ○ Schwach | ◑ Stark | ● Stark | ◑ Stark | ◐ Mittel |
| **Bitcoin-Settlement** | ● Ja | ● Ja | ● Ja | ● Ja | ● Ja |
| **Kein eigener Token** | ● Ja | ● Ja | ● Ja | ● Ja | ● Ja |
| **Gesamt** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |

---

## 5. Deep-Dive: Variante C (Operator Network) — Die optimale Lösung

### 5.1 Warum Variante C?

**Das Killer-Feature ist die Kombination aus:**

1. **Privacy** — Keine öffentlichen Positionen, keine sichtbaren Liquidationen, kein Front-Running
2. **Dezentralisierung** — Operator-Netzwerk statt einzelnem Server
3. **Bitcoin-Settlement** — Kein eigener Token, kein eigener Konsens-Layer
4. **CLOB** — Professionelles Orderbook, nicht AMM
5. **zkCoins-nativ** — Baut direkt auf existierender Infrastruktur auf

**Hyperliquid-Schwächen, die Variante C adressiert:**

| Hyperliquid-Problem | Variante C Lösung |
|---------------------|-------------------|
| Öffentliche Positionen → Gezielte Liquidation | Shielded Positions |
| Front-Running durch Validatoren | ZK-verified Matching, kein Validator sieht Details |
| Manuelles Eingreifen (Jelly-Jelly) | Algorithmische Liquidation via ZK-Proof |
| Permissioned Validator-Set | Offenes Operator-Netzwerk |
| Eigener Token (HYPE) benötigt | Kein Token, Bitcoin-Settlement |
| Bridge-Multisig-Risiko | BitVM2-Bridge (trustless) |

### 5.2 Architektur im Detail

#### Operator-Rollen

```
Operator-Typen:
├── Sequencer (1 aktiv, rotierend)
│   - Empfängt signierte Orders
│   - Führt Orderbook-Matching aus
│   - Generiert Batch-Proofs
│   - Publiziert Nullifiers auf Bitcoin
│
├── Verifier (N-1 Operatoren)
│   - Verifizieren Sequencer-Proofs (O(1) per Proof)
│   - Halten replizierten State
│   - Können bei Sequencer-Ausfall übernehmen
│   - Betreiben Oracle-Feeds
│
└── Keeper (Permissionless)
    - Überwachen Liquidations-Bedingungen
    - Reichen Liquidations-Proofs ein
    - Erhalten Liquidations-Fee
```

#### State-Modell (Erweiterung des zkCoins SMT)

```rust
// Erweitertes Account-Modell für Perpetuals
struct PerpAccount {
    // zkCoins-Basis
    owner: HashDigest,           // SHA256(pubkey)
    balance: u64,                // Free margin (satoshis)
    public_key: Vec<u8>,         // Current BIP-32 key

    // Perpetual-Erweiterungen
    positions: Vec<Position>,    // Offene Positionen
    total_margin_used: u64,      // Gebundene Margin
    unrealized_pnl: i64,         // Laufender PnL
    funding_accumulated: i64,    // Aufgelaufene Funding-Zahlungen
}

struct Position {
    market_id: u16,              // z.B. 0=BTC, 1=ETH
    size: i64,                   // Positiv=Long, Negativ=Short (Satoshis)
    entry_price: u64,            // Einstiegspreis (Fixed-Point)
    leverage: u8,                // Hebel (1-40x)
    liquidation_price: u64,      // Vorberechnet
    last_funding_index: u64,     // Für Funding-Rate-Berechnung
}

struct Market {
    id: u16,
    oracle_price: u64,           // Aktueller Oracle-Preis
    funding_rate: i64,           // Aktuelle Funding Rate
    long_open_interest: u64,     // Gesamt Long OI
    short_open_interest: u64,    // Gesamt Short OI
    insurance_fund: u64,         // Insurance Fund Balance
}
```

#### ZK-Circuit für Trade-Verification

```
SP1 Circuit: verify_trade(inputs) -> ProofData

Inputs:
  - seller_account_state_hash
  - buyer_account_state_hash
  - trade: { market, price, size, leverage }
  - oracle_price (signed by 2/3 operators)

Circuit prüft:
  1. Buyer hat genug freie Margin:
     buyer.balance - buyer.total_margin_used >= size * price / leverage
  2. Seller hat genug freie Margin (analog)
  3. Oracle-Preis ist gültig signiert
  4. Trade-Preis liegt innerhalb von ±1% des Oracle
  5. Leverage ≤ max_leverage für diesen Markt
  6. Neue Position korrekt berechnet
  7. Account-State-Hashes korrekt aktualisiert

Output:
  - new_buyer_state_hash
  - new_seller_state_hash
  - trade_nullifier (64 bytes)
```

#### Liquidations-Circuit

```
SP1 Circuit: verify_liquidation(inputs) -> ProofData

Inputs:
  - account_state_hash
  - position
  - oracle_price (signed)
  - insurance_fund_state

Circuit prüft:
  1. account.balance + unrealized_pnl < maintenance_margin(position)
  2. Oracle-Preis gültig signiert
  3. Maintenance Margin = position.size * oracle_price * maintenance_rate
  4. Liquidation korrekt ausgeführt (Position geschlossen)
  5. Liquidations-Fee korrekt berechnet
  6. Insurance Fund korrekt aktualisiert (Überschuss/Defizit)

Output:
  - new_account_state_hash (liquidiertes Konto)
  - new_insurance_fund_hash
  - liquidation_nullifier
```

### 5.3 Konsens-Mechanismus (ohne Blockchain)

**Kein klassischer BFT-Konsens nötig.** Stattdessen:

```
1. Sequencer published batch of matched trades
2. Jeder Trade hat einen ZK-Proof
3. Verifier prüfen Proofs (O(1) per Proof, milliseconds)
4. Wenn ≥ 2/3 Verifier den Batch akzeptieren → State-Update
5. Sequencer publiziert Batch-Nullifier auf Bitcoin
6. Bei Dispute: Jeder kann on-chain challengen (à la Optimistic Rollup)
```

**Warum kein vollständiger BFT nötig ist:**
- ZK-Proofs sind mathematisch verifizierbar — entweder korrekt oder nicht
- Sequencer kann nicht betrügen (Proof wäre ungültig)
- Sequencer kann zensieren → Rotation löst das
- Settlement auf Bitcoin ist final

**Sequencer-Rotation:**
- Epoch-basiert (z.B. alle 10 Minuten)
- Deterministisch (Hash der letzten Bitcoin-Block-Header)
- Bei Ausfall: Timeout → nächster Operator übernimmt
- State ist repliziert, Übernahme ist seamless

### 5.4 Performance-Analyse

```
Orderbook-Matching (Sequencer):
  - Limitiert durch Sequencer-Hardware
  - Realistisch: 10'000-50'000 Orders/Sekunde
  - Latenz: 1-10ms (lokale Computation)

ZK-Proof-Generation:
  - Pro Trade: ~1-5 Sekunden (SP1, CPU)
  - Batched: 100 Trades in einem Proof möglich
  - GPU (CUDA): 10-100x schneller
  - Succinct Network: Outsourced, parallel

Settlement auf Bitcoin:
  - Batch-Nullifier alle 10-60 Sekunden
  - 64 Bytes pro Batch (nicht pro Trade!)
  - Bitcoin-Finality: ~10 Minuten (1 Block)

Gesamtlatenz:
  - Order → Match: 1-10ms ✅
  - Match → Proof: 1-5s (batched) ⚠️
  - Proof → Bitcoin: 10-60s (batching) ⚠️
  - Bitcoin-Finality: ~10 min (aber nicht blocking)
```

**Vergleich mit Hyperliquid:**

| Metrik | Hyperliquid | Variante C |
|--------|------------|------------|
| Order-Latenz | ~200ms | 1-10ms |
| Settlement-Latenz | ~200ms | 1-60s |
| Finality | ~200ms (L1) | ~10min (Bitcoin) |
| Orders/Sekunde | ~100k | ~10-50k |
| Privacy | ❌ Keine | ✅ Voll |
| Dezentralisierung | ◐ Schwach | ◑ Stark |

**Fazit**: Etwas langsamer beim Settlement, aber schneller beim Matching. Privacy ist das Differenzierungsmerkmal, nicht Speed.

### 5.5 Wirtschaftsmodell (ohne Token)

```
Revenue Streams:
├── Trading Fees (0.01-0.05% per Trade)
│   - Verteilt an Operatoren proportional zu Uptime
│   - Bezahlt in BTC (via zkCoins shielded)
│
├── Liquidation Fees (0.5-1% der liquidierten Position)
│   - Keeper erhält 50%
│   - Insurance Fund erhält 50%
│
└── Funding Rate Delta
    - Exchange behält minimalen Spread auf Funding

Operator-Incentive:
├── Sequencer-Bonus: Höherer Fee-Anteil während Sequencer-Epoch
├── Verifier-Bonus: Fee-Anteil für korrekte Verifikation
└── Keeper: Liquidations-Bounty (permissionless)

Kein eigener Token:
- Fees in BTC (shielded)
- Kein Governance-Token nötig
- Kein Staking-Token nötig
- Operator-Selection via Reputation + Deposit
```

### 5.6 Implementierungs-Roadmap

```
Phase 1: Foundation (3-6 Monate)
├── Extend zkCoins AccountState → PerpAccount
├── Implement Margin-Engine in SP1 Circuit
├── Basic Orderbook (single server, wie jetzt)
├── Oracle-Feed Integration (Chainlink, Pyth)
├── 1-2 Märkte (BTC-PERP, ETH-PERP)
└── Testnet auf Bitcoin Signet

Phase 2: Privacy (3-6 Monate)
├── Shielded Positions (encrypted in SMT)
├── Liquidation-Proofs im SP1 Circuit
├── Funding-Rate-Mechanismus
├── Batch-Proof-Optimierung
├── Insurance Fund
└── 10+ Märkte

Phase 3: Dezentralisierung (6-12 Monate)
├── Operator-Netzwerk (3-5 Nodes)
├── Sequencer-Rotation
├── State-Replication
├── Keeper-Netzwerk (permissionless)
├── GPU-Proving (CUDA/Succinct Network)
└── Bitcoin Mainnet Settlement

Phase 4: Scale (6-12 Monate)
├── 50+ Märkte
├── Cross-Margin
├── Portfolio-Margin
├── Sub-Accounts
├── API für Market Maker
├── BitVM2 Bridge (trustless BTC Ein-/Auszahlung)
└── Open Operator Onboarding
```

---

## 6. Warum Privacy DAS Differenzierungsmerkmal ist

### 6.1 Das Problem öffentlicher Positionen

Auf Hyperliquid (und allen transparenten DEXes) ist ALLES öffentlich:

- **Grosse Positionen** sind sichtbar → gezielte Liquidation durch Whales
- **Stop-Losses** sind sichtbar → Stop-Hunting
- **PnL** ist sichtbar → Social Pressure, Copytrading-Manipulation
- **Wallet-Adressen** sind verlinkbar → Doxxing-Risiko
- **Open Interest** ist sichtbar → Manipulative Strategien
- **Funding-Arbitrage** ist transparent → Edge verschwindet sofort

### 6.2 Was eine shielded Exchange löst

```
Beispiel: Grosser Trader will $50M BTC Long öffnen

Auf Hyperliquid:
  1. Position öffnen → sofort auf Chain sichtbar
  2. Andere Trader sehen die $50M Position
  3. Gegenreaktion: Shorts werden aufgebaut
  4. Whale-Alert-Bots tweeten die Position
  5. Preis bewegt sich gegen den Trader
  6. Bei Drawdown: Liquidation wird öffentlich → Panik

Auf zkCoins Perp (Variante C):
  1. Position öffnen → verschlüsselt in SMT
  2. Niemand sieht Grösse, Richtung oder Hebel
  3. Keine Gegenreaktion möglich
  4. Kein Whale-Alert (nichts zu reporten)
  5. Preis bewegt sich frei
  6. Bei Liquidation: nur Keeper + Account-Holder wissen davon
```

### 6.3 Zielgruppe

| Segment | Warum Privacy wichtig |
|---------|----------------------|
| Institutionelle Trader | Compliance, Wettbewerbsgeheimnis |
| Market Maker | Strategie-Schutz, Inventory-Privacy |
| Whale-Trader | Schutz vor gezielter Liquidation |
| DeFi-Protocols (Treasury) | Hedging ohne öffentliche Exposure |
| Privacy-Fokussierte Nutzer | Ideologisch motiviert (Bitcoin-Ethos) |

---

## 7. Risiken und offene Fragen

### 7.1 Technische Risiken

| Risiko | Schwere | Mitigation |
|--------|---------|------------|
| SP1 Proof-Latenz zu hoch | Hoch | GPU-Proving, Batching, Succinct Network |
| ZK-Circuit zu komplex für Margin-Engine | Mittel | Iterative Vereinfachung, SP1 ist Turing-complete |
| Sequencer-Zentralisierung | Mittel | Rotation, Challenge-Mechanismus |
| Oracle-Manipulation | Hoch | Multi-Source, Median, Operator-signiert |
| Bitcoin-Blockspace-Kosten | Niedrig | Batching (64 Bytes pro Batch, nicht pro Trade) |

### 7.2 Regulatorische Risiken

| Risiko | Schwere | Mitigation |
|--------|---------|------------|
| Privacy-Tools unter Druck (Tornado Cash) | Hoch | Kein Coordinator, kein Smart Contract, kein Token |
| KYC/AML-Anforderungen | Mittel | Optional: ZK-KYC (beweise Compliance ohne Daten) |
| Derivate-Regulierung | Hoch | Dezentral, kein Firmensitz, kein Token |

### 7.3 Wirtschaftliche Risiken

| Risiko | Schwere | Mitigation |
|--------|---------|------------|
| Nicht genug Liquidität | Hoch | Market-Maker-Incentives, shielded MM |
| Hyperliquid-Netzwerkeffekt | Hoch | Privacy als unique value prop |
| Kein Token = kein Hype | Mittel | Organisches Wachstum, Bitcoin-Community |

### 7.4 Offene Forschungsfragen

1. **Wie komplex kann der SP1-Circuit werden?** — Margin-Engine + Liquidation + Funding in einem Proof?
2. **Proof-Aggregation**: Können 1000 Trades in einem Proof zusammengefasst werden?
3. **Oracle-Design**: Wie dezentralisiert man den Oracle-Feed ohne eigenen Konsens?
4. **Cross-Margin im ZK-Circuit**: Wie beweist man Portfolio-Level-Margin effizient?
5. **Sequencer-Fairness**: Wie verhindert man Front-Running durch den Sequencer selbst?

---

## 8. Fazit

### Die optimale Lösung: Variante C — zkCoins Operator Network

**Variante C ist die beste Kombination aus Machbarkeit und Differenzierung.**

Sie nutzt die Kernstärken von zkCoins:
- SP1 zkVM für beliebige Computation in ZK (Margin, Liquidation, Funding)
- Shielded Accounts via Sparse Merkle Tree
- Bitcoin-Settlement via Nullifiers
- Bewährte Kryptografie (Schnorr, BIP-32, SHA-256)

Und adressiert die grössten Schwächen von Hyperliquid:
- **Privacy**: Vollständig verborgen (Positionen, PnL, Liquidationen)
- **Dezentralisierung**: Offenes Operator-Netzwerk statt permissioned Validator-Set
- **Kein eigener Token**: Revenue via Trading-Fees in BTC
- **Bitcoin-aligned**: Settlement auf Bitcoin, nicht auf eigener L1

### Was zu bauen ist (minimal viable)

1. **PerpAccount** — Erweiterung des zkCoins AccountState um Positionen und Margin
2. **Margin-Circuit** — SP1-Programm das Margin-Anforderungen verifiziert
3. **Orderbook** — Klassisches CLOB mit Price-Time-Priority
4. **Oracle** — Multi-Source-Preis-Feed mit Operator-Signaturen
5. **Settlement** — Batch-Nullifiers auf Bitcoin

### Der Name

> **zkCoins Exchange** — Private Perpetual Futures. Settled on Bitcoin.
>
> Vertikal-Bezeichner intern: "Exchange". Domain: [zkcoins.exchange](https://zkcoins.exchange).
> (Frühere Arbeitstitel "zkPerps" wurden mit der Entscheidung für Brand A verworfen — siehe Header dieses Dokuments und [marketing/strategy/exchange/vision.md](https://github.com/zk-coins/marketing/blob/develop/strategy/exchange/vision.md).)

### Zusammenfassung in einem Satz

**Ein Hyperliquid mit Privacy: Trades sind schnell und liquide wie auf einer CEX, aber Positionen, Balances und Liquidationen sind kryptografisch verborgen — settled auf Bitcoin, ohne eigenen Token, ohne eigene Blockchain.**
