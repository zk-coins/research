# Threat Model — Fraud Scenarios for zkCoins L2

> Draft | 2026-05-11 | Comprehensive adversarial analysis
>
> Systematic enumeration of every fraud and attack scenario against the zkCoins L2 protocol, the SSS trust model, and the perpetuals venue built on it. Per actor, per scenario, with prerequisites, effects, mitigations, and residual risk.

This document depends on:
- [`l2-protocol-design.md`](l2-protocol-design.md) — protocol primitives
- [`sss-trust-model.md`](sss-trust-model.md) — validity hierarchy and trust profiles

---

## Table of Contents

1. [Methodology](#methodology)
2. [Threat Actors](#threat-actors)
3. [Sender-Initiated Attacks](#sender-initiated-attacks)
4. [Receiver-Initiated Attacks](#receiver-initiated-attacks)
5. [SSS-Initiated Attacks](#sss-initiated-attacks)
6. [Miner-Initiated Attacks](#miner-initiated-attacks)
7. [Multi-Actor Conspiracies](#multi-actor-conspiracies)
8. [Bond and Slashing Attacks](#bond-and-slashing-attacks)
9. [Force-Exit Attacks](#force-exit-attacks)
10. [Economic Attacks](#economic-attacks)
11. [Privacy Attacks](#privacy-attacks)
12. [Network and Software Attacks](#network-and-software-attacks)
13. [Cross-Asset Attacks](#cross-asset-attacks)
14. [Attack Matrix](#attack-matrix)
15. [Residual Risks](#residual-risks)

---

## Methodology

For each attack, this document specifies:

- **Actor(s)**: who is the adversary
- **Target**: who or what is harmed
- **Prerequisites**: capabilities and knowledge required by the adversary
- **Mechanism**: how the attack is executed
- **Effect**: what the adversary gains, what the victim loses
- **Detection**: whether and how the attack is detectable
- **Mitigation**: protocol mechanisms that prevent or reduce the attack
- **Residual risk**: what remains exploitable even with mitigations in place
- **Affected trust profiles**: which receiver profiles are vulnerable (P1, P2, P3, P4)

The threat model uses the **Dolev-Yao** assumption for cryptography: the adversary cannot break cryptographic primitives (signatures, hashes, ZK proofs) but can do anything else permitted by the protocol semantics.

Bitcoin's standard security assumption is preserved: no adversary controls ≥50% of mining hashrate consistently, no adversary achieves ≥6 consecutive blocks deliberately under realistic conditions.

---

## Threat Actors

| Actor | Description | Power |
|---|---|---|
| **Sender** | Account holder initiating a transaction | Owns account key, can produce valid signatures |
| **Receiver** | Recipient of a transaction | Verifies proofs, accepts or rejects |
| **SSS** | Single Signer Server for an asset | Holds SSS pubkey, decides which transactions to sign |
| **Miner** | Bitcoin block producer | Decides which transactions enter blocks, controls fee market |
| **Asset issuer** | Creator of the asset (typically = initial SSS) | Defined the asset's parameters at genesis |
| **Bond holder** | Entity controlling the SSS bond UTXO | Can spend bond via timelock path |
| **Watcher** | Third party monitoring on-chain for misbehavior | Can submit slashing proofs |
| **Network adversary** | Controls victim's network connectivity | Eclipse, BGP, DNS attacks |
| **Software adversary** | Controls a piece of software the victim uses | Wallet, extension, library |
| **Sender's accomplice** | Another party colluding with sender | Adds capabilities (e.g., another account, miner contact) |

Most realistic adversaries combine several of these roles. The most dangerous combinations are catalogued in *Multi-Actor Conspiracies* below.

---

## Sender-Initiated Attacks

### S1. Simple Double-Spend Attempt (SSS-Mediated × 2)

**Actor**: Sender Alice  
**Target**: Receivers Bob and Carol  
**Prerequisites**: Account state allowing a single spend, two intended recipients  
**Mechanism**: Alice submits T_AB to the SSS. After receiving signature, she submits T_AC to the SSS for the same account state.  
**Effect**: If SSS is honest, none. SSS detects conflict and refuses to sign T_AC.  
**Detection**: SSS sees both submissions; trivially detected.  
**Mitigation**: SSS state-tracking is the entire point of the SSS role.  
**Residual risk**: None, assuming honest SSS. (See SSS-attacks for malicious SSS.)  
**Affected profiles**: None.

### S2. Sender Equivocation via Parallel Paths

**Actor**: Sender Alice  
**Target**: Receivers Bob and Carol simultaneously  
**Prerequisites**: Account key, ability to natively broadcast (bypass SSS)  
**Mechanism**:
1. Alice submits T_AB to the SSS. SSS signs.
2. Alice signs T_AC with her own account key and natively broadcasts.
3. Both inscriptions reach the chain.

**Effect**: 
- Bob (P1/P2/P3) sees SSS-signed T_AB, accepts at his profile's threshold. Ships goods.
- Carol (P1/P2/P3) sees unsigned T_AC, accepts at 6 confs. Ships goods.
- At T_AC's block N+12, T_AC reaches tier (a). It beats T_AB.
- Final canonical state: Carol's transaction. Bob's transaction is reverted.
- Alice has obtained goods from both Bob and Carol but only paid Carol.

**Detection**: 
- Both transactions are on-chain with the same account key's signature over different message contents.
- A watcher or either victim can cryptographically prove sender equivocation (two valid signatures, same key, different messages).

**Mitigation**:
- **Profile 4** is immune: P4 receivers wait 12 confs for unsigned transactions and reject SSS-signed entirely. P4 Bob would not have accepted T_AB. P4 Carol would have correctly waited until tier (a) was reached.
- **Sender personal bond** (optional protocol extension): if Alice has posted a bond, the equivocation proof slashes it.

**Residual risk**:
- Without a sender bond, no economic penalty for sender equivocation. Reputation is the only deterrent.
- P1/P2/P3 receivers are exposed unless they have out-of-band knowledge that Alice is trustworthy.

**Affected profiles**: P1, P2, P3.

### S3. Sender-Initiated SSS Bypass Race

**Actor**: Sender Alice  
**Target**: Receiver Bob (who expects SSS-mediated path)  
**Prerequisites**: Account key, ability to bribe a miner directly  
**Mechanism**:
1. Alice submits T_AB to SSS, SSS signs.
2. Alice immediately natively broadcasts T_AC (conflicting, to herself or accomplice).
3. Alice bribes a miner to inscribe T_AC and exclude T_AB.

**Effect**: Same as S2 in terms of canonical outcome. Detection identical.  
**Mitigation**: Same as S2.  
**Residual risk**: Same as S2 plus the miner bribery cost (paid by Alice).  
**Affected profiles**: P1, P2, P3.

This is just S2 with extra adversarial effort by the sender. Defense is identical.

### S4. Replay Attack on Old Transaction

**Actor**: Sender Alice (or anyone with copy of an old TX)  
**Target**: Receiver Bob  
**Prerequisites**: Possession of an old signed transaction; absence of replay protection in the protocol  
**Mechanism**: Alice re-broadcasts an old transaction T_AB hoping Bob accepts it as a fresh payment.  
**Effect**: If protocol allows replay, Bob accepts the same money twice. If protocol prevents replay, attack fails.  
**Detection**: Trivial — the transaction's nullifier is already on-chain.  
**Mitigation**: The Shielded CSV nullifier mechanism intrinsically prevents replay. Each transaction generates a unique nullifier per account state; once inscribed, no transaction with the same nullifier can be accepted again.  
**Residual risk**: None at the protocol level. Application-level replays (e.g., re-using payment links) are a UX problem, not a protocol problem.  
**Affected profiles**: None (protocol-level immunity).

### S5. Fee Manipulation / Inscription Front-Running

**Actor**: Sender Alice  
**Target**: Other senders, MEV-aware participants  
**Prerequisites**: Visibility into mempool, ability to outbid for inscription position  
**Mechanism**: Alice observes pending inscriptions in mempool and broadcasts her own with higher fees to ensure her inscription wins block-position priority.  
**Effect**: Alice's transaction is canonical despite arriving later. For Mode A assets (where block-position determines order), this can affect double-spend outcomes.  
**Detection**: Visible in mempool; visible on-chain post-hoc.  
**Mitigation**: 
- For Mode B assets: the SSS signature path is unaffected — SSS only signs the first transaction.
- For Mode A assets: this is the standard Bitcoin fee market. There is no mitigation; it is the nature of the system.

**Residual risk**: MEV-style fee front-running is endemic to Bitcoin. Accepted as residual.  
**Affected profiles**: All, but only on Mode A assets and only for transactions whose acceptance depends on tight block ordering.

### S6. Force-Exit Spam

**Actor**: Sender Alice (or any holder)  
**Target**: The SSS (operational disruption)  
**Prerequisites**: Bitcoin UTXOs to pay for force-exit inscriptions, valid account states for which to demand exit  
**Mechanism**: Alice issues many force-exit claims, requiring the SSS to refute each within the challenge period.  
**Effect**: SSS operational load increases. If SSS is overwhelmed and fails to refute legitimate-looking but spurious claims, fraudulent exits succeed.  
**Detection**: The pattern is visible on-chain (many force-exit inscriptions from same source).  
**Mitigation**: 
- Force-exit claims should require a bond by the claimant, refundable if the claim is honest.
- Spurious claims forfeit their bond.

**Residual risk**: The cost of force-exit spam is the bond × the number of bogus claims. As long as bonds are non-trivial, the attack is unprofitable.  
**Affected profiles**: All (asset-level disruption affects everyone).

### S7. State Snapshot Old-State Replay (Force-Exit)

**Actor**: Sender Alice  
**Target**: The SSS, indirectly other holders  
**Prerequisites**: Possession of an old (valid-at-time) state proof for Alice's account; SSS unable or unwilling to refute  
**Mechanism**: Alice publishes a force-exit claim with an old state proof showing a higher balance than her current state.  
**Effect**: If SSS doesn't refute in time, Alice extracts more than her current entitlement.  
**Detection**: The SSS knows Alice's current state; refutation is straightforward.  
**Mitigation**: SSS-side refutation requires only signing a more-recent state proof with Alice's account.  
**Residual risk**: Only if SSS is offline for the entire challenge period AND no other watcher refutes. Watcher network can independently challenge using public commitment data.  
**Affected profiles**: All.

### S8. Selectively Withhold Coin Data from Receiver

**Actor**: Sender Alice  
**Target**: Receiver Bob  
**Prerequisites**: Standard sender capability  
**Mechanism**: Alice publishes T_AB on-chain (gets credit for "paying"), but does not deliver the off-chain coin data (ZK proof, inclusion proofs) to Bob.  
**Effect**: Bob sees the nullifier on-chain but cannot reconstruct the coin he received. The funds are functionally locked: nobody can spend them.  
**Detection**: Bob can prove non-delivery only by negative evidence ("I never received it").  
**Mitigation**: 
- Off-chain message delivery should be acknowledged (e.g., via signed receipt from Bob).
- Sender should retain proof of delivery (signed by Bob) before considering the transaction complete.
- This is essentially the problem of every off-chain protocol; standard message-delivery patterns apply.

**Residual risk**: Pure withholding is a denial-of-service against Bob. Alice loses the funds too (they're locked), so it's unprofitable unless Alice's goal is harm rather than gain.  
**Affected profiles**: All.

### S9. Dust-Attack via Many Small Sends

**Actor**: Sender Alice  
**Target**: Receiver Bob (privacy or wallet usability)  
**Prerequisites**: Cheap inscription fees, Bob's account address  
**Mechanism**: Alice sends many tiny amounts to Bob, hoping to cluster Bob's account or flood his wallet.  
**Effect**: Privacy degradation if Bob's wallet processes all incoming coins similarly; UI clutter; possible cost to Bob if processing/spending these costs more than the dust value.  
**Detection**: Pattern visible on-chain (many small sends from same source).  
**Mitigation**: 
- Bob's wallet can ignore inbound transactions below a dust threshold.
- Bob can refuse to spend dust transactions, leaving them as "uncollected."

**Residual risk**: Minor UX impact. Privacy impact depends on wallet design.  
**Affected profiles**: All.

---

## Receiver-Initiated Attacks

### R1. False Non-Receipt Claim

**Actor**: Receiver Bob  
**Target**: Sender Alice  
**Prerequisites**: Standard receiver capability  
**Mechanism**: Bob claims to have not received a valid transaction Alice already sent, demanding redelivery or refund.  
**Effect**: Off-protocol social attack; Alice may comply and effectively pay twice.  
**Detection**: Sender can require Bob's signed receipt before considering the transaction complete.  
**Mitigation**: Application-layer signed receipt before "delivery acknowledged."  
**Residual risk**: Pure social-engineering attack. Protocol cannot fully prevent it.  
**Affected profiles**: All.

### R2. False Slashing Claim

**Actor**: Receiver Bob, or any watcher  
**Target**: The SSS or bond holder  
**Prerequisites**: Crafting plausible-looking but invalid slashing proof  
**Mechanism**: Bob submits a slashing proof that looks valid but is not (e.g., one of the two SSS signatures is forged or relates to a different account state).  
**Effect**: If the bond contract's validation script is correct, the attempt fails — Bitcoin script rejects the unlock. No funds change hands.  
**Detection**: The validation script execution is the detection.  
**Mitigation**: Bond contract script must rigorously validate the equivocation proof: same SSS pubkey, two real Schnorr signatures, two different messages, both referencing the same account state.  
**Residual risk**: If the script is buggy, false slashing could succeed. This is a script-design issue, not a protocol issue.  
**Affected profiles**: None directly; bond contract integrity is a separate property.

### R3. Force-Exit Mimicry / Sybil Force-Exit

**Actor**: Receiver Bob (claiming to be Alice)  
**Target**: Alice (the actual account holder)  
**Prerequisites**: Possession of (some of) Alice's information; ability to forge force-exit data  
**Mechanism**: Bob attempts a force-exit claim for Alice's account.  
**Effect**: If Bob lacks Alice's account key, he cannot produce a valid signature on the force-exit claim. Attack fails.  
**Detection**: Signature verification.  
**Mitigation**: Force-exit claims must be signed by the account key. Cryptographic.  
**Residual risk**: None (cryptographic prevention).  
**Affected profiles**: None.

### R4. Coin-Data Hoarding for Future Sale

**Actor**: Receiver Bob  
**Target**: The asset's overall liquidity / health  
**Prerequisites**: Standard receiver capability  
**Mechanism**: Bob receives coins but refuses to spend them, withholding inventory from market.  
**Effect**: This is normal user behavior, not an attack. Mentioned for completeness.  
**Detection**: N/A.  
**Mitigation**: N/A.  
**Residual risk**: N/A.  
**Affected profiles**: N/A.

---

## SSS-Initiated Attacks

### X1. SSS Equivocation (Two Signatures, Same Account State)

**Actor**: SSS  
**Target**: At least one of the two transactions' receivers  
**Prerequisites**: SSS controls its signing key  
**Mechanism**: SSS receives two conflicting submissions for the same account state. It signs both (either deliberately or due to a bug).  
**Effect**:
- Both T_X and T_Y are SSS-signed.
- Both reach inscription.
- Hierarchy resolves to first-inscribed; the second's receiver loses.
- A watcher (or the losing receiver) can produce a cryptographic equivocation proof.

**Detection**: Trivial after both transactions are on-chain. Two SSS signatures with same key over different messages referencing the same account state.  
**Mitigation**:
- **Bond slashing**: the bond contract's slashing path is activated by exactly this proof.
- Affected receivers claim against the bond.

**Residual risk**:
- If the bond is too small for the total damage (i.e., SSS equivocated on many high-value transactions simultaneously), some victims are not fully made whole.
- If watchers don't catch it quickly, late submissions might miss claim windows.

**Affected profiles**: P1, P2, P3 directly. P4 is unaffected (doesn't trust SSS-signed in the first place).

### X2. SSS Late-Sign Attack

**Actor**: SSS  
**Target**: Receiver of an unsigned transaction with 6+ confs  
**Prerequisites**: An attacker (could be the sender, an accomplice, or the SSS itself with a beneficiary account) has an account state allowing competition  
**Mechanism**:
1. Sender Alice broadcasts unsigned T_AB to Bob in block N.
2. Bob (P2/P3) accepts at block N+6.
3. SSS waits until N+8, then signs T_AC (competing, to attacker).
4. T_AC is inscribed in block N+9.
5. Hierarchy: T_AC (tier b) beats T_AB (tier c). T_AB is reverted.
6. Bob loses goods already shipped.

**Effect**: Bob (P1/P2/P3) loses. Bob (P4) had waited for 12 confs; T_AB reached tier (a) at N+12 before T_AC could overtake. P4 unaffected.

**Detection**:
- The two transactions T_AB and T_AC have different senders (or the same sender with parallel-path equivocation). The SSS is providing late attestation that flips canonical state. Pattern detectable on-chain.

**Mitigation**:
- Profile 4 acceptance threshold (12 confs unsigned).
- Bond slashing if T_AC's signature can be proved to be SSS equivocation. (Note: in the basic form of X2, the SSS only signs T_AC; it has not signed T_AB. So there's no equivocation strictly speaking. The attack works because the SSS gives a competing transaction a higher tier.)

**Residual risk**:
- Without a sender bond on the attacker, no economic penalty.
- P1/P2/P3 receivers of unsigned transactions on Mode B assets are intrinsically exposed to this attack vector.

**Affected profiles**: P1 (falls back to P2 on unsigned), P2, P3.

### X3. SSS Censorship (Selective Refusal)

**Actor**: SSS  
**Target**: Specific user or set of users  
**Prerequisites**: SSS can identify the target (by account key, IP, or other side-channel)  
**Mechanism**: SSS refuses to sign transactions for the target.  
**Effect**: Target falls back to native broadcast. Soft-finality unavailable for that user; otherwise unaffected.  
**Detection**: User-visible: their submissions are rejected.  
**Mitigation**: Native broadcast remains available. The user reverts to Mode A behavior on this asset.  
**Residual risk**: 
- UX degradation for the target.
- Possible discriminatory censorship if SSS systematically excludes certain users.
- Cannot be cryptographically prevented (the SSS has discretion over signing).

**Affected profiles**: None directly. UX degradation, not financial loss.

### X4. SSS Honeypot / Privacy Harvesting

**Actor**: SSS  
**Target**: All users of the asset  
**Prerequisites**: Standard SSS role  
**Mechanism**: SSS logs all transactions it sees (which is its job) and either retains or sells this data.  
**Effect**: Privacy degradation. The SSS sees the full transaction graph for its asset.  
**Detection**: Only if logs leak or are misused publicly.  
**Mitigation**:
- Blind-signature SSS protocols (research direction; not yet implemented).
- Multiple SSSs in rotation (re-opens coordination problems).
- Asset segmentation by user (split holdings across several assets/SSSs).

**Residual risk**: Substantial. This is the irreducible privacy cost of having an SSS. Users who want full privacy should use Mode A assets (no SSS) and accept 6-conf finality.  
**Affected profiles**: All (privacy, not financial).

### X5. SSS Bond Drain via Forced Slashing

**Actor**: SSS in cooperation with sender accomplices, OR a sophisticated attacker manipulating an honest SSS  
**Target**: The bond, ultimately legitimate users  
**Prerequisites**: Ability to cause SSS-equivocation patterns repeatedly  
**Mechanism**:
1. Attacker submits transaction T_X to SSS.
2. SSS signs (correctly, based on its view).
3. Attacker also presents the SSS with a competing T_Y (e.g., via a wallet bug, race condition, or compromised SSS endpoint) — SSS signs T_Y under the impression it's a separate, valid submission.
4. Slashing proof generated. Bond partially drained.
5. Repeat until bond is depleted.

**Effect**: The bond is drained. Legitimate users who later experience SSS misbehavior have no coverage.  
**Detection**: Each slashing event is on-chain. Pattern of repeated draining is visible.  
**Mitigation**:
- **SSS must be implemented with strict atomic state-tracking** to prevent multiple-signing race conditions.
- **Bond contract** can enforce a minimum reserve or refill mechanism.
- **Watchdogs**: detect repeated micro-slashing and pause the SSS administratively.

**Residual risk**: Depends entirely on SSS implementation quality and bond-management.  
**Affected profiles**: P1, P2, P3 (those who rely on bond coverage).

### X6. SSS Front-Running Transaction Submissions

**Actor**: SSS  
**Target**: User submitting a transaction with valuable timing properties (e.g., a market order)  
**Prerequisites**: SSS sees pending submission before broadcast  
**Mechanism**: User submits T_X to SSS. Before signing T_X, SSS uses the visible information to execute its own (or accomplice's) trade T_Y first, capturing favorable pricing.  
**Effect**: User's order executes at worse price than expected. Particularly relevant for the perpetuals venue.  
**Detection**: Statistical analysis of pricing patterns; very hard to prove definitively.  
**Mitigation**:
- **Encrypted submissions**: user encrypts the order under a threshold-decryption scheme; SSS cannot read content until the matching epoch closes.
- **Order-flow auditing**: independent observers monitor SSS's order book against external benchmarks.
- **Reputational consequence**: discovered front-running destroys SSS's user base.

**Residual risk**: Without encrypted submissions, front-running is operationally easy and detection is difficult. Major concern for the perpetuals venue.  
**Affected profiles**: All trading users (perpetuals venue).

### X7. SSS Pre-Mining of Sequencer Epoch (Hyperliquid-Style)

**Actor**: SSS  
**Target**: All users during the SSS's epoch  
**Prerequisites**: SSS controls inscription timing  
**Mechanism**: SSS holds back submissions, batches them, and inserts SSS's own transactions advantageously.  
**Effect**: Similar to X6 but at scale, affecting all users during the epoch.  
**Detection**: Same as X6 — statistical, post-hoc.  
**Mitigation**: Same as X6.  
**Residual risk**: Same as X6.  
**Affected profiles**: All trading users.

### X8. SSS Liquidity Trap

**Actor**: SSS (as asset issuer)  
**Target**: All asset holders  
**Prerequisites**: Asset issuance allowing locked liquidity (e.g., wrapped Bitcoin variant requiring SSS for unwrap)  
**Mechanism**: SSS stops processing redemption transactions, effectively trapping users' wrapped assets.  
**Effect**: Users' funds become illiquid until force-exit completes (1+ challenge period of delay).  
**Detection**: Users discover refusal individually; aggregated, it becomes a public pattern.  
**Mitigation**:
- **Force-exit** is the protocol's answer: users withdraw without SSS cooperation.
- Force-exit cost (Bitcoin fees, challenge period delay) limits how harmful the trap can be.

**Residual risk**: Force-exit delay (one challenge period — 144 blocks ≈ 1 day per [`l2-protocol-design.md`](l2-protocol-design.md) §7, asset-configurable) is the floor. During that period, users cannot move funds.  
**Affected profiles**: All holders.

### X9. SSS Self-Slashing (Voluntary Bond Burn)

**Actor**: SSS  
**Target**: Itself (and the asset's reputation)  
**Prerequisites**: SSS controls bond key  
**Mechanism**: SSS deliberately equivocates to burn its own bond. Purpose unclear — possibly to escape obligations, to defraud bond claimants (by burning the bond before claims accumulate), or as an exit-scam pattern.  
**Effect**: Bond gone. Claimants who haven't claimed yet may face an empty bond.  
**Detection**: On-chain visible.  
**Mitigation**:
- Bond contract should enforce that slashing pays out to a public pool, not back to the SSS.
- Watchdogs alert users as soon as slashing is detected, so they can claim.

**Residual risk**: Race-to-claim. Late claimants may find the bond already paid out. Pro-rata distribution mitigates this but requires a claim-window protocol.  
**Affected profiles**: P1, P2, P3 (bond-dependent).

### X10. SSS Key Compromise

**Actor**: External attacker who has obtained SSS private key  
**Target**: All asset users  
**Prerequisites**: Successful operational attack on SSS infrastructure (server breach, side-channel, etc.)  
**Mechanism**: Attacker can sign anything as the SSS. Equivocation, front-running, censorship — all become possible.  
**Effect**: All trust in the SSS is broken. Asset effectively requires emergency response.  
**Detection**: Behavior becomes erratic; possibly silent for a while if attacker is careful.  
**Mitigation**:
- **Multi-sig SSS** (e.g., 2-of-3 keys with separate operational security domains).
- **Key rotation protocol** for emergency SSS replacement (see [`l2-protocol-design.md`](l2-protocol-design.md) §7.3).
- **Hardware security modules** for SSS key storage.
- **Bond slashing**: when SSS equivocation is detected, bond is triggered regardless of cause.

**Residual risk**: Operational security is hard. Multi-sig SSS adds latency. Emergency rotation requires holder cooperation to acknowledge new SSS pubkey.  
**Affected profiles**: P1, P2, P3 (P4 already assumes hostile SSS).

---

## Miner-Initiated Attacks

### M1. Single-Miner Bribery for Inscription Exclusion

**Actor**: Bribed miner  
**Target**: A specific transaction's receiver  
**Prerequisites**: Miner controls one upcoming block; bribe is paid  
**Mechanism**: Miner excludes a target inscription from their block.  
**Effect**: Target transaction is delayed by one block (until another miner includes it).  
**Detection**: Trivial — the transaction is in the mempool but not in the produced block.  
**Mitigation**: Other miners will include the transaction in subsequent blocks. The user can also use CPFP or RBF to ensure inclusion.  
**Residual risk**: Slight delay only. Not a serious attack.  
**Affected profiles**: All (UX delay).

### M2. Single-Miner Bribery for Inscription Reordering

**Actor**: Bribed miner  
**Target**: Specific transaction in a same-block conflict scenario  
**Prerequisites**: Miner controls block, two conflicting transactions both in mempool, willing to be paid for specific ordering  
**Mechanism**: Miner orders inscriptions within the block to favor one transaction over the other.  
**Effect**: For Mode A assets where same-block order matters: the bribed ordering wins. For Mode B with SSS-signed: SSS-signed wins regardless of position because tier (b) > tier (c)/(d).  
**Detection**: Visible on-chain — inscription positions within the block are public.  
**Mitigation**: Mode B's tier hierarchy renders same-block reordering moot for signed transactions.  
**Residual risk**: Mode A assets are exposed to bribery for same-block ordering. This is intentional (Mode A is the "low-trust" mode that accepts standard Bitcoin behavior).  
**Affected profiles**: Mode A receivers only.

### M3. 1-2 Block Reorg

**Actor**: Miner with substantial hashrate, OR coalition  
**Target**: Specific transaction's receiver  
**Prerequisites**: Significant hashrate; willingness to forfeit one or two block rewards  
**Mechanism**: Miner privately builds an alternative chain that excludes the target transaction; releases when their chain is longer.  
**Effect**: Transaction is reverted; the alternative chain becomes canonical.  
**Detection**: Reorg is visible to all node operators.  
**Mitigation**: 6-conf threshold (P2/P3/P4 receivers all wait at least 6 confs).  
**Residual risk**: For transactions with <6 confs, vulnerable. Standard Bitcoin trade-off.  
**Affected profiles**: P1 (who accepts SSS-signed at 0 confs — but the SSS sig protects against this since the transaction can be re-inscribed in the new chain with the same SSS sig).

### M4. Deep Reorg (≥6 Blocks)

**Actor**: Miner with >50% hashrate, OR effective coalition with sustained dominance  
**Target**: Specific transaction or general protocol disruption  
**Prerequisites**: Majority hashrate sustained over multiple blocks  
**Mechanism**: Build a longer chain than the honest one, including only the attacker's preferred transactions.  
**Effect**: Bitcoin itself is broken at this point. zkCoins inherits Bitcoin's failure.  
**Detection**: Catastrophic and obvious.  
**Mitigation**: None at the zkCoins layer. Bitcoin's PoW security is the foundation.  
**Residual risk**: This is Bitcoin's tail risk. Mitigation is at the Bitcoin layer (decentralized mining ecosystem).  
**Affected profiles**: All.

### M5. Selfish Mining

**Actor**: Miner with significant hashrate  
**Target**: Honest miners; indirectly the network's transaction throughput  
**Prerequisites**: Sufficient hashrate (>25% theoretically profitable)  
**Mechanism**: Miner withholds found blocks and releases strategically to invalidate honest blocks.  
**Effect**: Honest blocks wasted; selfish miner captures disproportionate share of rewards. Transactions in the honest blocks may take longer to confirm.  
**Detection**: Statistical pattern over many blocks.  
**Mitigation**: This is a Bitcoin-protocol-layer issue. zkCoins inherits Bitcoin's behavior.  
**Residual risk**: Same as Bitcoin's residual risk.  
**Affected profiles**: All (slight delay).

### M6. Mempool Eclipse / Targeted Exclusion

**Actor**: Network adversary controlling victim's view of mempool  
**Target**: Receiver Bob  
**Prerequisites**: Control over Bob's network connection  
**Mechanism**: Eclipse Bob's wallet so it sees only inscriptions that confirm a desired (possibly false) state.  
**Effect**: Bob's wallet may not see a competing transaction that exists. Bob accepts based on incomplete information.  
**Detection**: Bob would need to query multiple independent sources to detect.  
**Mitigation**:
- Wallet should query multiple node providers for chain state.
- Tor / mixnets for network-level privacy.

**Residual risk**: Network-level attacks are out-of-protocol; mitigations are wallet-implementation concerns.  
**Affected profiles**: All (especially P1/P2/P3 who don't wait for deep finality and might miss late-arriving competition).

---

## Multi-Actor Conspiracies

### C1. SSS + Miner — Late SSS-Sig with Guaranteed Inscription

**Actors**: SSS + bribed miner(s)  
**Target**: Receiver of an unsigned transaction  
**Prerequisites**: SSS willing to equivocate / sign for late-arriving conflict; miner willing to inscribe the late SSS-signed transaction in time  
**Mechanism**: Combination of X2 (late SSS-sign) and M2 (miner-controlled inscription).
1. Alice sends T_AB unsigned to Bob in block N.
2. Bob (P1/P2/P3) accepts at his profile's threshold.
3. SSS publishes late SSS-signed T_AC (to attacker) at block N+8.
4. Bribed miner ensures T_AC is inscribed in block N+9.
5. Bob is reverted at block N+9.

**Effect**: Bob (P1/P2/P3) loses. Bob (P4) is safe due to 12-conf threshold.  
**Detection**: 
- Public chain shows the timing pattern.
- T_AC's SSS sig is public — if compared to T_AB's unsigned state, the attack pattern is visible.
- However, since the SSS only signed T_AC (not T_AB), this is not formally "SSS equivocation" — no slashing trigger.

**Mitigation**: Profile 4 only.  
**Residual risk**: Mode B assets have this attack vector permanently. The only way to be immune is to wait for tier (a) — which is what P4 does.  
**Affected profiles**: P1, P2, P3.

### C2. Sender + SSS — Authorized Equivocation

**Actors**: Sender Alice (asset holder) + SSS (her accomplice)  
**Target**: Multiple receivers of Alice's transactions  
**Prerequisites**: SSS is willing to sign multiple conflicting transactions from Alice  
**Mechanism**:
1. Alice initiates T_AB to Bob via SSS. SSS signs.
2. Alice initiates T_AC to Carol via SSS. SSS signs.
3. Both inscribed. Both at tier (b).
4. Hierarchy resolves to first-inscribed.
5. Whoever loses has been defrauded.

**Effect**: One of Bob, Carol loses goods.  
**Detection**: SSS equivocation is on-chain. Bond slashable.  
**Mitigation**:
- Bond slashing penalizes the SSS (which is colluding with Alice, so the loss is partially Alice's too).
- P4 receivers reject SSS-signed and are not exposed.

**Residual risk**: If SSS+sender are willing to lose the bond as part of the attack value (extreme), the attack is economically possible. Mitigation: bond must exceed maximum exploitable value.  
**Affected profiles**: P1, P2, P3.

### C3. Sender + Miner — Bypass SSS via Bribed Inscription

**Actors**: Sender Alice + bribed miner  
**Target**: Receiver Bob (SSS-signed path) or Carol (native path)  
**Prerequisites**: Alice has account key; miner willing to inscribe what Alice wants  
**Mechanism**: Alice submits T_AB to SSS (which signs honestly). Then Alice natively broadcasts T_AC. The miner inscribes T_AC and excludes T_AB.
- Same as S2/S3 with miner help.

**Effect**: Same as S2.  
**Detection**: Same as S2 (sender equivocation, two valid sender sigs).  
**Mitigation**: Same as S2 (P4, sender bond).  
**Residual risk**: Same as S2.  
**Affected profiles**: P1, P2, P3.

### C4. SSS + Sender + Miner — Full Conspiracy

**Actors**: SSS + sender Alice + bribed miner(s)  
**Target**: Any receiver  
**Prerequisites**: All three coordinated  
**Mechanism**: Combination of C1, C2, C3. The conspiracy can:
- Generate SSS-signed transactions on demand.
- Inscribe them strategically.
- Equivocate freely.

**Effect**: The conspiracy can defeat any P1/P2/P3 receiver.  
**Detection**: Pattern visible on-chain; bond slashable if SSS equivocates.  
**Mitigation**: 
- Profile 4 (12-conf unsigned only) is immune.
- Bond slashing limits the SSS's downside.
- Bitcoin's chain-order property is the foundation — no conspiracy can rewrite history past finality.

**Residual risk**: P1/P2/P3 acceptance times are all exploitable. **Only P4 is conspiracy-safe.**  
**Affected profiles**: P1, P2, P3.

This is the worst-case adversarial model. The trust model was explicitly designed with this in mind — that's why Profile 4 exists.

### C5. SSS + Multiple Asset-Specific Conspiracies

**Actors**: SSS for asset A + SSS for asset B + senders for cross-asset attacks  
**Target**: Users doing cross-asset operations (swaps, perpetuals settlements)  
**Prerequisites**: Coordination across asset boundaries  
**Mechanism**: An atomic swap between asset A and asset B can be disrupted if both SSSs cooperate to favor one leg over the other.  
**Effect**: Cross-asset atomicity broken.  
**Detection**: Outcome of swap doesn't match agreement.  
**Mitigation**: 
- Cross-asset atomic protocols (HTLC-analogs) prevent the entire swap from completing if either leg fails.
- Force-exit gives each side independent withdrawal.

**Residual risk**: Cross-asset protocols are not in this document's scope. Significant residual risk pending detailed design.  
**Affected profiles**: All, on cross-asset operations.

### C6. SSS + Watcher — Suppressed Slashing

**Actors**: SSS + corrupt watcher network  
**Target**: Bond claimants  
**Prerequisites**: All watchers fail to publish a slashing proof when SSS equivocates  
**Mechanism**: SSS equivocates. Watchers know but stay silent (because they've been bribed, threatened, or are themselves the SSS).  
**Effect**: Victims unaware of equivocation until they observe it themselves. Bond may be partially or fully withdrawn (via timelock path) before victims claim.  
**Detection**: Anyone observing the chain can detect equivocation; corruption of all watchers requires consistent silence.  
**Mitigation**:
- Watchers are not a designated set — anyone observing the chain qualifies.
- Bond timelock should be long enough for victims to realize and claim.
- Open-source watchtower software encourages distributed monitoring.

**Residual risk**: Sophisticated attacker who controls a victim's information channels (eclipses them; controls their wallet UI) can delay their discovery of the equivocation. Combined with timelock, can succeed.  
**Affected profiles**: P1, P2, P3.

---

## Bond and Slashing Attacks

### B1. Bond Insufficiency vs Burst Equivocation

**Actor**: SSS equivocating on many high-value transactions simultaneously  
**Target**: Late claimants  
**Prerequisites**: Bond smaller than total damage from a burst attack  
**Mechanism**: SSS equivocates against many receivers in rapid sequence. Total damage > bond.  
**Effect**: First-claimants get paid; late ones get nothing.  
**Detection**: Bond utilization visible on-chain.  
**Mitigation**:
- **Bond sizing rule**: bond ≥ max realistic concurrent exposure.
- **Per-transaction caps**: SSS only signs transactions where the cumulative pending exposure remains under bond capacity.
- **Pro-rata distribution**: with a claim window, victims share the bond pro-rata rather than first-come.

**Residual risk**: If burst attack exceeds bond capacity, pro-rata distribution gives partial recovery only.  
**Affected profiles**: P1, P2, P3.

### B2. Bond Drainage via Slow Equivocation

**Actor**: SSS  
**Target**: The bond, ultimately new users  
**Prerequisites**: Bond contract that allows partial slashing  
**Mechanism**: SSS deliberately equivocates on small transactions repeatedly. Each event partially drains the bond. After many events, the bond is empty.  
**Effect**: New users have effectively no bond protection.  
**Detection**: On-chain visible (repeated slashing events).  
**Mitigation**:
- **Auto-pause**: bond contract triggers asset suspension after N slashings in a time window.
- **Bond top-up**: SSS must refill bond after slashing or asset is paused.

**Residual risk**: SSS may withdraw operational support entirely as bond drains. Effective denial of service for the asset.  
**Affected profiles**: All future users.

### B3. Slashing-Proof Race

**Actor**: Multiple watchers / victims competing for slashing payout  
**Target**: Each other  
**Prerequisites**: First-come bond payout structure  
**Mechanism**: When equivocation is detected, several parties race to publish the slashing proof first.  
**Effect**: 
- First-come: one party gets the bond, others get nothing.
- Pro-rata: parties cooperate but submission timing affects who's in the claim pool.

**Detection**: Visible on-chain.  
**Mitigation**:
- **Pro-rata distribution** with a long enough claim window for all victims to surface.
- **Public alerting** so all parties know to claim.

**Residual risk**: Sophistication asymmetry — well-watched parties claim, casual users miss out.  
**Affected profiles**: P1, P2, P3 victims of the equivocation event.

### B4. Bond Withdrawal Timelock Manipulation

**Actor**: SSS  
**Target**: Future victims  
**Prerequisites**: Bond's timelock is too short  
**Mechanism**: SSS lets timelock approach expiry without victims claiming. Once expired, SSS withdraws bond via the normal path.  
**Effect**: Bond is gone. Victims who didn't claim in time get nothing.  
**Detection**: On-chain visible — timelock progress is public.  
**Mitigation**:
- **Long timelock**: e.g., 90 days from last sign-related activity.
- **Re-arm on use**: each SSS signature resets the timelock, ensuring active operation keeps bond locked.
- **Watcher alerts**: notify users when timelock approaches expiry.

**Residual risk**: If user is offline / inattentive for the entire timelock period, they miss the window.  
**Affected profiles**: P1, P2, P3.

### B5. False Slashing Proof Construction

**Actor**: Malicious watcher  
**Target**: SSS (false accusation) or bond contract  
**Prerequisites**: Attacker constructs proofs that look like equivocation but aren't  
**Mechanism**: Submit a proof that the bond contract's script rejects → no payout. But possibly tarnishes SSS's reputation if proof is misinterpreted by users.  
**Effect**: At protocol level: nothing. Reputational damage if the proof is misunderstood.  
**Detection**: Script execution rejects fraudulent proofs.  
**Mitigation**: Public verification tools so any user can independently confirm or refute a claimed slashing proof.  
**Residual risk**: Reputational FUD. Mitigation is education and transparent verification.  
**Affected profiles**: All (informational, not financial).

### B6. Bond Compositional Attack (Multi-Asset)

**Actor**: SSS that operates multiple assets, attacking across them  
**Target**: One asset's users  
**Prerequisites**: SSS uses the same Bitcoin address for multiple assets' bonds (a sloppy implementation)  
**Mechanism**: Slashing on asset A's contract drains the bond, but asset B's contract believed the same UTXO covers it too.  
**Effect**: Asset B users discover their bond is gone.  
**Detection**: Implementation flaw; visible if anyone audits the bond UTXOs.  
**Mitigation**: **Each asset must have a separate, non-overlapping bond UTXO.** No bond sharing across assets.  
**Residual risk**: None if implemented correctly.  
**Affected profiles**: All on the affected asset.

---

## Force-Exit Attacks

### F1. Stale-State Force-Exit

**Actor**: A user with an old (higher-balance) state proof  
**Target**: The asset's overall accounting  
**Prerequisites**: User retained a valid state proof from an earlier higher-balance moment  
**Mechanism**: User initiates force-exit using the older proof, claiming higher than current balance.  
**Effect**: If SSS refutes correctly, attack fails. If SSS is unable to refute (offline, no current state proof), attack succeeds → over-claim.  
**Detection**: SSS's current state proof contradicts the claim.  
**Mitigation**: SSS publishes its latest commitment regularly; community can refute even if SSS is offline.  
**Residual risk**: Only if SSS is offline for the full challenge period AND no watcher refutes. Unlikely in practice.  
**Affected profiles**: All holders (asset-level disruption).

### F2. Force-Exit During Active SSS Rotation

**Actor**: Confused user, or attacker exploiting rotation timing  
**Target**: The system's consistency  
**Prerequisites**: SSS rotation is in progress (old SSS still recognized, new one pending)  
**Mechanism**: User initiates force-exit against the old SSS, while the new SSS believes itself authoritative.  
**Effect**: Ambiguity. Depends on rotation protocol semantics.  
**Detection**: Force-exit and rotation inscriptions both visible.  
**Mitigation**: **Rotation cutoff block** must be precisely defined; force-exits before that block are bound to old SSS, after to new SSS.  
**Residual risk**: Edge case at cutoff boundary; needs careful spec.  
**Affected profiles**: Users active during rotation.

### F3. Force-Exit Spam (Cost Attack on SSS)

**Actor**: Adversary willing to spend Bitcoin fees  
**Target**: SSS operational capacity  
**Prerequisites**: Cheap fees, account states allowing valid force-exit claims  
**Mechanism**: Submit many force-exit claims simultaneously, requiring SSS to refute each.  
**Effect**: SSS operational load spike; if SSS is overwhelmed, legitimate exits are slowed or fraudulent ones succeed.  
**Detection**: Visible on-chain.  
**Mitigation**: Force-exit claims must require a bond by the claimant (refunded if legitimate). Bond × N spam attempts has an upper cost.  
**Residual risk**: Cost-based DoS only; bonded claims make it expensive.  
**Affected profiles**: All (operational impact).

### F4. Force-Exit Front-Running by SSS

**Actor**: SSS  
**Target**: A force-exiting user  
**Prerequisites**: SSS sees pending force-exit submission  
**Mechanism**: SSS preemptively publishes a refutation (signing a fresh state that contradicts the claim) even if the user's claim was correct.  
**Effect**: Legitimate force-exit blocked. User must re-claim with updated state, possibly indefinitely if SSS continues.  
**Detection**: Pattern of SSS always refuting, even legitimate claims.  
**Mitigation**:
- Force-exit claim should reference the **highest known state** of the user. SSS can only refute by signing a higher state — which it might not have the user's signature for.
- If SSS persistently refutes by fabricating fake states, those states lack the user's signature; they're invalid.

**Residual risk**: This collapses to "SSS refuses to acknowledge user's state," which then fails force-exit but the user's force-exit attempt itself remains valid. Eventually SSS misbehavior is provable; bond slashable.  
**Affected profiles**: Affected user.

### F5. Force-Exit + Reorg Manipulation

**Actor**: Adversary with mining influence  
**Target**: A force-exit user  
**Prerequisites**: Force-exit inscribed; adversary controls upcoming blocks within the challenge period  
**Mechanism**: Adversary reorganizes blocks to remove the force-exit inscription, then claims the challenge period expired.  
**Effect**: User's force-exit invalidated.  
**Detection**: Reorg visible.  
**Mitigation**:
- Challenge period should be measured in confirmations of the force-exit inscription, not in absolute time. Reorgs reset the timer.
- 144-block (1 day) challenge period exceeds normal reorg depth significantly.

**Residual risk**: For very deep reorgs (>144 blocks), all bets are off; but such reorgs would break Bitcoin itself.  
**Affected profiles**: Force-exiting user.

### F6. Force-Exit Through Compromised User Wallet

**Actor**: Attacker who has compromised user's wallet  
**Target**: The user's funds  
**Prerequisites**: Wallet compromise, including access to account key  
**Mechanism**: Attacker initiates force-exit, redirecting funds to attacker's Bitcoin address.  
**Effect**: User's funds stolen.  
**Detection**: User sees unauthorized force-exit.  
**Mitigation**: 
- Wallet security is the user's responsibility.
- Multi-sig accounts (where supported) reduce risk.
- 2FA / hardware-key support in wallet.

**Residual risk**: Compromised wallets are out-of-protocol. Mitigations are user-side.  
**Affected profiles**: Compromised user.

---

## Economic Attacks

### E1. Pump-and-Dump on Newly Minted Asset

**Actor**: Asset issuer + accomplices  
**Target**: Speculative buyers  
**Prerequisites**: Newly minted asset with no track record; marketing capability  
**Mechanism**: Issuer mints an asset, allocates large portion to themselves/accomplices, promotes it, sells at inflated prices.  
**Effect**: Buyers lose money. Standard rug-pull pattern.  
**Detection**: Insider allocations visible if tokenomics is transparent. Some assets allow hidden distributions (Shielded mode).  
**Mitigation**:
- Disclosure norms (not protocol-enforced).
- Initial supply visibility (mandatory for fungible assets via the protocol's supply tracking).

**Residual risk**: Buyers can be deceived if they don't inspect tokenomics. Standard crypto risk.  
**Affected profiles**: All (general speculative risk).

### E2. Bond Front-Running on Asset Reputation

**Actor**: An attacker who deliberately reduces an asset's bond to harm its reputation  
**Target**: Asset users  
**Prerequisites**: Attacker can trigger lots of small slashings (perhaps with sender accomplices) without losing too much  
**Mechanism**: Force the SSS into many small equivocations or other slashing events, draining the bond and signaling to the market that the asset is risky.  
**Effect**: Asset users lose confidence; sell. Attacker may profit from short-selling or from migrating users to a competing asset.  
**Detection**: Slashing pattern public.  
**Mitigation**:
- Bond refill requirements (asset paused until refilled).
- Transparent narration of slashing events ("this was a test attack, not real misbehavior").

**Residual risk**: Market psychology is hard to engineer against.  
**Affected profiles**: All asset holders.

### E3. Liquidity-Lock Asset Drainage

**Actor**: SSS (as issuer) who has captured user deposits in a wrapped asset  
**Target**: All holders of the wrapped asset  
**Prerequisites**: Wrapped Bitcoin variant where users have deposited real BTC to back the wrapped supply  
**Mechanism**: SSS refuses redemptions, then absconds with the backing BTC.  
**Effect**: Wrapped asset becomes worthless; users lose their backing BTC.  
**Detection**: Pattern of refused redemptions; eventual on-chain visibility of BTC movement.  
**Mitigation**:
- Backing should not be held by the SSS alone. Use BitVM2-style permissionless bridge or multi-sig federation.
- Force-exit should attempt to release backing.

**Residual risk**: Custody trust is fundamental. Any wrapped-asset model has this risk unless the bridge is truly trust-minimized (BitVM2 with permissionless verification).  
**Affected profiles**: All holders of the wrapped asset.

### E4. Insurance Fund Drain (Perpetuals)

**Actor**: Adversary creating losing positions  
**Target**: The perpetuals venue's insurance fund  
**Prerequisites**: Ability to take large losing positions; ability to default before liquidation completes  
**Mechanism**: Take maximum-leverage positions, lose them faster than liquidation can recover margin, default to insurance fund.  
**Effect**: Insurance fund drained; subsequent legitimate losses go to ADL.  
**Detection**: Pattern of large defaults visible.  
**Mitigation**:
- Liquidation triggers earlier (initial margin threshold > maintenance margin).
- Insurance fund top-up from trading fees ensures continuous accrual.
- Bond slashing on the venue operator if insurance is depleted and ADL is triggered.

**Residual risk**: Tail events (extreme market moves) can deplete insurance faster than fees replenish.  
**Affected profiles**: Counterparties in ADL events.

### E5. Oracle Manipulation Attack

**Actor**: Adversary with influence over external price feeds  
**Target**: Perpetuals venue users  
**Prerequisites**: Influence over enough oracle sources to move the mark price  
**Mechanism**: Briefly manipulate an external exchange to trigger liquidations at unfair prices.  
**Effect**: Users on losing side of the false price are liquidated. Manipulator can profit from positioning on the winning side.  
**Detection**: Price discrepancy between venue mark price and other markets becomes visible.  
**Mitigation**:
- Multi-source oracles (median of N exchanges).
- Time-averaged prices (e.g., 5-minute TWAP) to dampen brief manipulation.
- Maximum-move clamps per epoch.

**Residual risk**: Coordinated manipulation across all upstream sources cannot be prevented at the venue layer.  
**Affected profiles**: All trading users.

### E6. Fee Spike During Venue Settlement

**Actor**: Adversary willing to spike Bitcoin fees  
**Target**: Venue operator + users  
**Prerequisites**: Capital to flood Bitcoin mempool with high-fee transactions  
**Mechanism**: Spike fees to make venue's batch inscription uneconomic, forcing settlement delays.  
**Effect**: Soft-finality times extended; user experience degraded. Potentially exploits force-exit timing.  
**Detection**: Fee market visibility; spike pattern obvious.  
**Mitigation**:
- Operator maintains fee reserve sufficient for spike conditions.
- Batch inscription can be deferred (with explicit user-facing soft-final indicator) during spikes.

**Residual risk**: Sustained fee-spike attacks could be economically motivated by competitors but require sustained large capital.  
**Affected profiles**: All venue users.

---

## Privacy Attacks

### P1. Transaction Graph Reconstruction from SSS

**Actor**: SSS or anyone who obtains SSS logs  
**Target**: All asset users  
**Prerequisites**: Access to SSS logs (insider, hack, subpoena)  
**Mechanism**: SSS records all transactions it sees. The records reveal sender, receiver, and amount for every transaction in the asset.  
**Effect**: Complete loss of privacy for that asset.  
**Detection**: Only if logs are exposed publicly.  
**Mitigation**:
- Use Mode A assets (no SSS) for privacy-critical transfers.
- Blind-signature SSS protocols (research).
- Asset segmentation across multiple SSSs.

**Residual risk**: Substantial. The cost of using SSS-mediated transactions is reduced privacy vs. the SSS.  
**Affected profiles**: All (privacy, not financial).

### P2. Timing Correlation Attack

**Actor**: Network observer  
**Target**: Specific user  
**Prerequisites**: Visibility of when transactions are submitted to SSS and when they appear on-chain  
**Mechanism**: Correlate submission timing with on-chain timing to deduce who submitted what.  
**Effect**: Privacy degradation: link account to submission patterns.  
**Detection**: Pattern-based, hard to detect from one transaction.  
**Mitigation**:
- Random submission delays.
- Anonymous channels (Tor) for SSS submissions.
- Batching from the SSS side smooths timing.

**Residual risk**: Network-level adversaries with sufficient observation can correlate.  
**Affected profiles**: All (privacy).

### P3. Account-Identification via Withdrawal Patterns

**Actor**: Observer (on-chain or off-chain)  
**Target**: Specific user  
**Prerequisites**: Ability to observe withdrawal flow patterns  
**Mechanism**: User behavior creates fingerprints — typical withdrawal sizes, timing, downstream wallets — that link their zkCoins activity to their identity.  
**Effect**: De-anonymization.  
**Detection**: User-level audit; statistical.  
**Mitigation**:
- Withdrawal frequency normalization.
- Use of mixing services downstream.
- Patterns of randomized waiting times.

**Residual risk**: Chain analysis is advanced; aggregate patterns are hard to fully obscure.  
**Affected profiles**: All (privacy).

### P4. Side-Channel Attack on SSS Process

**Actor**: Hardware or co-located adversary  
**Target**: SSS process  
**Prerequisites**: Co-location with SSS hardware (cloud-shared neighbor, etc.) or supply-chain access  
**Mechanism**: Extract signing key via side-channels (cache timing, power analysis, etc.).  
**Effect**: Once key is extracted, attacker can sign anything as SSS. Equivalent to X10.  
**Detection**: Same as X10 (erratic SSS behavior).  
**Mitigation**: 
- HSM for SSS key.
- Dedicated hardware, no co-tenancy.
- Side-channel-resistant implementations.

**Residual risk**: Side-channel attacks are an active research area; not all are easily mitigated.  
**Affected profiles**: All (catastrophic if successful).

### P5. Receiver-Side Account Linking via Off-Chain Coin Data

**Actor**: A receiver who receives multiple transactions from different senders  
**Target**: Senders' privacy  
**Prerequisites**: Standard receiver capability + off-chain coin data from multiple sources  
**Mechanism**: Receiver compares coin proofs from different senders. The proofs may contain elements that reveal sender identity (e.g., consistent account-state-hash patterns).  
**Effect**: Senders' privacy degraded vs. the receiver.  
**Detection**: Hard.  
**Mitigation**:
- Account-state hashing should not reveal anything beyond validity. The ZK proof should be zero-knowledge in the strict sense.
- Periodic account-state randomization.

**Residual risk**: Cryptographic correctness of the ZK proof matters here. A flawed proof system leaks; a correct one doesn't.  
**Affected profiles**: All senders.

---

## Network and Software Attacks

### N1. Eclipse Attack on Receiver's Wallet

**Actor**: Network adversary  
**Target**: Receiver wallet  
**Prerequisites**: Control over victim's network peers  
**Mechanism**: Feed victim's wallet a manipulated view of the chain (e.g., excluding competing transactions).  
**Effect**: Victim accepts a transaction that has been or will be reversed in the real chain.  
**Detection**: If victim queries multiple sources, mismatch is visible.  
**Mitigation**:
- Wallets should connect to multiple independent node providers.
- Use TLS-pinned reliable Bitcoin RPC endpoints.

**Residual risk**: Sophisticated eclipses can be elaborate; user diligence matters.  
**Affected profiles**: All (especially P1/P2/P3 with shorter wait times).

### N2. DNS / TLS Hijack of SSS Endpoint

**Actor**: Network adversary, possibly state-level  
**Target**: Users submitting transactions to SSS  
**Prerequisites**: Control over DNS or TLS infrastructure for the SSS's endpoint  
**Mechanism**: Redirect user submissions to attacker-controlled endpoint that records or modifies them.  
**Effect**: Privacy loss; possible substitution attacks.  
**Detection**: TLS certificate mismatch (if user checks).  
**Mitigation**:
- Certificate pinning in wallet.
- Tor / onion addresses for SSS endpoint.
- Out-of-band publication of SSS's public key for direct signature verification.

**Residual risk**: User-side diligence required.  
**Affected profiles**: All users of the affected SSS endpoint.

### N3. Wallet Software Backdoor

**Actor**: Compromised wallet developer or supply-chain attacker  
**Target**: Wallet users  
**Prerequisites**: Distribution channel for malicious wallet software  
**Mechanism**: Wallet sends user's key to attacker, or forges transactions in user's name.  
**Effect**: Catastrophic for affected users.  
**Detection**: Forensic analysis after the fact; difficult during.  
**Mitigation**:
- Open-source wallets with reproducible builds.
- Hardware key storage (transactions signed in hardware).
- Multi-source verification of wallet binaries.

**Residual risk**: Significant. Wallet supply chain is a perennial concern in crypto.  
**Affected profiles**: All using the affected wallet.

### N4. SSS Server Compromise

**Actor**: Attacker who has compromised SSS infrastructure  
**Target**: All asset users  
**Prerequisites**: Server-side breach (vulnerability, insider, side-channel)  
**Mechanism**: Same as X10. Full SSS authority in attacker's hands.  
**Effect**: Catastrophic.  
**Detection**: Same as X10.  
**Mitigation**: Same as X10.  
**Residual risk**: Operational security is hard.  
**Affected profiles**: All.

### N5. Replay Attack at Application Layer

**Actor**: Attacker observing an off-chain coin delivery  
**Target**: Receiver  
**Prerequisites**: Intercept the off-chain message containing coin + proof  
**Mechanism**: Attacker replays the message to multiple recipients, hoping one of them accepts.  
**Effect**: Each recipient verifies the proof; only the legitimately intended recipient can spend (because the coin specifies the recipient address). Attack fails at protocol level.  
**Detection**: Trivial; the coin includes the recipient identifier.  
**Mitigation**: Cryptographic — built into the proof.  
**Residual risk**: None.  
**Affected profiles**: None.

### N6. Malicious Browser Extension

**Actor**: Distributor of malicious extension that hooks the wallet  
**Target**: Wallet users  
**Prerequisites**: User installs extension  
**Mechanism**: Extension monitors and modifies wallet transactions before signing.  
**Effect**: Equivalent to N3 — full wallet compromise.  
**Detection**: Difficult.  
**Mitigation**:
- Wallet UI should use isolated/sandboxed environments.
- User education re: extension hygiene.

**Residual risk**: Significant; user-side concern.  
**Affected profiles**: Compromised users.

---

## Cross-Asset Attacks

### XA1. Failed Atomic Swap

**Actors**: Two SSSs (asset A, asset B) potentially uncoordinated or hostile  
**Target**: Users attempting a cross-asset swap  
**Prerequisites**: Cross-asset swap protocol in use  
**Mechanism**: One leg of the swap commits, the other does not.  
**Effect**: User's asset A is locked or transferred; asset B is not received. Partial state.  
**Detection**: Visible to the user trying to swap.  
**Mitigation**: HTLC-analog protocol requires atomicity (both succeed or both fail).  
**Residual risk**: Cross-asset protocols are out of this document's scope; specifications are pending.  
**Affected profiles**: All cross-asset users.

### XA2. Cross-Asset Replay

**Actor**: Adversary observing both assets' transaction streams  
**Target**: Users doing related transactions across assets  
**Prerequisites**: Same account-key pattern reused across assets  
**Mechanism**: Replay a transaction-like message in a different asset's context.  
**Effect**: If implementations are loose, an asset-A transaction could be accidentally accepted on asset B.  
**Detection**: Misimplementation; not a fundamental protocol issue.  
**Mitigation**: Each asset's transactions must include the asset_id in the signed message. Cross-asset replay becomes infeasible.  
**Residual risk**: None with correct implementation.  
**Affected profiles**: None.

### XA3. Asset Issuance Spam / Squatting

**Actor**: Anyone  
**Target**: Asset namespace, asset discoverability  
**Prerequisites**: Cheap asset creation  
**Mechanism**: Mint many assets with confusingly similar names or fake metadata to confuse users.  
**Effect**: Users may accidentally use the wrong asset.  
**Detection**: Visible on-chain.  
**Mitigation**:
- Asset namespace is just the asset_id (hash); no human-readable namespace conflict at protocol level.
- Wallets and explorers should help users identify the canonical asset (perhaps via reputation, registration, etc.).

**Residual risk**: User confusion. UX/social problem, not protocol.  
**Affected profiles**: Confused users.

---

## Attack Matrix

Summary of which trust profiles are vulnerable to each attack class.

| Attack Class | P1 | P2 | P3 | P4 | Bond | Notes |
|---|:-:|:-:|:-:|:-:|:-:|---|
| Simple sender double-spend | ✓ safe | ✓ safe | ✓ safe | ✓ safe | n/a | SSS state-tracks |
| Sender equivocation (parallel paths) | **vuln** | **vuln** | **vuln** | safe | optional | P4 + 12 confs needed |
| Sender + miner bypass | **vuln** | **vuln** | **vuln** | safe | optional | Same as above |
| Replay | safe | safe | safe | safe | n/a | Nullifier prevents |
| SSS equivocation | **vuln** | **vuln** | **vuln** | safe | **active** | Slashing triggers |
| SSS late-sign attack | **vuln** | **vuln** | **vuln** | safe | partial | P4 at 12 confs |
| SSS censorship | UX | UX | UX | UX | n/a | Native broadcast fallback |
| SSS+miner conspiracy | **vuln** | **vuln** | **vuln** | safe | partial | P4 only safe |
| Bitcoin reorg <6 blocks | partial | safe | safe | safe | n/a | 6-conf threshold |
| Bitcoin reorg ≥6 blocks | **vuln** | **vuln** | **vuln** | **vuln** | n/a | Bitcoin broken |
| Eclipse attack | **vuln** | partial | partial | partial | n/a | Wallet hygiene |
| Force-exit spam | UX-wide | UX-wide | UX-wide | UX-wide | n/a | Bonded claims |
| Stale state force-exit | safe* | safe* | safe* | safe* | n/a | If SSS or watcher refutes |
| Bond insufficiency | partial | partial | partial | safe | **affected** | Need pro-rata + sizing |
| Slashing race | partial | partial | partial | safe | **affected** | Need claim window |
| Oracle manipulation | n/a | n/a | n/a | n/a | n/a | Perpetuals only |
| Insurance fund drain | n/a | n/a | n/a | n/a | partial | Perpetuals only |
| Privacy vs SSS | **vuln** | **vuln** | **vuln** | **vuln** | n/a | Use Mode A for privacy |
| Wallet compromise | catastrophic | catastrophic | catastrophic | catastrophic | n/a | User-side concern |

Legend:
- ✓ safe = no exposure
- vuln = vulnerable
- UX = user experience degradation but no funds loss
- partial = partial protection
- catastrophic = total loss if attack succeeds
- n/a = attack not applicable to this profile

**The only profile immune to active SSS adversarial behavior is Profile 4.**

---

## Residual Risks

After all mitigations are applied, the following risks remain inherent to the design:

### Cryptographic-Foundation Risks

- Break of secp256k1 / Schnorr / SP1 / hash functions
- Mathematical advance in cryptanalysis
- Quantum computer with sufficient capability

These are existential to all of Bitcoin and most modern crypto. No system on this foundation is immune.

### Bitcoin-Layer Risks

- ≥50% hashrate attacks on Bitcoin
- Extreme reorgs (>12 blocks)
- Catastrophic Bitcoin consensus failure

zkCoins inherits Bitcoin's tail risks fully.

### Economic-Security Risks

- Bond sizes inadequate to cover burst exposure
- Total system exposure (sum of all bonds) exceeded by sophisticated coordinated attack
- Market manipulation of bonds themselves

Mitigations require dynamic bond management and conservative sizing.

### Operational-Security Risks

- SSS key compromise
- Wallet software compromise
- Infrastructure breach

Mitigations require dedicated security practices (HSM, multi-sig, audits) that go beyond protocol design.

### Privacy Risks vs SSS

- The SSS always sees its asset's transactions
- Mitigations (blind signatures, multi-SSS rotation) are partial and impose UX costs

The only complete privacy solution is Mode A (no SSS) with 6-conf finality.

### Out-of-Protocol Risks

- Social engineering
- Physical coercion
- Legal compulsion (subpoena of SSS logs, key seizure)
- Regulatory force-disable of SSS operator

These cannot be addressed at the protocol level.

### Cross-Asset Operations

- Cross-asset atomic operations are not yet specified
- Cross-asset swaps, perpetuals settlements crossing collateral assets, etc. all have residual unspecified-protocol risk

This is the most significant open design space.

---

## Recommendations

Based on this threat model:

1. **Profile 4 should be the default for high-value transfers.** Wallet UX should prominently flag when accepting at P1/P2/P3 acceptance threshold for transfers above a configurable amount.

2. **Bond sizes must be conservative.** Rule of thumb: bond ≥ 5× the maximum realistic single-event exposure for the asset. Periodic re-calibration as the asset's typical transaction values evolve.

3. **Slashing must be pro-rata with a sufficient claim window.** First-come is exploitable; pro-rata distributes fairly across affected parties.

4. **Watchtower software should be open-source and widely deployed.** The bond's effectiveness depends on equivocation being publicly detected.

5. **Multi-sig SSS is recommended for high-value assets.** A 2-of-3 SSS with operationally-separate keys reduces key-compromise risk significantly.

6. **Mode A assets exist for a reason.** For maximum privacy or for users who cannot accept any SSS-trust assumption, Mode A is the answer. Don't try to engineer Mode B to do everything.

7. **Cross-asset atomic protocol specification is the top open priority.** Most application-level attacks (perpetuals, DeFi, swaps) are cross-asset. The current single-asset trust model does not address them.

8. **Force-exit must be tested at scale before mainnet.** The challenge-period dynamics, claim mechanics, and SSS-refutation paths need adversarial testing on testnet for several months minimum.

9. **Public transparency of slashing events.** When equivocation is detected, full transparency about what happened, what the bond paid out, and how to prevent recurrence is essential for trust.

10. **Profile 4 should be available without performance penalty as much as possible.** Wallet UX should make it easy to opt into 12-conf wait without forcing users into "wait 60 minutes" UI patterns.

---

## Glossary

| Term | Meaning |
|---|---|
| **Threat actor** | An adversary attempting to exploit the protocol |
| **Attack vector** | A specific class of attack technique |
| **Prerequisite** | What an adversary needs to execute the attack |
| **Effect** | What the adversary gains or what the victim loses |
| **Detection** | How / whether the attack is observable |
| **Mitigation** | Protocol mechanisms that reduce or prevent the attack |
| **Residual risk** | What remains exploitable even with mitigations |
| **Profile** | Receiver trust profile P1, P2, P3, or P4 from `sss-trust-model.md` |
| **Slashing** | Forfeiture of an actor's bond as penalty for misbehavior |
| **Conspiracy** | Coordinated attack by multiple actors |
| **Equivocation** | Producing two valid signatures over conflicting messages from the same key |
| **Force-exit** | Holder's unilateral on-chain withdrawal when SSS unresponsive |
| **HTLC** | Hashed Time-Locked Contract — atomic-swap primitive |
| **ADL** | Auto-deleveraging — forced position closure when insurance fund depleted |
| **Eclipse** | Network-level attack isolating victim from honest peers |
| **HSM** | Hardware Security Module — dedicated cryptographic key storage device |
