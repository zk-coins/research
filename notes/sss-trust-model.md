# SSS Trust Model — Finality and Validity Hierarchy

> Draft | 2026-05-11 | Comprehensive reference
>
> The full trust and finality model for the zkCoins L2 protocol, centered on the optional **Single Signer Server (SSS)** per asset.

This document specifies the rules governing transaction acceptance, conflict resolution, and finality, with worked examples for every meaningful variant. It assumes the reader is familiar with [`l2-protocol-design.md`](l2-protocol-design.md).

---

## Table of Contents

1. [TL;DR](#tldr)
2. [Why This Model Is Coherent](#why-this-model-is-coherent)
3. [Core Concepts](#core-concepts)
4. [Asset Modes](#asset-modes)
5. [The Validity Hierarchy](#the-validity-hierarchy)
6. [Receiver Trust Profiles](#receiver-trust-profiles)
7. [What Each Actor Can and Cannot Do](#what-each-actor-can-and-cannot-do)
8. [Comprehensive Worked Examples](#comprehensive-worked-examples)
9. [Edge Cases and Variant Resolution](#edge-cases-and-variant-resolution)
10. [Interaction with Bonds and Slashing](#interaction-with-bonds-and-slashing)
11. [Interaction with Mode A Assets](#interaction-with-mode-a-assets)
12. [Properties Summary](#properties-summary)
13. [Open Questions](#open-questions)
14. [Glossary](#glossary)

---

## TL;DR

- Anyone can mint an asset in the zkCoins protocol. At creation, the asset's creator declares either an **SSS** (Single Signer Server) or no SSS.
- There is **no protocol-wide SSS**. Every asset is independent.
- An SSS signs a transaction only if no conflicting transaction exists from its perspective. It cannot reverse transactions, cannot custody funds, cannot affect other assets.
- A receiver chooses one of four **trust profiles** that determine when they consider an incoming transaction final.
- Conflicts between transactions are resolved by a strict **validity hierarchy**:
  ```
  12-conf unsigned   >   SSS-signed   >   6-conf unsigned   >   <6 conf
  ```
- If an SSS goes offline, the asset gracefully degrades to Mode A (6-conf finality, no soft-finality option).
- Profile 4 (anti-conspiracy paranoid) is the only profile cryptographically immune to active SSS+miner collusion.

---

## Why This Model Is Coherent

A trust model is internally consistent if and only if:

1. The conflict-resolution rules produce a single canonical outcome for every possible conflict.
2. The trust profiles correspond to clearly identifiable assumption sets.
3. The finality thresholds are monotonic in adversarial strength (more paranoid → longer wait).
4. The mode-A-only assets behave as a strict sub-case of mode-B assets.

This model satisfies all four:

| Property | How it's satisfied |
|---|---|
| Unique conflict outcome | Validity hierarchy is a total order. Same-tier conflicts fall back to Bitcoin block order (first inscription wins). |
| Clear assumption sets | Profiles 1–4 correspond to four distinct combinations of {SSS-trusted?, miners-trusted?, conspiracy-assumed?}. |
| Monotonic thresholds | 0 confs (P1) → 6 confs (P2/P3) → 12 confs (P4). Each adds a layer of adversarial robustness. |
| Mode A as sub-case | A Mode B asset with permanently absent SSS reduces to Mode A: only tiers (c)/(d) of the hierarchy can ever be reached. |

The model trades one property: it does **not** offer maximalist trustlessness with sub-confirmation finality. That combination is mathematically impossible on Bitcoin (see earlier analysis). What it offers is **layered, opt-in trust** — each receiver picks the trade-off they want.

---

## Core Concepts

### Asset Creation

Anyone can mint a new asset in the zkCoins protocol. At creation, the creator's choice is binary:

- **Declare an SSS**: a Bitcoin pubkey is bound to the asset as its single authorized signer.
- **Omit the SSS**: the asset has no signing oracle; it operates in pure Mode A.

This choice is recorded in the asset's genesis commitment and is **permanent** for that asset. A creator who wants to change SSS policy must mint a new asset.

### The Single Signer Server (SSS)

An SSS is a server program that performs exactly one function: given a candidate transaction for its asset, sign that transaction **if and only if** no conflicting transaction has been previously signed by this SSS for the same account state.

Key properties:

- An SSS is **per-asset**. There is no global SSS for the protocol.
- An SSS does not order transactions globally. Block order remains Bitcoin's responsibility.
- An SSS does not custody funds. The user's keys remain the user's keys.
- An SSS does not act on other assets, even if the same operator runs SSSs for many assets.
- An SSS can refuse to sign (censorship); it cannot force a transaction to happen.

### What "Signed" Means

An SSS signature attests:

> *"From the SSS's perspective at the time of signing, no conflicting transaction has been signed for this account state."*

It does **not** attest:
- That the transaction will be inscribed on Bitcoin.
- That no conflicting transaction exists outside the SSS's view (e.g., a natively broadcasted competing transaction).
- That miners will include the inscription.

The signature gives the transaction tier (b) in the validity hierarchy. That tier loses to 12-conf unsigned (tier a) but beats anything weaker.

---

## Asset Modes

### Mode A — No SSS Defined

When the creator omits the SSS at genesis.

Behavior:
- All transactions are native broadcasts.
- Finality: 6 Bitcoin block confirmations of the inscription.
- Conflict resolution: first-in-order wins.
  - Different blocks: earlier block wins.
  - Same block: earlier inscription position within the block wins.

No tier (a)/(b) distinction exists for Mode A assets — only tier (c) (≥6 confs) and tier (d) (<6 confs). A Mode A transaction at tier (c) cannot be overturned by anything in the protocol; only a Bitcoin reorg can disturb it (and after 6 confs, Bitcoin reorgs are presumed impossible).

### Mode B — SSS Defined

When the creator declares an SSS at genesis.

Behavior:
- A transaction can take either path:
  - **Native broadcast**: identical to Mode A. The transaction has no SSS signature.
  - **SSS-mediated**: the sender submits to the SSS, the SSS signs, the inscription is published with the SSS signature attached.
- Both paths produce inscriptions of the same on-chain footprint (one nullifier plus optional signature bytes).
- All four tiers of the validity hierarchy are reachable.

### SSS Outage Behavior (Mode B)

If the SSS is unavailable (offline, refusing, bonds exhausted, key rotation in progress):
- Senders fall back to native broadcast.
- Receivers fall back to Profile 2 or 3 (6 confs minimum).
- The asset continues to function with degraded UX, not with degraded security.

The asset's holders and the asset's accounting remain unaffected. The only thing lost is the sub-confirmation-finality convenience.

---

## The Validity Hierarchy

This is the protocol's authoritative rule for resolving conflicts between two transactions claiming to spend the same account state.

```
Tier (a)   12-conf unsigned   = strongest
Tier (b)   SSS-signed          (any conf depth, including 0)
Tier (c)   6-conf unsigned
Tier (d)   <6 conf unsigned   = weakest
```

### How a Conflict Is Resolved

Given two transactions T_X and T_Y for the same account state:

1. Determine the current tier of each.
2. The transaction at the higher tier is **canonical**. The other is **rejected by the protocol**.
3. If both are at the same tier, resolve by Bitcoin block order: earlier inscription wins.

The tier is reassessed at every block boundary, because confirmation depth changes over time. A transaction can change tier:
- An unsigned transaction migrates (d) → (c) at 6 confs, (c) → (a) at 12 confs.
- An SSS signature is permanent on the transaction; it stays tier (b) regardless of confs.

### Why SSS-Signed Stays at Tier (b)

A natural question: shouldn't a 6-conf SSS-signed transaction be stronger than a fresh SSS-signed one?

Answer: the protocol intentionally keeps SSS-signed at tier (b) regardless of confs. The reason is that the **SSS signature itself** is what raises it above unsigned-at-6-confs. Adding confs doesn't change the basis of trust; it stays the same trust assumption. Conversely, tier (a) (12-conf unsigned) is a different basis (Bitcoin-only) that defeats SSS-signed by design.

This avoids ambiguity: there is no scenario where two SSS-signed transactions need to be ranked by conf depth. If two SSS signatures exist for the same account state, the SSS has equivocated, and that is a separate matter (slashing; see below).

### Worked Hierarchy Cases (Quick Reference)

| T_X tier | T_Y tier | Winner |
|---|---|---|
| (a) 12-conf unsigned | (b) SSS-signed | T_X |
| (a) 12-conf unsigned | (c) 6-conf unsigned | T_X |
| (a) | (a) | first-inscribed |
| (b) SSS-signed | (c) 6-conf unsigned | T_X |
| (b) | (b) | first-inscribed (SSS equivocation event) |
| (c) | (d) <6 conf | T_X |
| (c) | (c) | first-inscribed |

---

## Receiver Trust Profiles

Each receiver chooses a profile that reflects their assumptions about the world. The profile determines when they accept an incoming transaction.

### Profile 1 — Trust the SSS

**Assumptions:**
- The SSS is honest and reliable.
- The SSS will not equivocate.
- The SSS will not conspire with miners.

**Acceptance behavior:**
- An SSS-signed transaction is treated as **final from the moment the receiver verifies the signature**, even before any block confirmation.
- An unsigned transaction is accepted after 6 confs (P2/P3 fallback behavior).

**Use case:** Standard merchant or end-user UX on an asset whose SSS they have reason to trust (regulatory, reputational, or personal).

**Vulnerable to:** SSS equivocation, SSS+miner conspiracy, sender equivocation via parallel paths.

### Profile 2 — Distrust SSS, Trust Bitcoin

**Assumptions:**
- The SSS might be unreliable or refuse to sign for me.
- The SSS does not actively equivocate. (Important: this is **not** "the SSS is adversarial" — just "I don't depend on its signature for trust.")
- Miners are honest.

**Acceptance behavior:**
- Any transaction (signed or unsigned) is accepted after 6 confs of its inscription.
- The SSS signature has informational value (e.g., the transaction probably hasn't been challenged), but it is not the basis for acceptance.

**Use case:** Receivers who want Bitcoin-level security but are willing to wait. Common for medium-value transfers.

**Vulnerable to:** SSS equivocation paired with late SSS-sig attack (see example 5), sender equivocation via parallel paths.

### Profile 3 — Distrust SSS and Miners (Independent)

**Assumptions:**
- The SSS might be unreliable.
- Miners might be individually bribed.
- But: the SSS and the miners are not coordinating.

**Acceptance behavior:**
- Identical to Profile 2: 6 confs of any transaction.
- Bitcoin's standard reorg-resistance (no single pool achieves 6 consecutive blocks deliberately) is the basis of safety.

**Use case:** Receivers in adversarial markets where some bribery is presumed but no organized conspiracy is. The most common "real world" paranoid posture.

**Vulnerable to:** Same as Profile 2 — late SSS-sig attack, parallel-path equivocation.

### Profile 4 — Assume SSS+Miner Conspiracy

**Assumptions:**
- The SSS is actively adversarial and will equivocate at will.
- A subset of miners coordinates with the SSS to enable late SSS-signed transactions to displace earlier unsigned ones.
- No SSS signature can be trusted.

**Acceptance behavior:**
- SSS-signed transactions are **rejected** as a basis for trust. (The signature is informationally useless — a hostile SSS will sign anything.)
- Only the unsigned path is acceptable.
- Acceptance requires **12 confs** of the unsigned transaction, at which point it reaches tier (a) and is immune to any future tier-(b) competitor.

**Use case:** High-value transfers, settlement of disputes, paranoid market participants, regulatory finality requirements.

**Not vulnerable to:** any combination of SSS+miner adversarial behavior — short of Bitcoin itself being compromised.

### Profile Summary

| Profile | Trust SSS? | Trust miners? | Conspiracy? | SSS-signed accept | Unsigned accept |
|---|:-:|:-:|:-:|:-:|:-:|
| 1 | yes | yes | no | 0 confs | 6 confs |
| 2 | no (passive) | yes | no | 6 confs | 6 confs |
| 3 | no (passive) | partial | no | 6 confs | 6 confs |
| 4 | no (active) | no | yes | **rejected** | 12 confs |

"Trust SSS = no (passive)" means: the SSS is not used as a trust anchor, but the SSS is not assumed to actively cheat. "No (active)" means: assume the SSS is actively trying to defraud me.

---

## What Each Actor Can and Cannot Do

### The Sender (Account Holder)

**Can do:**
- Send via the SSS (SSS-mediated path).
- Send via native broadcast (bypass the SSS).
- Send via both simultaneously, with conflicting destinations → sender equivocation. The protocol does not prevent this; the hierarchy and bond/slashing system handle the consequences.
- Equivocate using their own account key. Two signatures of the same key over different messages are detectable. If the sender has a personal bond, this is slashable.

**Cannot do:**
- Forge an SSS signature (only the SSS holds that key).
- Reverse a transaction after it has reached tier (a).
- Spend without their own account key.

### The SSS

**Can do:**
- Sign a transaction (granting tier (b)).
- Refuse to sign (operational censorship).
- Equivocate by signing two conflicting transactions. This is cryptographically detectable on-chain and is the trigger for bond slashing.
- Go offline (asset reverts to Mode A behavior temporarily).
- Coordinate with miners to influence inscription order (the conspiracy scenario).

**Cannot do:**
- Custody user funds. The SSS holds no user keys.
- Sign on behalf of a user without the user's signature on the transaction. SSS signatures are added to user-signed transactions, not stand-alone.
- Affect any other asset (it operates only on the asset whose genesis declares it).
- Override Bitcoin's chain order. A tier (a) transaction will defeat any later SSS signature.

### The Miners

**Can do:**
- Include or exclude inscriptions in their blocks.
- Reorganize the chain up to their hash power (Bitcoin's standard reorg risk).
- Be bribed individually or coordinated by an SSS+miner conspiracy.

**Cannot do:**
- Reorder transactions retroactively beyond what their hash power allows.
- Forge signatures.
- Override the validity hierarchy. Even if miners produce a chain favorable to the SSS, the hierarchy's tier (a) > tier (b) rule still applies — 12-conf-unsigned defeats SSS-signed in any chain Bitcoin acknowledges.

### The Receiver

**Can do:**
- Choose any trust profile (1, 2, 3, or 4) per transaction.
- Switch profiles per asset (trust SSS A but not SSS B).
- Run their own SSS-shadow that observes the official SSS's behavior and flags equivocation.
- Reject a transaction even if it would be canonical (the hierarchy says what's valid; the receiver decides what they personally accept).

**Cannot do:**
- Change the canonical outcome. If T_X wins under the hierarchy, no receiver action changes that.

---

## Comprehensive Worked Examples

In every example below, blocks are numbered relative to Alice's first transaction. "Block N" is when the first relevant inscription appears. Each block contains relevant inscriptions; irrelevant ones are omitted.

### Example 1 — Happy Path, SSS-Mediated

Alice sends 0.1 of asset X to Bob via the SSS.

| Block | Event |
|---|---|
| N | T_AB inscription (SSS-signed) appears on-chain. |
| N | (Bob's wallet, P1) Verifies SSS signature → **accepts as final**. |
| N+6 | T_AB has 6 confs. Bob's wallet (P2/P3) accepts. |
| N+12 | T_AB has 12 confs. Tier (a). |

No conflict. Receiver wait times:
- P1: < 1 second after seeing signature.
- P2/P3: 60 minutes.
- P4: 120 minutes (and only because P4 rejects the SSS signature; if Alice's transaction had been native rather than SSS-signed, P4 would also accept at N+12).

### Example 2 — Happy Path, Native Broadcast

Alice sends 0.1 of asset X to Bob via native broadcast (no SSS).

| Block | Event |
|---|---|
| N | T_AB inscription (unsigned) appears. Tier (d). |
| N+6 | Tier (c). P2/P3 accept. |
| N+12 | Tier (a). P4 accepts. |

P1 falls back to P2 behavior here (since there's no SSS signature, P1's 0-conf rule doesn't apply).

### Example 3 — Alice Tries to Double-Spend via the SSS

Alice signs T_AB and submits to SSS. SSS signs T_AB.

Alice immediately tries to submit T_AC to the SSS (same account state, different destination).

| Block | Event |
|---|---|
| pre-N | SSS sees T_AC submission. Detects conflict (same account state as already-signed T_AB). **Refuses to sign.** |
| pre-N | Alice's T_AC remains unsigned. Alice could still natively broadcast it (see example 4). |
| N | T_AB inscribed. |

Bob's safety in this case is **unconditional**: there is no SSS-signed T_AC and never will be (unless the SSS equivocates).

### Example 4 — Alice Bypasses the SSS via Native Broadcast

Alice signs T_AB and submits to SSS. SSS signs.

Alice **also** natively broadcasts a conflicting T_AC to Carol (without involving the SSS).

Both inscriptions reach the chain.

| Block | T_AB status | T_AC status | Canonical (hierarchy) |
|---|---|---|---|
| N | SSS-signed in mempool | unsigned, in mempool | (no inscription yet) |
| N (inscribed) | tier (b) | tier (d) | T_AB |
| N+6 | tier (b) | tier (c) | T_AB |
| N+12 | tier (b) | tier (a) | **T_AC** |
| N+13 | tier (b) | tier (a) | T_AC |
| forever | tier (b) | tier (a) | T_AC |

Critical observation: the **canonical winner changes at block N+12**. Up until then, T_AB (SSS-signed) wins. From N+12 onward, T_AC (12-conf unsigned) wins, because tier (a) > tier (b).

Implication for each receiver profile:

| Profile | Bob (T_AB) accepts | Outcome |
|---|---|---|
| P1 | at block N, accepts. **Loses at N+12.** | Bob's funds reverted, T_AB invalid. |
| P2/P3 | at block N+6, accepts. **Loses at N+12.** | Bob's funds reverted. |
| P4 | rejects SSS-signed → doesn't accept T_AB at all. | Bob unaffected (didn't believe T_AB to begin with). |

For Carol (T_AC):

| Profile | Carol accepts | Outcome |
|---|---|---|
| P1 | sees no SSS-sig, falls back to P2 → 6 confs. **Accepts at N+6, but T_AB wins until N+12.** Then T_AC wins. | Carol's acceptance was premature; the canonical state at N+6 was T_AB. |
| P2/P3 | accepts at N+6, but **incorrect** until N+12. | Carol's wallet correctly waited for hierarchy resolution if she stayed paranoid. |
| P4 | accepts at N+12. **Permanently correct from N+12.** | Carol wins. |

**This is the core scenario where Profile 4 is the only safe profile.** Both Bob and Carol could be in trouble if they used P1/P2/P3.

This is also why this attack vector is called **sender equivocation via parallel paths**: the sender uses both the SSS path and the native path simultaneously, and the receivers cannot a-priori know which is canonical without waiting for tier (a).

### Example 5 — Late SSS-Sig Attack on Unsigned Transaction

Alice sends T_AB via native broadcast to Bob in block N.

At block N+8, Alice colludes with the SSS to publish a competing SSS-signed T_AC (same account state) for the attacker's account.

| Block | T_AB tier | T_AC tier | Canonical |
|---|---|---|---|
| N | (d) | — | T_AB |
| N+6 | (c) | — | T_AB |
| N+8 | (c) | — | T_AB |
| N+9 | (c) | (b) inscribed | **T_AC** |
| N+12 | (a) | (b) | T_AB again |

The flip at N+9 catches receivers in P2/P3 who accepted at N+6. The flip back at N+12 protects only P4.

This attack requires SSS cooperation (the SSS knowingly signs after-the-fact for a competing transaction). It is the classical SSS-equivocation use case → triggers slashing of the SSS bond if implemented (see *Interaction with Bonds and Slashing* below).

### Example 6 — SSS+Miner Conspiracy Against SSS-Signed Transaction

Alice sends T_AB via SSS to Bob. SSS signs honestly.

At block N, T_AB is inscribed. P1 Bob accepts.

The SSS+miner conspiracy then attempts to publish a competing T_AC (also SSS-signed, against Alice's wishes — only possible if the SSS goes rogue *after* signing T_AB).

| Block | T_AB tier | T_AC tier | Canonical |
|---|---|---|---|
| N | (b) | — | T_AB |
| N+1 | (b) | (b) competing, first-inscribed = T_AB | T_AB |
| ... | (b) | (b) | T_AB |
| N+12 (if T_AB unsigned could exist, alternative scenario) | — | — | — |

Both transactions sit at tier (b). The hierarchy resolves with first-inscribed = T_AB. Bob (P1) wins.

However, the SSS has equivocated (signed two conflicting transactions for the same account state). This is on-chain detectable. If a bond exists, the bond is slashed: the loser of the conflict (whoever received T_AC) plus any other affected parties can claim against the bond.

In **Profile 4** Bob would have rejected T_AB outright (no SSS-sig is trusted), so Bob would not have shipped goods on the basis of T_AB. P4 is insensitive to this attack.

### Example 7 — Sender Equivocation Targeting Both Paths

Alice attempts to defraud both Bob and Carol simultaneously. She arranges:
- Submits T_AB to SSS → SSS signs.
- Natively broadcasts T_AC.
- Bribes a miner to include T_AC in block N and exclude T_AB until block N+1.

| Block | T_AB status | T_AC status | Canonical |
|---|---|---|---|
| N | not inscribed | inscribed, tier (d) | T_AC |
| N+1 | inscribed, tier (b) | tier (d)→(d) | T_AB (b > d) |
| N+6 | (b) | (c) | T_AB |
| N+12 | (b) | (a) | **T_AC** |

Same outcome as example 4. Bob (any profile except P4) initially accepts T_AB after seeing SSS sig; gets reverted at N+12. Carol (P4 only) safely accepts at N+12.

The miner bribery here is a red herring — it changes which block they appear in but not the eventual canonical winner. The 12-conf rule wins out regardless.

### Example 8 — Honest SSS, Honest Miners, Many Senders

100 honest senders use asset X over an hour. Each makes a single SSS-mediated transaction. No conflicts arise.

| Block | Events |
|---|---|
| N | 50 inscriptions, all SSS-signed, all non-conflicting |
| N+1 | 50 more inscriptions, all SSS-signed, all non-conflicting |
| N+6 | All transactions in P2/P3 acceptance window |
| N+12 | All transactions at tier (a) |

P1 receivers experience sub-second finality. P2/P3 receivers wait 60 minutes. P4 receivers wait 120 minutes. All transactions are canonical from inception; nothing is reverted.

This is the **normal operation** of the asset. Examples 3–7 are pathological cases.

### Example 9 — SSS Outage

The SSS goes offline. Alice attempts to send T_AB via SSS, gets no response.

| Block | Action |
|---|---|
| pre-N | Alice's wallet times out on SSS submission. Falls back to native broadcast. |
| N | T_AB inscribed unsigned, tier (d) |
| N+6 | Tier (c). P2/P3 accept. |
| N+12 | Tier (a). P4 accepts. |

The asset functions normally, just in degraded UX. P1 receivers cannot get sub-confirmation finality during the outage but they don't lose access to the asset.

### Example 10 — SSS Slashing Cascade

SSS equivocates by signing two competing T_AB and T_AC (deliberately or due to bug).

| Block | Event |
|---|---|
| N | Both inscribed (same block or adjacent). |
| N+1 | Slashing watcher detects two SSS signatures of conflicting transactions on the same account state. |
| N+2 | Watcher publishes slashing-proof on Bitcoin. |
| N+3 | Bond UTXO is unlocked via the slashing path. |
| N+4 onwards | The losing-party receivers (Bob if T_AC won; Carol if T_AB won) submit claims against the unlocked bond. |
| ~ N+144 | Claims window closes. Bond distributed pro-rata (or first-come, per the bond contract). |

The SSS is functionally dead after this — its key is publicly proven untrustworthy. The asset effectively reverts to Mode A unless the asset's creator declares a new SSS via the SSS-rotation mechanism (see [`l2-protocol-design.md`](l2-protocol-design.md) §7.3).

---

## Edge Cases and Variant Resolution

### Edge Case A — Both Transactions Are SSS-Signed (Equivocation)

Two SSS-signed transactions T_X and T_Y exist for the same account state. Same tier (b).

**Resolution:** first-inscribed wins by Bitcoin block order. Specifically:
- Different blocks: earlier block.
- Same block: earlier index within the block.

**Side effect:** the SSS has cryptographically equivocated. Bond slashable. Asset reputation damaged.

### Edge Case B — Both Transactions Are 12-Conf Unsigned (Sender Equivocation, P4 Race)

Both T_X and T_Y reach tier (a) (12+ confs each).

**Resolution:** first-inscribed wins.

**Side effect:** the sender has equivocated using their own account key. Two signatures of the account key over different messages are produced. If the sender has a personal bond, the bond is slashable. (Personal sender bonds are an optional extension; not part of the base protocol.)

### Edge Case C — One Transaction Reaches Tier (a) While the Other Is at Tier (b) — Then the Tier-(b) Transaction Also Hypothetically Reaches Tier (a)

This **cannot happen.** A transaction either has an SSS signature or it doesn't. If signed, it stays tier (b) regardless of confs. There is no automatic promotion to tier (a) for SSS-signed transactions.

This is a design choice: it preserves the property that tier (a) is reserved for transactions whose validity does **not** depend on the SSS.

### Edge Case D — SSS Signs a Transaction, Then Refuses to Sign Later Transactions for the Same Account

Alice's first transaction T_1 is SSS-signed and inscribed. Alice then sends a non-conflicting follow-up T_2 from her new account state. SSS refuses.

**Resolution:** Alice falls back to native broadcast for T_2. The asset continues to function; only the soft-finality is unavailable for T_2.

### Edge Case E — The SSS Signs a Transaction That the User Did Not Submit

If the SSS were to fabricate a transaction (sign and inscribe without user authorization), the underlying user-signature would be missing. Any party validating the transaction would reject it as malformed — the SSS signature does not replace the user's account-key signature.

The SSS can only sign **on top of** a valid user-signed transaction. It has no authority to create transactions out of thin air.

### Edge Case F — Bitcoin Reorg Removes an SSS-Signed Inscription

A reorg of depth N removes T_AB (SSS-signed) from the canonical chain. T_AB returns to the mempool. The SSS signature is unchanged.

**Resolution:** T_AB can be re-inscribed in the new chain. The SSS signature remains valid. Receivers' confirmation counts reset; they must re-evaluate against the new chain depth.

If a competing T_AC was inscribed in the new chain (e.g., due to a malicious miner orchestrating the reorg), the hierarchy applies as usual: T_AB tier (b) vs T_AC tier (d)→(c)→(a) over the next 12 blocks.

### Edge Case G — Account Has Multiple Concurrent States Due to a Failed Sync

A user's wallet syncs from two sources that have not yet seen the same set of inscriptions. The user briefly perceives two valid states.

**Resolution:** the canonical state is determined entirely by the on-chain block order and the hierarchy. The wallet must resync to a consistent view before allowing the user to spend. This is a UX problem, not a protocol problem.

### Edge Case H — SSS Rotation Mid-Transaction

The asset's creator rotates the SSS key while transactions are in flight.

**Resolution:** the rotation inscription includes a cutoff block number. Signatures by the old SSS pubkey before the cutoff are valid; signatures after are not. Signatures by the new SSS pubkey are valid only from the cutoff onward.

The exact rotation protocol is specified in [`l2-protocol-design.md`](l2-protocol-design.md) §7.3.

### Edge Case I — Multiple Inscriptions in the Same Block, Same Account, Same Tier

Three SSS-signed conflicting transactions land in block N at positions 47, 52, 89. (Indicates multi-way SSS equivocation.)

**Resolution:** position-47 wins. Positions 52 and 89 are invalid. The SSS has performed multi-way equivocation, doubly slashable.

### Edge Case J — Bitcoin Block Boundary Coincides with a Receiver Decision

Bob (P2) sees T_AB at 5 confs and decides to defer acceptance to the next block. Between his check and the next block, a competing T_AC is inscribed.

**Resolution:** the hierarchy at the moment Bob actually accepts is what counts. If at the moment of acceptance T_AB has reached 6 confs but T_AC has appeared, the wallet must compare current tiers. If T_AC is SSS-signed and T_AB is unsigned at tier (c), T_AC wins (b > c). Bob should not accept.

Wallets must check the full hierarchy at the moment of acceptance, not just the conf count of their target transaction.

### Edge Case K — Two Independent SSSs for Two Different Assets, Cross-Asset Transaction

A swap between asset X (SSS_X) and asset Y (SSS_Y) requires coordination. Each SSS only signs for its own asset's leg of the swap.

**Resolution:** outside the scope of this document. See cross-asset atomic swap design in future spec (HTLC-analog).

---

## Interaction with Bonds and Slashing

The trust model and the bond/slashing mechanism are orthogonal but interdependent:

- The **hierarchy** determines what is canonical.
- The **bond** determines the economic cost to the SSS of equivocation.

The bond does not change finality. A transaction is canonical or not based purely on the hierarchy. The bond exists to make SSS misbehavior expensive.

### Bond Triggers

Slashing of the SSS bond is triggered by:

| Trigger | Description |
|---|---|
| SSS equivocation | Two valid SSS signatures over conflicting transactions for the same account state. |
| Failure to perform agreed action | (Future extension) e.g., SSS contracted to sign within N seconds and fails. Requires explicit SSS commitment to a service-level agreement. |
| Demonstrable conspiracy with miners | Hard to prove cryptographically without additional commitments. Reputational only, unless paired with an attestation protocol. |

### Slashing Outcomes

When slashed:
- The bond UTXO becomes spendable to claimants who present the slashing proof.
- Distribution follows the bond contract's rules (pro-rata across affected parties within a claim window; or first-come).
- The SSS's key becomes publicly distrusted. Wallets should mark the asset as "SSS-untrusted" in their UI.

### Profile 1 Safety Under Bonded SSS

Profile 1 is safe **conditional on** the bond being:
- Larger than the maximum loss from a single equivocation event.
- Cryptographically claimable by the affected party.
- Promptly enforceable.

If these conditions hold, Profile 1 becomes **economically rational**: the SSS has no incentive to equivocate because the cost exceeds any possible gain.

This is the same economic-security argument as Lightning channel penalty transactions: in theory the channel partner can publish an old state, but they would lose more than they gain by doing so, so they don't.

---

## Interaction with Mode A Assets

Mode A assets have no SSS. The validity hierarchy reduces to:

```
Tier (c)   6-conf unsigned   = strongest
Tier (d)   <6 conf unsigned  = weakest
```

(There is no SSS-signed transaction to be at tier (b), and tier (a) — defined as "12-conf unsigned that beats SSS-signed" — has no SSS-signed to beat, so it collapses into tier (c).)

All four trust profiles converge:
- P1: 6 confs (no SSS to trust).
- P2/P3: 6 confs (their normal behavior).
- P4: 6 confs (no SSS to assume conspiracy with — but the wallet may still wait 12 confs out of habit or as an extra safety margin; not required by protocol).

Mode A assets cannot achieve sub-confirmation finality. This is the design choice the creator made.

### Cross-Mode Transactions

A transaction in asset X (Mode A) and a transaction in asset Y (Mode B) do not interact. They have independent state and independent SSSs (or lack thereof). A cross-asset transaction is a separate, coordinated operation outside the scope of this document.

---

## Properties Summary

### What the Model Protects Against

| Threat | Protected by |
|---|---|
| Sender double-spend (one SSS-mediated, one re-attempt) | SSS refuses to sign the second |
| Sender double-spend (parallel paths) | Hierarchy at tier (a) defeats SSS-signed at tier (b); P4 safe at 12 confs |
| Honest miner reorg up to 5 blocks | 6 conf threshold (P2/P3) |
| Bribed miner without SSS collusion | 6 conf threshold (P2/P3) |
| SSS equivocation | Hierarchy resolves to first-inscribed; bond slashable |
| SSS+miner conspiracy | Hierarchy tier (a); P4 safe at 12 confs |
| Bitcoin-level reorg beyond 12 blocks | Not protected — Bitcoin itself broken |

### What the Model Trades Off

| Trade-off | Implication |
|---|---|
| Per-asset trust choice | Receivers must evaluate each asset's SSS individually; cannot rely on global trust |
| SSS-signed cannot reach tier (a) | Profile 4 must wait 12 confs even for SSS-signed transactions (effectively rejecting the SSS path) |
| Sender equivocation creates pre-final state changes | Wallets must show "soft-final, pending tier (a) resolution" for transactions in P2/P3 windows on Mode B assets |
| Bond size limits realistic transaction values | SSS-mediated path is only economically safe for transactions ≤ (bond / safety factor / expected concurrent exposure) |
| Privacy from the SSS | The SSS sees all transactions for its asset. Mitigations exist (blind signatures, multiple SSSs) but are out of scope |

### What the Model Does Not Provide

- Mathematical trustlessness with sub-confirmation finality. (Mathematically impossible on Bitcoin per the earlier analysis in this repository.)
- Cross-asset atomic operations. (Requires separate protocol design.)
- Privacy from the asset's SSS. (The SSS sees transaction graphs by necessity.)
- Resistance to Bitcoin-level attacks (51%+ hashrate). (Inherited limitation from Bitcoin itself.)

---

## Open Questions

1. **Concrete numeric calibration of 12.** The 12-conf figure follows from the symmetric-mirroring of "SSS-signed beats 6-conf unsigned." Is a more conservative ratio (e.g., 18 confs) warranted for high-value transactions? This is a parameter choice, not a structural one.

2. **SSS rotation atomicity.** When the asset's creator rotates the SSS key, transactions in flight at the cutoff block need carefully defined behavior. Specifically: what if the rotation inscription itself is in conflict with a transaction signed by the old SSS just before? See [`l2-protocol-design.md`](l2-protocol-design.md) §7.3 for the rotation protocol; this document defers the conflict-resolution details.

3. **Wallet UX for pre-tier-(a) acceptance.** A P2 wallet showing a transaction as "accepted" at 6 confs is technically vulnerable to a late SSS-sig attack. Should the wallet show this risk explicitly? At what threshold should the wallet warn the user?

4. **Bond distribution rules.** Pro-rata vs. first-come vs. hybrid. The current document references the bond contract but does not specify it. Needs formal Taproot script design.

5. **Sender personal bonds.** An optional protocol extension where senders themselves post bonds, slashable on sender equivocation. Would close the parallel-path equivocation vector at tier (a), but creates UX friction.

6. **Multiple competing SSSs for the same asset.** Currently each asset has at most one SSS. A future extension might allow a "marketplace of SSSs" where senders can choose which SSS to use for a given transaction, and receivers express preferences. This re-opens the multi-attestor coordination problem and is intentionally deferred.

7. **SSS-as-watchtower hybrid.** A passive SSS that does not sign but only flags equivocation attempts could provide a hybrid trust model. Not currently part of the spec.

---

## Glossary

| Term | Meaning |
|---|---|
| **SSS** | Single Signer Server. Per-asset signing oracle that attests non-conflict at signing time. |
| **Mode A** | Asset created without an SSS. 6-conf finality, first-in-order conflict resolution. |
| **Mode B** | Asset created with an SSS. Supports both native broadcast and SSS-mediated paths. |
| **Tier (a)** | Validity rank: 12-conf unsigned. Strongest. |
| **Tier (b)** | Validity rank: SSS-signed (any conf depth). |
| **Tier (c)** | Validity rank: 6-conf unsigned. |
| **Tier (d)** | Validity rank: <6 conf. Weakest. |
| **Validity hierarchy** | Total order over tiers, determining canonical conflict outcome. |
| **Trust profile** | A receiver's stated assumptions about the world (P1–P4). Determines acceptance threshold. |
| **Native broadcast** | A sender publishing their inscription without involving the SSS. |
| **SSS-mediated** | A sender submitting to the SSS; SSS signs and inscription is published with signature. |
| **Sender equivocation** | Sender produces two valid signatures from their account key for conflicting transactions. |
| **SSS equivocation** | The SSS produces two valid SSS-signatures over conflicting transactions for the same account state. |
| **Parallel-path equivocation** | A specific sender-equivocation pattern: SSS-signed via SSS plus native-broadcast in parallel, with conflicting destinations. |
| **Late SSS-sig attack** | An SSS-equivocation pattern where the second SSS signature is published well after the first transaction's inscription, exploiting the tier (b) > tier (c) rule. |
| **Conspiracy** | Active coordination between the SSS and one or more miners against a receiver. The model assumed only in Profile 4. |
| **Force-exit** | A holder's unilateral on-chain withdrawal mechanism if the SSS becomes unresponsive. See [`l2-protocol-design.md`](l2-protocol-design.md) §7. |
| **Bond** | A Bitcoin UTXO held by the SSS, slashable via on-chain proof of equivocation. See [`l2-protocol-design.md`](l2-protocol-design.md) §5. |
