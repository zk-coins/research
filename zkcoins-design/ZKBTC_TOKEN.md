# zkBTC — Permissionless Deposit-Backed Redeemable BTC on zkCoins (Optional Gatekeeper)

**Status:** Design specification. No code. A v3+ design (see maturity gate §4.0) — not a build order. Concretises the Glock-path decision of [`../bitvm-bridge-research.md`](../bitvm-bridge-research.md) (2026-06-06).

**Authoritative source for:** the zkBTC token standard (token standard 3, `issuance_version == 3`) and the zkBTC bridge profile (permissionless minting with optional gatekeeper quality control at peg-in; gatekeeper-independent peg-out).

**Audience:** protocol engineers and organisations evaluating zkBTC deployment (as minters, optional gatekeepers, or operators).

**Supersedes:**
- [`BRIDGE_MVP.md`](./BRIDGE_MVP.md) §4 / §6.3 (separate `IssuanceProof` / `BurnProof` ProofTypes and global `peg_in_consumed_smt` / `burned_coins_smt` — incompatible with the post-#97 nullifier model, with specification.md §6.5's version-branch dispatch, and with §2.2's single-circuit rule);
- the `IssuanceTerms_v2_glock_bridged` sketch in [`../bitvm-bridge-research.md`](../bitvm-bridge-research.md) (issuer-less, and `issuance_version == 2` is now the capped-supply standard in specification.md §6.5);
- the single-issuer framing of earlier drafts of this document (replaced by permissionless issuance with an optional mint gatekeeper — §1.1 REQ-3, §6).

**Note:** Written against zk-coins/docs `develop` @ e3b5d04 (post-#97 on-chain nullifier `(Pkᵢ, Rᵢ)`, half-aggregation, v1 freeze). Normative keywords (**MUST**, **MUST NOT**, **SHOULD**, **MAY**) follow RFC 2119.

---

## 1. Requirements and scope

### 1.1 Product requirements

| ID | Requirement |
|----|-------------|
| **REQ-1** | zkBTC is a zkCoins asset: an ordinary multi-asset coin under the protocol's `asset_id` model, verified by the same circuit `C` and nullifier accumulator as every other asset. |
| **REQ-2** | Free transfer: once minted, any holder **MAY** send zkBTC to any other address without gatekeeper permission, signature, or online cooperation. |
| **REQ-3** | **Permissionless issuance with an optional mint gatekeeper.** Anyone **MAY** create a zkBTC-style asset and act as a **minter**. An asset **MAY** designate a **gatekeeper** whose per-mint approval is mandatory; the gatekeeper does entry quality control **and is the canonical-chain anchor for mint settlement** (§3.2.1.1, §6.1), and represents the interests of the asset's existing holders. Minting economic activity and gatekeeping are separate roles. **A trust-minimized pooled zkBTC effectively REQUIRES a gatekeeper (or an equivalent canonical-oracle role)** (§5, §6.4); no-gatekeeper mode remains protocol-valid but is a **materially weaker** security class and **MUST NOT** be presented as trust-minimized backing. |
| **REQ-4** | **Gatekeeper-independent and operator-liveness-bounded redemption:** every holder **MUST** be able to redeem for on-chain BTC without the gatekeeper's permission or technical cooperation. Exit depends only on operator liveness (BitVM-family residual — §1.2, §4.3). (The gatekeeper's structural role is at **mint/entry** as quality filter + canonical-chain anchor — REQ-3 / R-04 — not at exit.) High minimum denominations and multi-week wait windows are acceptable for emergency exit. |

### 1.2 Honest impossibility statement

No currently deployed mechanism gives a fungible multi-holder BTC-backed token a pure third-party-free unilateral L1 exit the way a Lightning force-close or a statecoin backup does. Federated and threshold-signer pegs (Liquid, tBTC, sBTC, and similar) require a signer quorum to release BTC. BitVM-family bridges improve **safety** toward 1-of-N setup honesty with challenge games, but keep **withdrawal liveness** dependent on at least one rational operator who fronts funds. Statechains and Ark offer unilateral exit for discrete UTXO/VTXO claims, not for a free-transfer fungible multi-holder token. Covenant soft forks that would enable anyone-can-satisfy vault exits are not activated as of mid-2026.

REQ-4 as stated demands **gatekeeper-independence** (and, more generally, independence from any mint-time quality authority), which this design achieves: the gatekeeper has no role in peg-out. Full **counterparty-freeness** (zero live third parties other than Bitcoin) is not achievable for a fungible multi-holder token on today's Bitcoin; that residual needs covenant soft forks (§10). This document states that residual plainly rather than masking it.

### 1.3 Mechanism-class → unilateral-exit verdict

Compressed from the landscape matrix (research landscape report §3):

| Mechanism class | Unilateral exit (holder vs L1 vault) | Fit for REQ-4 |
|-----------------|--------------------------------------|---------------|
| BitVM2 / BitVM3 / Glock operator-fronted peg | **PARTIAL** — safety 1-of-N; liveness needs ≥1 operator | Best practical match today |
| Federated / threshold (Liquid, tBTC, sBTC, Spiderchain) | **NO** — quorum releases BTC | Out |
| Mercury statechains | **YES** per UTXO, not fungible multi-holder | Poor fungibility fit |
| Ark / Arkade VTXO | **YES** / **PARTIAL** while unexpired; expiry liveness | Secondary rail, not reserve |
| Lightning channels | **YES** for channel parties; **N/A** as multi-holder peg | Not a shared-reserve token |
| Covenant vaults (CTV / CSFS / OP_CAT) | **YES** (design-space) after activation | Long-term upgrade path |
| Custodial mints (Fedimint / Cashu) | **NO** | Contrast only |

Sources for the matrix and shortlist: landscape research report §1–§4; BitVM2 bridge paper at `https://bitvm.org/bitvm_bridge.pdf` and `https://bitvm.org/bitvm2`.

### 1.4 Scope boundaries

This document defines:

- the in-circuit token standard that makes mint and redeem statements machine-checkable;
- the off-circuit bridge profile that holds the BTC reserve and serves exits;
- the trust matrix, launch gates, gatekeeper/compliance model, and transitional naming lock;
- the covenant upgrade path as design optionality, not a delivery dependency.

This document does **not** define:

- operator runbooks, federation recruitment, or commercial SLAs beyond the transitional profile;
- concrete Plonky2 circuit gadgets (only the statements they must prove);
- mainnet parameter freezes (values marked `PROVISIONAL` until Glock-mainnet evidence);
- a roadmap sequencing commitment relative to zkCoins native-issuance work (ROADMAP treats a BTC peg as orthogonal).

### 1.5 Non-goals

- **No new v1 wire formats.** Token standard 3 lives on the v2 circuit surface (new digests, new lineages). The frozen v1 surface of specification.md §1.7.8 is not edited in place.
- **No peg-in/out L1-footprint privacy beyond §8.** Deposits and payouts are public Bitcoin events; internal transfers remain shielded.
- **No price or oracle logic.** zkBTC is a claim on BTC at 1:1 denomination amounts, not a synthetic or stablecoin with external price feeds.
- **No federation-multisig V0** and **no BitVM2 intermediate** as a product path (June-2026 decision; §4.0).
- **No claim of zero third-party dependency at exit.** REQ-4 is gatekeeper-independence and operator-liveness-bounded exit; operator liveness remains a residual (§4.3, §5).
- **No mandatory central mint authority at the protocol layer.** A gatekeeper is optional per asset (`gatekeeper = 0³²` is valid). When present, the gatekeeper is both an entry quality filter **and** the canonical-chain anchor for mint settlement (§3.2.1.1, §6.1). **Trust-minimized pooled backing effectively REQUIRES a gatekeeper (or equivalent canonical oracle)**; no-gatekeeper pooled mode is **materially weaker** and **MUST NOT** be marketed as trust-minimized (§5, §6.4).

---

## 2. Design summary

zkBTC has two normative halves:

1. **Token standard 3 (TS3)** — in-circuit rules inside the single PCD circuit `C` (`issuance_version == 3`). Every mint is bound to a unique confirmed **`MoveToBacked` transaction** that creates a **backing-only vault output** (N-of-N-authenticated, deep-finality, operator-set membership; no refund path on that output); every redeem is an ordinary holder transition that anchors a unique on-chain nullifier `(Pkᵢ, Rᵢ)` and a hiding `redeem_commitment`.
2. **zkBTC bridge profile** — off-circuit Glock-based (BitVM-family) construction that holds the BTC reserve. Peg-in is permissionless for minters, optionally gated by a per-asset gatekeeper that is both entry quality filter and **canonical-chain anchor** for mint settlement (REQ-3 / R-04). Peg-out is gatekeeper-independent (REQ-4), operator-fronted, with claim/challenge reimbursement.

Document order follows the advisor Q3 rule: token standard first (defines the statements), bridge second (consumes them). The bridge never invents a parallel mint/burn semantics; it only materialises Bitcoin custody around statements the circuit already enforces.

### 2.1 Roles (minter and optional gatekeeper)

Two mint-time roles are separated. They **MUST NOT** be conflated with a single central "issuer."

| Role | Function | Authority |
|------|----------|-----------|
| **Minter** | Economic actor: locks BTC (for zkBTC), obtains a mint to a recipient it commits. **MAY** be any depositor (permissionless). | Business activity only; no protocol veto over other holders' coins |
| **Gatekeeper** (optional) | Designated blockchain address — an x-only BIP-340 key; **MAY** be a MuSig2/FROST **threshold** aggregate of a holder committee (still a single x-only key in-circuit). Per-mint approval is mandatory when designated. Performs **two load-bearing roles** (§6.1, §3.2.1.1): (a) **source-of-funds / vault-legitimacy screening**, and (b) **canonical-chain anchor** — withholds the `Pk_mint` mint-settlement signature until `MoveToBacked` is confirmed on the gatekeeper's **own canonical Bitcoin view** (closes R-04). | Entry filter + mint-settlement canonicity gate; **cannot mint without valid backing** (deposit + operator-set-legit clauses) and **cannot redirect another depositor's committed mint** (clause (g)); has no special minting privilege beyond any depositor; cannot inflate, freeze, claw back, or touch existing coins; **cannot settle a mint against a non-canonical `MoveToBacked`** because it withholds `sk_mint` until canonical confirmation |

The asset **MAY** set `gatekeeper` to the all-zero sentinel (= no gatekeeper). Then minting is fully permissionless under depositor-anchored `Pk_mint` (§3.2) and structural operator-set legitimacy (§3.1). **Honest limitation (R-04 / §6.4):** without a gatekeeper (or equivalent canonical-oracle role) there is **no external canonical observer** at mint settlement; no-gatekeeper pooled backing is a **materially weaker** security class and **MUST NOT** be presented as trust-minimized.

A gatekeeper **MAY** also act as a depositor/minter for the same asset, subject to the **same** mint clauses as any other depositor — it has no special minting privilege.

The **vault presigning / operator set** (keys that co-sign the pre-signed Glock graph at setup and whose aggregate identity `agg_key` is admitted by `operator_set_root`) **MUST** be **N-of-N** (MUST — NEW-01). All operators **MUST** sign the graph at setup, and all **MUST** delete their signing shares afterward. Under 1-of-N setup honesty, **one honest deletion** prevents any further graph signing — a `t < N` threshold would leave `N−1 ≥ t` shares able to sign after one honest deletion and would **break** 1-of-N safety. A live `t-of-n` CHECKSIG on the vault is already forbidden (§3.1.1); the presigning set itself **MUST NOT** be threshold either.

**Threshold / FROST is allowed only for the gatekeeper key** (when designated): a gatekeeper **MAY** be a MuSig2/FROST threshold aggregate (still a single x-only key in-circuit). Its threshold affects **approval liveness** only; a gatekeeper **cannot** create unbacked mints (backing is circuit-enforced), so gatekeeper aggregation **does not** touch vault safety. **Warning (MUST state):** an **N-of-N** gatekeeper aggregate means loss of a single member key **permanently disables minting** of that asset (rotation of a bound gatekeeper = new asset); threshold (t-of-n) for the **gatekeeper only** is **RECOMMENDED** to avoid permanent disablement from a single key loss.

An organisation **MAY** also operate an ordinary operator node if and only if launch gate A(1) still holds (affiliated keys strictly under half). Membership as operator confers **no** special mint or redeem privilege beyond the ordinary operator role.

### 2.2 What the gatekeeper (and any minter) cannot do

| Action | Why it fails |
|--------|----------------|
| Block transfers of circulating zkBTC | Ordinary §2 sends; no gatekeeper/minter clause in holder transitions |
| Block redemptions | Peg-out path (§4.3) has no gatekeeper step; operators serve holders |
| Forge supply without real vault backing | Mint clauses (e)/(f)/(h): LCP `MoveToBacked` confirmation + N-of-N + recursive `operator_set_root` equality + depth ≥ `D_mint`, one-shot `Pk_mint` uniqueness, `amount == vault-output amount`; in gatekeeper mode, private-fork mint further blocked by gatekeeper withholding `Pk_mint` until **canonical** confirmation (R-04) |
| Redirect a mint to a different recipient | Clause (g) recipient binding from deposit taproot commitment |
| Unilaterally seize the vault | N-of-N presigned Glock graphs; no gatekeeper admin key on vault spends |
| Quietly re-parameterise the asset | `vault_template`, `gatekeeper`, and `operator_set_root` are bound into `asset_id`; change implies a new asset. `refund_timelock` is a bridge-epoch parameter only (§4.4), not asset identity |
| Add, remove, or rotate the gatekeeper in place | `gatekeeper` is in `asset_id`; rotation = new asset (honest statement — §3.1, §6) |
| Substitute a self-controlled vault under an honest asset | `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root` and membership under that root (§3.1, §3.3(e), §3.3.1) |

### 2.3 Three flows (ASCII)

```
  User/Minter          Gatekeeper (opt.)   Bridge operators           Bitcoin L1
   |                     |                        |                      |
   |-- deposit (denom amount; recipient + optional depositor_base commits) -->|
   |                     |                        |-- N-of-N presign graph -->|
   |  [co-sign gate:] depositor co-signs MoveToBacked (BOTH modes; INV-01);
   |                  + gatekeeper co-signs in gated mode (anti-griefing)
   |                     |                        |-- MoveToBacked ----->|
   |                     |                        |   (backing-only vault;
   |                     |                        |    no refund leaf)
   |                     |                        |                      |
   |  [if gatekeeper:] SoF/vault + CANONICAL view (MoveToBacked depth ≥ D_mint
   |                   on gatekeeper's canonical chain; deposit not refunded);
   |                   gatekeeper withholds Pk_mint sig until then (R-04);
   |                   then signs m_state under Pk_mint
   |  [if no gatekeeper:] depositor signs m_state under depositor-anchored Pk_mint
   |                      (no external canonical observer — §6.4)
   |-- TS3 mint (LCP: MoveToBacked depth ≥ D_mint) ->|                   |
   |<-- zkBTC coin (to committed recipient) -------|                      |
   |                     |                        |                      |
   |==== free transfers among holders (gatekeeper offline) ==============|
   |                     |                        |                      |
   |-- redeem transition (anchors (Pkᵢ,Rᵢ)) ----->|                      |
   |-- open redeem + payout template ----------->|                      |
   |                     |                        |-- front BTC -------->|
   |                     |                        |-- claim/challenge -->|
   |                     |                        |-- reimburse ---------|
```

### 2.4 How the halves interact

| Event | Token standard (in-circuit) | Bridge profile (off-circuit) |
|-------|----------------------------|------------------------------|
| Peg-in deposit lands | — | Deposit taproot (refund leaf) → co-signed `MoveToBacked` (extinguishes refund) → **backing-only** vault output (no depositor/cooperative refund; pre-signed reimbursement graph only); denomination check |
| Mint settles | Clauses (a)–(h); `(Pk_mint, R)`; LCP proves `MoveToBacked` confirmed at depth ≥ `D_mint` + N-of-N + recursive `operator_set_root` | Observes mint; backing-only vault UTXO is the settled backing (proven in-circuit; no host-side freshness re-check) |
| Holder transfer | Ordinary §2 | None |
| Redeem settles | `redeem_commitment` (incl. `max_fee`); `(Pkᵢ, Rᵢ)` | Accepts opening; fronts payout; claim/challenge with claim-marker `(Pkᵢ, Rᵢ, payout_txid, payout_vout)` (logical first-marker — NH-02) |
| Audit | Upper-bound circulating ≤ vault UTXOs; exact needs published aggregate attestation | Public vault UTXO set + optional balance/aggregate attestations |

### 2.5 Competing tokens / market

Because `gatekeeper`, `operator_set_root`, and `H(vault_template)` are bound into `asset_id`, each (name/genesis, vault template, operator set, gatekeeper) combination is a **distinct asset**. Anyone **MAY** deploy a competing zkBTC with their own gatekeeper, a different operator set, or no gatekeeper. Wallets **MUST** key by `asset_id` (and circuit lineage), never by display name alone. Adoption decides which zkBTC wins. The asset model supports this natively.

---

## 3. Token standard 3 — permissionless, deposit-backed, redeemable (`issuance_version == 3`)

Token standard 3 is a new issuance schema in the sense of specification.md §6.5. It is **not** an edit to frozen v1; it ships only as a version branch of the **v2 circuit surface**. Dispatch **MUST** be an in-circuit version branch of the same circuit `C` (specification.md §6.5 "Adding new token standards"): a separate per-version circuit would break cyclic recursion when an account lineage mixes standards.

### 3.1 IssuanceTerms_v3 schema

Denominations and `refund_timelock` are **not** part of the token terms. Values bound into `asset_id` freeze for the life of the asset; denomination economics and deposit-taproot CSV depend on Glock mainnet cost reality and **MUST** remain adjustable per deposit epoch as bridge parameters (§4.4). Soundness needs `vault_template` and `operator_set_root` in the terms (cross-asset double-backing closure and vault-legitimacy binding) plus in-circuit `amount == vault-output amount` and operator-set membership.

```
IssuanceTerms_v3 = {
  asset_id          : field,     // = Hc("AssetIdV3", genesis_tag ‖ gatekeeper ‖ operator_set_root
                                 //      ‖ H(name) ‖ decimals ‖ issuance_version ‖ H(vault_template))
                                 //   genesis_tag reuses the v1 constant ASCII string "zkCoins/v1/genesis" (§3.7.2)
  gatekeeper        : 32 bytes,  // x-only BIP-340 pubkey of the optional quality authority;
                                 //   OR the all-zero 32-byte sentinel = "no gatekeeper"
  operator_set_root : 32 bytes,  // commitment to the legitimate operator/signer set and epoch policy
                                 //   (e.g. Merkle/policy root over permitted N-of-N aggregate keys
                                 //   and their honesty basis); MUST — closes self-controlled-vault drain
  issuance_version  : u8 = 3,
  name_hash         : digest,    // = H(name); name never on-chain (same rule as v1/v2)
  decimals          : u8,        // = 8 (satoshi); normative for zkBTC
  vault_template    : bytes,     // canonical parameterized vault tapleaf-set template (§3.1.1);
                                 //   holes for agg_key identity, epoch, CSV constants; NUMS internal key;
                                 //   pre-signed-graph leaves only (no live CHECKSIG; no depositor refund);
                                 //   MUST NOT embed asset_id as a free field — see instantiate below
  terms_hash        : field      // = Hc("IssuanceTermsV3", asset_id ‖ issuance_version
                                 //      ‖ gatekeeper ‖ operator_set_root ‖ H(vault_template))
}
```

**Transport.** Identical to specification.md §6.5 IssuanceTerms transport: terms travel as optional `asset_terms` inside `CoinProof` (or out-of-band). The receiver recomputes `asset_id` and rejects a mismatch. The human-readable `name` is never on-chain.

#### 3.1.1 `vault_template` canonical encoding and `instantiate` (normative — B-02)

`vault_template` is a **canonical byte template** for the vault's **script-path tapleaf set**. Parameter holes are filled only by `instantiate`:

| Hole | Width | Meaning |
|------|-------|---------|
| `AGG_KEY_HOLE` | 32 bytes | **N-of-N** (Glock) aggregate x-only public key **identity** of the vault instance — used to bind the instance to an `agg_key` admitted by `operator_set_root` and to label the pre-signed graph for this operator set. **MUST NOT** create a live `agg_key` CHECKSIG spend path (NEW-01). The vault presigning set is **N-of-N**, not a threshold (NEW-01 — §2.1). |
| `EPOCH_HOLE` | 8 bytes | Deposit-epoch identifier (`u64` big-endian); binds the instance to a bridge epoch |
| `CSV_OP_HOLE` | variable (BIP-68 encoded) | Operator / reimbursement / claim-connector-leaf CSV relative locktime; filled to the **Glock claim/challenge CSV windows** of this epoch (B-06 / §4.4 — not a mint-window formula) |

There is **no** `CSV_REFUND_HOLE`, **no** depositor-refund leaf, and **no** cooperative-refund leaf on the **backing-only** vault output (R-01). The depositor's unilateral refund lives exclusively on the **deposit taproot** (§4.2) and is extinguished when `MoveToBacked` consumes that output.

All other script structure is fixed by the template. The template **MUST NOT** contain `asset_id` as a free field outside the asset/epoch binding leaf (that would be circular: `asset_id` depends on `H(vault_template)`).

**NUMS internal key (MUST — no key-path spend).** The vault taproot output **MUST** use an **unspendable NUMS internal key** — a point with no known discrete log — so there is **no key-path spend**. Using `agg_key` as the internal key is **forbidden**: a key-path spend by the operator set would bypass every CSV-locked leaf and every pre-signed reimbursement path.

**NUMS derivation (normative — NEW-03).** The internal key **MUST** be an unspendable nothing-up-my-sleeve point with no known discrete log, identical for every vault of every asset (**not** a secret and **not** asset-bound). Derivation rule:

1. Domain tag: the fixed ASCII string `zkCoins/v2/VaultNUMS`.
2. Let `domain_sep` be the consensus-fixed 32-byte all-zero string of the v2 release.
3. `NUMS_xonly := xonly(hash_to_curve(domain_tag ‖ domain_sep))`, where `hash_to_curve` is a consensus-pinned hash-to-curve into secp256k1 with unknown discrete log (BIP-340-compatible even-y lift).  
   **Rationale / relation to BIP-341:** this is the same class of construction as the BIP-341 example NUMS internal key `H` (lift of the SHA-256 midstate of the BIP-341 tagged hash of the curve generator); this profile pins a profile-specific domain tag so the point is unambiguous for zkCoins vaults.
4. The concrete 32-byte x-only NUMS value is a **launch pin** of the v2 release (one value, frozen with the circuit digests). Until that pin, the derivation rule above is normative; the byte value is marked `PROVISIONAL`.

**No live CHECKSIG on the vault (MUST — NEW-01; covenant-emulation core).** Every vault spend path **MUST** move funds **only along the pre-signed Glock transaction graph** fixed at setup. The vault **presigning set MUST be N-of-N** (all sign; all delete — §2.1). After the per-deposit graph is fully signed, each signer's signing shares for those graph transactions **MUST** be **deleted**. Under 1-of-N setup honesty, one honest deletion means no coalition can authorise a spend outside the approved graph.

- There is **no live signing path** on the vault output: a live threshold/`agg_key` CHECKSIG that any current coalition could use to sign an **arbitrary** vault spend is **forbidden**. The presigning set itself is N-of-N, not t-of-n (NEW-01).
- Operator / reimbursement / connector leaves **MUST** commit to **specific pre-signed graph transactions** (claim, challenge, payout connectors, reimbursement payout) — not to a free-form `agg_key` CHECKSIG. **No** cooperative-refund leaf on the backing-only vault (R-01 residual — §4.2).
- Each such spend is authorised only by signatures produced **once at setup** with keys then deleted. A live CHECKSIG by the current key-holders is **forbidden**.
- This restores 1-of-N safety and makes the fraud statement / sequencing connectors the **only** paths that can move vault value after `MoveToBacked`.

**Canonical ordered tapleaf set and tree construction (MUST — NEW-03).** All spend paths are **tapleaves** (script path only; BIP-341 tapleaf version `0xc0` unless a later consensus parameter freezes another version). Sorting sibling hashes alone does **not** define the tree shape; this profile pins both **leaf order** and **tree shape**:

1. **Leaf multiset (semantic identities).** `instantiate` builds exactly the following ordered multiset (fixed semantic order key = the labels below, left-to-right):

| Order key | Semantic leaf | Encoding / role |
|-----------|---------------|-----------------|
| (a) | **Operator / reimbursement leaf** | Pre-signed-graph reimbursement entry: commits to the Glock claim/reimbursement graph transaction(s) for this epoch (connector structure the graph requires). **CSV-timelocked to the Glock claim/challenge window** of this epoch (B-06 / §4.4). **MUST NOT** be a live `agg_key` CHECKSIG. The filled `AGG_KEY_HOLE` identifies the operator-set aggregate bound into the graph; it does **not** authorise free-form spends. |
| (b) | **Claim / reimbursement / sequencing connector leaves** | The additional connector leaves the Glock graph requires for claim/challenge serialisation and sequencing (exact scripts are graph-compiler artefacts — see launch-pin note below). Each leaf that can move vault value **MUST** be CSV-locked to the Glock claim/challenge windows (B-06). |
| (c) | **Asset/epoch binding leaf** | An unspendable commit leaf (OP_RETURN-style / always-fail script path) whose data payload is exactly `asset_id_bytes (32) ‖ u64be(epoch) (8)`. |

   **No depositor refund leaf and no cooperative refund leaf** appear on the backing-only vault (R-01). Unilateral depositor reclaim exists only on the deposit taproot **before** `MoveToBacked` (§4.2).

2. **Fixed leaf ordering key.** Leaves are ordered first by the semantic order key `(a) < (b) < (c)`; within (b), by ascending `tapleaf_hash` of each connector leaf (deterministic secondary key). This produces a total order independent of insertion order.

3. **Tree-shape rule (canonical balanced binary combination).** Over the ordered leaf list `L[0..n-1]`, build a **left-complete balanced binary Merkle tree** as follows:
   - If `n = 1`, the Merkle root is that single `tapleaf_hash`.
   - Otherwise, pair consecutive leaves left-to-right into parent nodes; BIP-341 sibling lexicographic sort applies **only within each pair** (standard BIP-341: `parent = H_tapbranch(min(a,b) ‖ max(a,b))`).
   - If the current level has an odd count, the last unpaired hash is promoted unchanged to the next level (left-complete; no Huffman rebalancing, no free reordering of unpaired nodes).
   - Repeat until one root remains.
   This rule, together with the fixed leaf order and NUMS internal key, fully determines the tree bytes for a **fixed** leaf multiset.

4. **Launch-pin honesty for concrete connector bytes (`PROVISIONAL`).** The **semantic** construction (leaf roles, CSV bounds, no live CHECKSIG, no vault refund leaf, NUMS, order key, tree-shape rule) is normative now. The **concrete** connector-leaf script bytes emitted by the Glock graph compiler are launch parameters: until the compiler template is frozen with the v2 circuit digests, byte-equality of `instantiate(…)` is defined **relative to the pinned template** once fixed, not claimed as fully determined by the prose alone. Implementations **MUST NOT** claim present-day absolute byte-determinism for the connector subset beyond the semantic pins above.

Define the concrete vault output by instantiation:

```
instantiate(vault_template, asset_id, agg_key, epoch) :=
  // 1. Fill holes deterministically:
  leaves := vault_template tapleaf set with
              AGG_KEY_HOLE     ← agg_key                    // 32-byte x-only identity (NOT live CHECKSIG)
              EPOCH_HOLE       ← u64be(epoch)               // 8-byte big-endian
              CSV_OP_HOLE      ← bip68_csv(claim_challenge_csv)  // Glock claim/challenge window (B-06)
              asset/epoch leaf payload ← asset_id_bytes ‖ u64be(epoch)
              // NO CSV_REFUND_HOLE; NO depositor-refund leaf; NO cooperative-refund leaf
  // 2. Internal key := NUMS   // unspendable; NO key-path spend (MUST)
  // 3. Order leaves by semantic key (a)<(b)<(c), then within (b) by
  //    ascending tapleaf_hash; build left-complete balanced BIP-341 tree
  //    (tree-shape rule above).
  // 4. output_key := BIP341_tweak(NUMS, merkle_root(leaves))
  // 5. scriptPubKey := P2TR(output_key)   // 34-byte witness program
  // Return the exact scriptPubKey bytes (and, for LCP equality, the full
  // serialised output script as used on Bitcoin) relative to the pinned
  // vault_template / graph-compiler template at launch.
```

Normative properties:

- Instantiation is a pure function of `(vault_template, asset_id, agg_key, epoch)` together with the consensus NUMS point and the epoch's Glock claim/challenge CSV constants (B-06 / §4.4). Two different `asset_id` values **MUST** produce different scriptPubKeys (via the asset/epoch binding leaf). `refund_timelock` is **not** an input to vault instantiation (it belongs only to the deposit taproot — §4.2 / §4.4). There is **no** mint-freshness window `W` and **no** `D_mint + S + W + 1` CSV term.
- At mint time, clause (e) **MUST** verify that the proven vault output's scriptPubKey is **byte-equal** to `instantiate(vault_template, this asset_id, agg_key, epoch)` for some `agg_key` admitted by `operator_set_root` and the epoch committed in the deposit path. Byte-equality is executable once the launch-pinned template (including connector-leaf bytes) and NUMS value are frozen; until then equality is relative to that pin (NEW-03 honesty).
- **Consequence (B-01 restored via MoveToBacked):** there is **no key-path bypass** and **no live free-form CHECKSIG**; the backing-only vault is spendable **only** via the Glock claim/challenge pre-signed-graph leaves. One BTC outpoint can back at most one asset. A minter **cannot** omit the asset binding: an output that does not match the required instance fails the mint. Settled mint ↔ backing-only UTXO is proven **in-circuit** by confirming `MoveToBacked` (§3.3(e)); no host-side freshness re-check.
- **Consequence (R-01 / INV-01):** a depositor **cannot** mint against a vaulted output and later unilaterally refund the same BTC: the backing-only vault carries no depositor-refund leaf and no cooperative-refund leaf; unilateral reclaim exists only if `MoveToBacked` never happens (deposit-taproot refund). If `MoveToBacked` fires but the mint never settles, the vaulted BTC is an **irrevocable, consented contribution to the shared reserve** (cross-graph reimbursement may consume it for another holder's redeem — §3.4, §4.2), not merely frozen recoverable BTC.

#### 3.1.2 Operator-set legitimacy (normative — Part 2)

`operator_set_root` is a 32-byte commitment to the **legitimate** operator/signer set and epoch policy for this asset (encoding of the Merkle/policy tree is a launch parameter; the root value is frozen in `asset_id`).

- The mint (clause (e)) **MUST** verify that the vault output's aggregate key `agg_key` is **admitted by** this asset's `operator_set_root`, with membership proven against the root **exposed by `C_lcp`** and checked by outer equality `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root` (§3.3.1). A bare membership-ok boolean is **not** sufficient.
- Without this binding, permissionless minting would allow an attacker to instantiate a vault with itself as the entire N-of-N, deposit, mint, then cooperatively spend its own vault after CSV → unbacked but fungible zkBTC, redeemed cross-graph against honest vaults. The 1-of-N honesty assumption is vacuous if the attacker supplies all N keys. Binding the operator set into `asset_id` **and** recursively binding the membership root into the LCP public interface closes that drain structurally (including the attacker-root variant of R-02).
- Changing `operator_set_root` produces a **different** `asset_id` (new asset).

#### 3.1.3 Binding rules

- `decimals` **MUST** equal `8` for the zkBTC asset (satoshi base units).
- `vault_template` is bound into `asset_id` via `H(vault_template)`. Changing the template produces a **different** `asset_id` (new asset).
- `gatekeeper` is bound into `asset_id` and `terms_hash`. Presence and identity are fixed and holder-visible. A gatekeeper **cannot** be added, removed, or rotated without producing a different asset (**rotation = new asset** — stated honestly).
- `operator_set_root` is bound into `asset_id` and `terms_hash` (same freeze discipline).
- `refund_timelock` is a **per-deposit-epoch bridge parameter** only (§4.4). It governs the deposit-taproot refund leaf, not token identity, and is **not** in `IssuanceTerms_v3`, `AssetIdV3`, or `terms_hash`.
- Allowed deposit/payout denominations are **per-deposit-epoch bridge parameters** (§4.4). The circuit enforces only `amount == vault-output amount`, not membership of a frozen denomination set.

### 3.2 Mint key derivation and the one-shot mint account

#### 3.2.1 Additive-tweak mint key (`Pk_mint`)

The mint anchors to the **`MoveToBacked` vault outpoint** `(vault_txid, vault_vout)` — the backing-only N-of-N/Glock vault UTXO created when `MoveToBacked` consumes the user's deposit output — **not** the user's original deposit outpoint. Write `vault_outpoint := vault_txid ‖ vault_vout` (32-byte txid ‖ 4-byte little-endian `vout`, matching Bitcoin outpoint serialisation).

For each such vault outpoint of this `asset_id`:

```
digest = Hc("zkCoins/v2/MintKey", asset_id ‖ vault_outpoint)
```

**Digest-to-scalar (normative, mirrors specification.md §3.2 BIP-340/S2C).** Let `n` be the secp256k1 group order.

1. Let `h_bytes` be the **32-byte serialization** of the Poseidon `Hc` digest (byte order per parent specification.md §1.7).
2. Interpret `h_bytes` as a **big-endian integer** and reduce **mod `n`** to obtain the scalar candidate `h`.
3. If the reduced value is `0`, **redraw** with a defined domain-tagged counter: recompute  
   `digest = Hc("zkCoins/v2/MintKey", asset_id ‖ vault_outpoint ‖ u32-be(counter))`  
   with `counter` starting at `1` and incremented until `h ≠ 0` (analogous to the parent redraw rule for exceptional S2C nonces). The unbiased reduction bias is ≈ `2⁻¹²⁸`, negligible.
4. **Even-y base normalisation (MUST — M-01).** Let `Pk_base` be the mode-dependent base key (§3.2.1.1 / §3.2.1.2). Before the additive tweak, `Pk_base` **MUST** be normalised to the **even-y lift** of its x-only encoding (parent specification.md §1.157):
   - Lift the 32-byte x-only encoding to the unique even-y curve point `P_base`.
   - Let `sk_base` be the corresponding secret for that even-y point (if the holder's raw secret produces the odd-y point, set `sk_base := n − sk_raw mod n` so that `sk_base · G = P_base` with even y).
   - All subsequent arithmetic uses this even-y `(P_base, sk_base)` pair.
5. Form the unnormalised point `P = P_base + h · G` on secp256k1.
6. If `P` is the point at infinity, **reject** and redraw with the next counter (same domain tag).
7. **BIP-340 x-only (even-y) normalisation of the result:**
   - if `y(P)` is odd: set `Pk_mint` to the even-y negation (`−P`) and  
     `sk_mint = n − (sk_base + h) mod n`;
   - else: set `Pk_mint = P` (x-only) and  
     `sk_mint = (sk_base + h) mod n`.

A pure hash-to-point construction (`Pk_mint = H_to_point(…)`) would be a NUMS point with no known discrete log — unusable as an account spend key. The additive-tweak form is deliberate: it keeps mint authority on the mode-dependent base secret while making each vault outpoint's key unique and outpoint-bound.

##### 3.2.1.1 Gatekeeper-gated mode (`gatekeeper ≠ 0³²`)

```
Pk_mint = BIP340_even_y( gatekeeper_pubkey_even_y + h · G )
sk_mint = sk_gk_even_y + h   (with parity/negation per step 7)
```

where `gatekeeper_pubkey` is the x-only key from `IssuanceTerms_v3.gatekeeper` (fixed in `asset_id`) and `h` derives from `vault_outpoint` as above. Only the gatekeeper knows `sk_mint = sk_gk + h` (after even-y normalisation).

Because the accumulator admits `(Pk_mint, R)` only under a BIP-340 signature over `m_state` by `Pk_mint` (parent specification.md §3.2), **producing that on-chain nullifier IS the gatekeeper's act of approval** ("I permit this mint") — zero extra circuit cost beyond the ordinary spent-key check. First-occurrence on the deterministic `Pk_mint` (fixed `gatekeeper_pubkey` from `asset_id`, `h` from `vault_outpoint`) makes **one mint per deposit**, even against a malicious gatekeeper.

**Approval semantics (normative).** The gatekeeper's signature over `m_state` vouches that, for this mint:

1. **Source-of-funds:** the public on-chain BTC feeding the deposit has passed the gatekeeper's screening (reject hack/tainted/sanctioned BTC at entry);
2. **Vault/operator-set legitimacy:** the vault instance is legitimately constituted under this asset's `operator_set_root` (real 1-of-N-honest set — not an attacker-controlled N-of-N);
3. **Committed recipient and clean deposit-backing:** the mint's **witness / inputs** establish a real LCP-proven vault deposit (≥ depth, to the asset's instantiated vault), the committed recipient (clause (g)), and operator-set membership under the asset-bound root (clause (e));
4. **Canonical-chain anchor (MUST — closes R-04).** On the gatekeeper's **own canonical Bitcoin view**: (i) the relevant `MoveToBacked` is confirmed to depth ≥ `D_mint` on the **canonical** chain, and (ii) the deposit output was **not** refunded on the canonical chain. The gatekeeper **MUST withhold** the `Pk_mint` signature until both hold. Because the mint cannot settle without the gatekeeper's `Pk_mint` signature (`sk_mint = sk_gk + h`; only the gatekeeper can produce it), a private-fork `MoveToBacked` yields **no mint**. A co-signed `MoveToBacked` alone is **insufficient** as the sole canonicity gate — its N-of-N setup signature is valid on any fork; the gate is the gatekeeper withholding the **final** mint signature until canonical confirmation. The gatekeeper is therefore the **canonical-chain anchor**, not only a source-of-funds / legitimacy check.

**Signing order / mint-signing checklist (normative — GK-2 + R-04; MUST).** "Verify the full mint proof before signing" is **circular**: the completed proof `C` embeds the gatekeeper's BIP-340 signature over `m_state` (S2C over `H(ProofData)`), so the proof cannot exist before the signature. The correct order is:

1. The gatekeeper verifies the mint's witness/inputs — the LCP-proven vault deposit (real, ≥ depth, to the asset's `instantiate`d vault), the committed recipient, `operator_set_root` membership against the asset-bound root, and its own source-of-funds / legitimacy policy — **NOT** a completed proof.
2. **Canonical confirmation (MUST — R-04):** on the gatekeeper's **own canonical Bitcoin view**, confirm that (i) `MoveToBacked` is present at depth ≥ `D_mint` on the **canonical** chain and (ii) the deposit output was **not** refunded on the canonical chain. **Withhold** the mint signature until both hold.
3. Only then does the gatekeeper produce the transition-authorization **signature** (`sk_mint` S2C over `m_state` committing `H(ProofData)`).
4. After that signature exists, the final proof `C` is constructed embedding it and settled.

**Caveat (MUST state).** Blind signing (signing without checking inputs, including without the canonical-chain check) cannot create an unbacked mint that the circuit alone rejects (backing is circuit-enforced against *some* header chain) — but it **does** re-open the private-fork amortization attack of R-04 and may waste the `Pk_mint` slot or wave through a tainted mint. The gatekeeper checks all proof inputs **and** its own canonical Bitcoin view, signs only after both, then the proof is built.

##### 3.2.1.2 No-gatekeeper mode (`gatekeeper = 0³²`)

```
Pk_mint = BIP340_even_y( depositor_base_even_y + h · G )
```

where `depositor_base` is a key the depositor **commits in the deposit taproot** and the mint verifies in-circuit via the LCP leaf data (exactly like the recipient commitment of clause (g)). **WITHOUT** this in-circuit commitment, any prover could choose its own base and first-occurrence would give no one-mint-per-outpoint guarantee — so this commitment is **MANDATORY** in no-gatekeeper mode.

**Hard limitation (MUST state — R-04 / §6.4).** With `Pk_mint` anchored on the depositor's own key, the depositor produces the mint signature itself. There is therefore **no external canonical observer**: the private-fork amortization attack (mine a private fork, fire co-signed `MoveToBacked` only there, mint from the private-fork LCP proof, refund the deposit on the canonical chain → unbacked zkBTC amortized over many deposits) is **not closed** in this mode for a pooled fungible reserve. Backing integrity in no-gatekeeper mode **additionally** depends on reimbursement operators refusing to reimburse against non-canonical vaults (a best-effort operator-honesty / oracle assumption) and remains **materially weaker**. A **trust-minimized pooled zkBTC effectively REQUIRES a gatekeeper (or an equivalent canonical-oracle role)**; no-gatekeeper mode **MUST NOT** be presented as trust-minimized backing.

```
depositor_base_commitment = H("zkCoins/v2/DepositorBase", depositor_base ‖ db_blind)
```

carried as committed leaf data in the deposit taproot beside the recipient commitment and refund leaf. Clause (b) opens it and checks `Pk_mint` derivation against the opened `depositor_base` (even-y normalised per M-01).

#### 3.2.2 One-shot mint account (consumed-key uniqueness)

Every vaulted deposit spawns a fresh **one-shot mint account** whose genesis key is `Pk₀ = Pk_mint`. The TS3 mint **MUST** be that account's genesis transition:

- `prev_account_state.send_counter == 0`
- `prev_account_state.current_pubkey == Pk_mint`

The mint consumes `Pk_mint` and publishes `(Pk_mint, R)` as its on-chain nullifier. First-occurrence on `Pk_mint` (specification.md §3.6 / §3.7) makes a second settled mint against the same vault outpoint impossible — the exact token-standard-2 genesis mechanism (specification.md §6.5 clause (f)) reused **per vault outpoint**.

**Naked-aux-key gap (normative rationale).** A design that merely "additionally publishes" an auxiliary key without consuming it would **not** be checked by any compliance-predicate clause. A second mint could still settle under a different consumed key. That is why the mint key **MUST BE** the consumed key of the mint transition, not a naked auxiliary object.

**Front-running.**

- **Gatekeeper-gated:** a third party **cannot** burn the `Pk_mint` slot: accumulator admission requires a BIP-340 signature over `m_state` by `Pk_mint`, and only the gatekeeper knows `sk_mint`.
- **No-gatekeeper:** only the holder of `depositor_base` knows `sk_mint`; the in-circuit commitment of `depositor_base` prevents a stranger from choosing a different base for the same outpoint.

### 3.3 Mint clauses (normative, in-circuit)

When `asset_issuance` is present and `issuance_version == 3`, the **v2 circuit surface** of `C` **MUST** verify all of the following (style parallel to specification.md §6.5 (a)–(g)). Clause numbering (a)–(h) is local to this standard; it hooks into specification.md §2.1 clause 3 the same way standards 1 and 2 do.

- **(a)** `issuance_version == 3` — this branch accepts only TS3 mints.
- **(b) Base + vault-outpoint binding.** The mint account's `owner` equals `H(Pk_mint ‖ nk_commit)`. The circuit verifies in-circuit the full §3.2.1 derivation:

  ```
  Pk_mint == BIP340_even_y( Pk_base + h · G )
  ```

  where `h` is the mod-`n` reduction of `Hc("zkCoins/v2/MintKey", asset_id ‖ vault_outpoint)` (with the §3.2.1 redraw/counter rules and even-y base normalisation), and `Pk_base` is:

  - **Gatekeeper-gated:** the even-y lift of `gatekeeper` from `asset_id`;
  - **No-gatekeeper:** the even-y lift of `depositor_base` opened from the deposit-taproot commitment (LCP leaf data).

  This simultaneously binds the mint to the **mode base** and to the **vault outpoint**.
- **(c)** `asset_id` recomputation per §3.1 (`AssetIdV3` preimage including `gatekeeper`, `operator_set_root`, `H(vault_template)`; no `refund_timelock`).
- **(d)** `terms_hash` recomputation per §3.1 (`gatekeeper`, `operator_set_root`, `H(vault_template)`).
- **(e) Vault-backing reality (LCP sub-proof).** Recursively verify a Bitcoin light-client sub-proof — normatively a **separate recursive Plonky2 circuit** whose root is verified inside `C` (the BRIDGE_MVP.md §3.2 recursive-LCP decision remains valid; inlining SHA-256d header chains into the main compliance budget is not required). The LCP statement **MUST** establish all of:
  1. **Header chain.** A chain of Bitcoin headers from a **pinned checkpoint** (checkpoint value is a circuit / S2C consensus parameter of the v2 release — §3.7.2, §11); each header is PoW-valid and links to its predecessor; cumulative work is computed.
  2. **`MoveToBacked` vault outpoint (not the user's deposit outpoint).** The proven UTXO is the **backing-only vault output** `(vault_txid, vault_vout)` created by a confirmed **`MoveToBacked`** transaction — the N-of-N/Glock vault UTXO that consumes the user's deposit output. `Pk_mint` derivation uses this same vault outpoint (§3.2.1).
  3. **N-of-N witness proof (MUST — closes the drain-class private-fork hole).** The LCP **MUST** prove that the `MoveToBacked` transaction spent the user's deposit output through the **vault leaf under the N-of-N (Glock aggregate) signature** produced at setup — i.e. the spend is authenticated by the operator set's pre-signed graph path, not by the user's refund leaf.  
     **Rationale:** without this, an attacker could, in a private fork, spend their own deposit via the refund leaf into a look-alike `vault_descriptor` output and fabricate unlimited unbacked "MoveToBacked"s with no operator, amortising one discarded fork over unlimited fake mints. Requiring the N-of-N witness makes forging a `MoveToBacked` require full operator collusion, which the 1-of-N setup-honesty assumption excludes.
  4. **Vault script instance byte-equality + operator-set membership (MUST — B-02 + Part 2).** Output `vault_vout` pays exactly `amount` sats to a script that is **byte-equal** to `instantiate(vault_template, this asset_id, agg_key, epoch)` (§3.1.1 — NUMS internal key + ordered Glock claim/challenge tapleaf set; **no** depositor or cooperative refund leaf), **and** `agg_key` is admitted by this asset's `operator_set_root`. Membership is proven **against the root exposed by `C_lcp`**, and the outer circuit `C` **MUST** check `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root` (asset-bound root equality — §3.3.1). A free-standing boolean `operator_set_member_ok` is **not** sufficient. The recipient commitment of clause (g) (and, in no-gatekeeper mode, the `depositor_base` commitment) is carried as committed leaf data consistent with the deposit → vault path (§4.2).  
     **Attack closed:** without recursive root binding, an attacker proves membership of a self-controlled `agg_key` under an **attacker-chosen** root, a bare `operator_set_member_ok = true` passes, and the outer circuit cannot tell — enabling a self-controlled vault drain under an honest asset. Exposing and equating `operator_set_root` makes that attack fail.
  5. **`MoveToBacked` confirmation depth (MUST — R-01 / R-04 inverted binding).** Confirmations of the `MoveToBacked` block below the proven tip satisfy  
     `depth ≥ D_mint`  
     (and, when an upper slack is configured, `depth ∈ [D_mint, D_mint + S]`),  
     where `D_mint` and optional `S` are normative `PROVISIONAL` parameters (§4.4; on the order of the bridge security horizon, e.g. `D_mint ≈ 2016` blocks — long finality is acceptable per REQ-4).  
     **The mint proves "`MoveToBacked` confirmed at depth ≥ `D_mint`"** — not "vault output unspent in a host-side window." Because the backing-only output `MoveToBacked` creates has **no refund path** (neither depositor nor cooperative — §3.1.1 / §4.2), a settled mint corresponds to a permanent backing-only vault UTXO. That correspondence is proven **in-circuit** and is recursively inherited by every later transition; downstream holders need **no** host-side re-check of Bitcoin vault state or mint freshness. There is **no** in-circuit non-spend-to-tip proof, **no** host-side freshness rule, **no** `tip_height` ProofData field, and **no** mint-window CSV race against a refund leaf (there is none).
- **(f) Genesis binding / uniqueness.** `prev_account_state.send_counter == 0` **and** `prev_account_state.current_pubkey == Pk_mint` (see §3.2). Combined with first-occurrence on `Pk_mint`, a second settled mint against the same vault outpoint is impossible.
- **(g) Recipient binding.** The deposit taproot commits

  ```
  recipient_commitment = H("zkCoins/v2/DepositRecipient", recipient ‖ rc_blind)
  ```

  in the taproot tree beside the refund leaf (placement is bridge detail, §4.2). The circuit verifies that the minted output coin's `recipient` opens that commitment. Neither the gatekeeper nor any minter **MUST** be able to redirect a mint to a different address after the user has deposited (custody-class protection; same lesson as out-intent / blind-signing findings in the main specification's history).
- **(h) Amount discipline.** `amount == vault-output amount` exactly — the **only** in-circuit amount rule. Denomination membership is bridge-side (§4.4). Emission mirrors token-standard-2 clause (g): for the minted asset `a`, `Out(a) == Mint(a) == amount`, `In(a) == 0`; the mint **MUST NOT** self-credit into balances, `received_coins[]`, or this transition's coin-history; credit only via a later clause-10 receive.

**Dispatch.** TS3 is one more branch of the **same** circuit `C`. The v2 circuit ships standards 1, 2, and 3 as branches so the new lineage universe is complete from genesis (§3.7). Adding the branch extends the version dispatch of specification.md §2.1 clause 3, which today accepts only `issuance_version == 1` or `2` on the v1 surface; on the v2 surface the accepted set is `{1, 2, 3}`.

#### 3.3.1 LCP sub-proof interface (normative sketch)

The recursive LCP is a separate circuit `C_lcp` (name provisional) whose public outputs feed the TS3 mint branch. Minimum public interface:

```
LCP_Public = {
  checkpoint_hash,          // pinned Bitcoin header hash (circuit / S2C parameter of the v2 release)
  tip_hash,                 // proven tip
  cumulative_work,          // total work from checkpoint to tip
  vault_txid,               // 32-byte MoveToBacked txid (the vault outpoint, NOT the user deposit)
  vault_vout,               // u32
  vault_amount,             // u64 sats
  vault_script_bytes,       // exact scriptPubKey of the backing-only vault output
  agg_key,                  // 32-byte N-of-N aggregate key used in instantiate (presigning set is N-of-N)
  epoch,                    // u64 deposit epoch used in instantiate
  operator_set_root,        // 32-byte root that C_lcp proved agg_key membership against (MUST — R-02)
  n_of_n_witness_ok,        // boolean / bit: MoveToBacked spent the deposit via the N-of-N vault leaf
  recipient_commitment,     // as in clause (g)
  depositor_base_commitment,// present / opened in no-gatekeeper mode; zero sentinel otherwise
  depth                     // confirmations of MoveToBacked below tip; MUST be ≥ D_mint
                            //   (optionally ≤ D_mint + S when upper slack is configured)
}
```

**Recursive operator-set root binding (MUST — closes self-controlled-root attack).** `C_lcp` **MUST** expose the `operator_set_root` it proved membership against as a public output; the membership Merkle/policy proof inside `C_lcp` is against **that** root. The outer mint circuit `C` **MUST** verify

```
C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root
```

(equality with the asset-bound root). `C` **MUST NOT** rely on a free-standing `operator_set_member_ok` boolean: such a boolean can be `true` under an attacker-chosen root while the outer circuit only sees the bit. Equivalently, `C` **MAY** verify the membership Merkle path directly against the asset-bound `IssuanceTerms_v3.operator_set_root` (same root equality, no bare boolean).

**Attack closed.** Without this binding an attacker proves membership of a self-controlled `agg_key` under an **attacker root**, sets `operator_set_member_ok = true`, and the outer circuit cannot distinguish that from membership under the honest asset root → unbacked mint under a self-controlled vault, redeemable cross-graph against honest vaults (drain). Root equality makes the attack fail: a foreign root does not equal `IssuanceTerms_v3.operator_set_root`.

The mint branch **MUST** check equality of `vault_amount` with `asset_issuance.amount`, **byte-equality** of `vault_script_bytes` with `instantiate(vault_template, this asset_id, agg_key, epoch)`, `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root`, `n_of_n_witness_ok == true`, depth ≥ `D_mint` (and ≤ `D_mint + S` when upper slack is configured), equality of `recipient_commitment` with the opening used for the minted coin's `recipient`, and (in no-gatekeeper mode) opening of `depositor_base_commitment` consistent with clause (b). The exact bit-encoding of the N-of-N witness check and operator-set membership proof is a Glock-graph / launch-parameter detail; the **semantic** requirements (operator-set authentication of the `MoveToBacked` spend; membership of `agg_key` under the **asset-bound** `operator_set_root`) are normative here.

#### 3.3.2 Binding via MoveToBacked (normative — R-01 / R-04; replaces host-side freshness)

Host-side mint freshness is **not** a security source under this design. There is **no** `tip_height` ProofData field, **no** inscription-height rule `h_inscr < tip_height + W`, **no** freshness window `W`, and **no** mint-window CSV term `D_mint + S + W + 1`.

Soundness of settled mint ↔ permanent backing rests on:

1. **`MoveToBacked` is a fixed pre-signed graph transaction** (content fixed at setup → txid fixed → the downstream reimbursement graph stays pre-signable). It is nullifier-free and ordinary on Bitcoin. It **consumes** the depositor-refundable deposit output and **creates** the backing-only vault output (§4.2).
2. **Firing requires a co-sign gate (consent + anti-griefing — MUST; INV-01).** `MoveToBacked` **MUST** require the **depositor's co-signature in both modes** (gatekeeper and no-gatekeeper) — so the contribution to the shared reserve is **consented**, not imposed. In **gatekeeper mode**, the **gatekeeper's co-signature is additionally required** (anti-griefing: a third party cannot fire after a gatekeeper refusal). Implementation: a co-sign tapleaf or additional required signature(s) on the pre-signed `MoveToBacked` path.
3. **The mint LCP proves `MoveToBacked` confirmed at depth ≥ `D_mint`** (clause (e) point 5) on *some* header chain. Because the backing-only output has **no** refund path, that confirmation is a permanent commitment of the deposited BTC to the vault graph **on the proven chain**.
4. **Canonical-chain anchor at mint settlement (MUST — R-04; gatekeeper mode).** The LCP alone does **not** bind the proven header chain to the verifier's **canonical** Bitcoin view. In gatekeeper mode, the gatekeeper **withholds** the final `Pk_mint` signature until it has verified, on its **own canonical Bitcoin view**, that `MoveToBacked` is confirmed at depth ≥ `D_mint` on the canonical chain and the deposit was not refunded there (§3.2.1.1). Co-signed `MoveToBacked` alone is insufficient (setup signatures are valid on any fork). In no-gatekeeper mode this external anchor is absent (§3.2.1.2, §6.4).
5. **No host-side re-check for downstream holders.** Downstream CoinProof receivers inherit the in-circuit statement recursively; they **MUST NOT** be required to re-check Bitcoin vault unspentness or mint inscription freshness. (The gatekeeper's canonical check is a **mint-time** observer role, not a transitive holder duty.)

### 3.4 Deep-finality canonicity (normative)

The LCP proves `MoveToBacked` at depth ≥ `D_mint` on a PoW-valid header chain (deep enough that private-fork mining for the mint value is economically irrational as a pure mining attack) **and** the N-of-N witness (clause (e) point 3) **and** operator-set membership (clause (e) point 4). That is **necessary but not sufficient** to bind the mint to the **canonical** Bitcoin chain: the LCP proves confirmation on *some* header chain, not that that chain is the verifier's canonical tip.

**Gatekeeper mode (closes R-04).** Canonical binding is supplied by the **gatekeeper as canonical-chain anchor** (§3.2.1.1): mint settlement requires the gatekeeper's `Pk_mint` signature, and the gatekeeper issues it **only after** confirming `MoveToBacked` (depth ≥ `D_mint`, deposit not refunded) on its **own canonical Bitcoin view**. Private-fork `MoveToBacked` therefore cannot settle a mint. Downstream CoinProof receivers **MUST NOT** be required to re-check Bitcoin deposit/vault canonicity: the vault outpoint and its canonicity opening are **not** transitively available through later transfers (parent specification.md deliberately lets a verifier validate the latest proof without fetching prior transitions), and under the deep-finality + N-of-N + operator-set + backing-only + **gatekeeper canonical-anchor** construction they are **no longer needed** for later holders.

**No-gatekeeper mode (R-04 not closed).** With depositor-anchored `Pk_mint`, there is **no external canonical observer**. Private-fork amortization against a pooled fungible reserve remains open; see §3.2.1.2 and §6.4. This mode **MUST NOT** be presented as trust-minimized pooled backing.

Soundness source:

- The LCP binds the mint to a confirmed **`MoveToBacked`** that created a **backing-only** vault UTXO (no depositor refund, no cooperative refund), not a historical user-deposit inclusion and not a "vault still unspent" host-side claim.
- Depth ≥ `D_mint` makes pure private-fork fabrication of `MoveToBacked` economically irrational at the mint value as a mining cost; the N-of-N witness excludes refund-leaf private-fork forgeries without full operator collusion at setup. **Neither alone binds the proven chain to the canonical tip** — that is the gatekeeper's mint-signing duty (R-04).
- NUMS internal key + pre-signed-graph-only leaves (no live free-form CHECKSIG) keep vault spends on the Glock claim/challenge graph only.
- `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root` excludes attacker-supplied self-controlled operator sets under this `asset_id` (membership is against the exposed, asset-bound root — not a bare boolean).
- There is **no** host-side freshness machinery and **no** refund-vs-mint-window CSV race (backing-only has no refund leaf).

**Optional first-recipient check (SHOULD).** The first recipient of a TS3-minted coin (who holds the vault data out-of-band with the mint delivery) **SHOULD** additionally confirm that `(vault_txid, vault_vout)` is present at depth ≥ `D_mint` in **its own** canonical chain view. This is a defence-in-depth hygiene check, not a soundness requirement for later holders (and does not replace the gatekeeper's mint-time canonical-anchor duty).

**Residual (accepted, D-16 class).** A reorg deeper than `D_mint` that orphans the proven `MoveToBacked` is a bounded accepted finality boundary (risks.md D-16 class; report-intern constraint 21). It is not closed by transitive canonicity transport.

**Residual (accepted, consented irrevocable reserve contribution — R-01 / INV-01).** If `MoveToBacked` fires but the mint never settles, the vaulted BTC is **not** merely frozen recoverable BTC: because reimbursement is cross-graph (any same-asset in-set vault can back a redeem), it becomes an **irrevocable, consented contribution to the shared reserve** and **MAY** be consumed by another holder's redeem. Firing requires the **depositor's co-signature in both modes** (§3.3.2 / §4.2), so the contribution is **consented**, not imposed. The depositor's unilateral escape for the "never processed / never `MoveToBacked`" case remains the pre-`MoveToBacked` deposit refund leaf.

### 3.5 Redeem transition (normative)

A redeem is an ordinary holder transition on the **v2 circuit surface**, not a separate ProofType and not a global SMT insertion.

#### 3.5.1 Balance shape

- `In(zkBTC) == redeem_amount`
- `Out(zkBTC) == 0` (no outputs of the asset; the difference is burned by conservation no-inflation — intentional value destruction for peg-out)
- `redeem_amount` **MUST** be an available payout denomination of the current bridge epoch (bridge rule §4.4). In-circuit, only the commitment binds the amount; denomination membership is enforced by the bridge when accepting a redemption request.

#### 3.5.2 ProofData field (v2 layout)

The v2 `ProofData` layout is the six v1 fields plus one new field (exact serialization pin in §3.7.2):

```
redeem_commitment = Hc("zkCoins/v2/RedeemCommit",
                       asset_id ‖ redeem_amount ‖ btc_recipient ‖ max_fee ‖ redeem_blind)
```

- Hiding: chain observers see only the field digest inside `H(ProofData)`, not the opening of `redeem_commitment`.
- `btc_recipient` is a 32-byte x-only taproot key; the payout output is P2TR to it.
- **`max_fee` (MUST — NH-03):** a `u64` satoshi ceiling on the operator's fee, committed inside `redeem_commitment`. The commitment **MUST** satisfy `max_fee < redeem_amount`. The payout **MUST** pay `btc_recipient` exactly the non-negative wide-integer difference `redeem_amount − max_fee` as a lower bound — i.e. at least `redeem_amount − max_fee`, computed with the parent §2.6 wide-integer gadgets so there is **no underflow and no zero-payout path from wrapping** (see §3.5.6 and §4.3.2). Binding a **ceiling** rather than an exact fixed fee is deliberate: a fee spike between redeem burn and fronting would otherwise leave the coin permanently unservable (loss of funds). The operator sets its actual fee `≤ max_fee` at fronting time.
- For **non-redeem** transitions (including **TS3 mints** and ordinary transfers), `redeem_commitment` **MUST** equal the all-zero 32-byte sentinel `0x00…00` (32 zero bytes). The circuit **MUST** accept the zero sentinel on non-redeem paths and **MUST** reject a zero sentinel when a redeem path is claimed (when `Out(zkBTC) == 0` and `In(zkBTC) > 0` for this asset under the redeem branch, or an explicit redeem flag if the implementation introduces one as an internal witness bit — either way the public field is non-zero iff a redeem is proven).
- There is **no** `tip_height` field and **no** per-branch tip/freshness sentinel (NEW-HOLE-01 resolved by removal).
#### 3.5.3 Redeem ID is the transition nullifier

**The redeem ID is the transition's own on-chain nullifier `(Pkᵢ, Rᵢ)`.** Sign-to-contract already binds `Rᵢ` to `H(ProofData)` and therefore to `redeem_commitment`. First-occurrence makes the **transition** ID unique. The bridge **MUST** key reimbursement claims on `(Pkᵢ, Rᵢ)`. **No separate redeem-nullifier object exists** (no global `burned_coins_smt`; that BRIDGE_MVP sketch is superseded).

#### 3.5.4 Off-chain opening and bridge consumption

The holder reveals the opening `(redeem_amount, btc_recipient, max_fee, redeem_blind)` **off-chain** to the bridge / operators as the redemption request. Chain observers see only that some transition happened (until a reimbursement claim marker appears — §8.2). The bridge fraud-proof circuit consumes the opening together with the settled nullifier. Third parties can be shown a specification.md §5.6-style trail for the redeem transition when the holder discloses the bundle.

#### 3.5.5 Transition uniqueness vs reimbursement uniqueness

- **Transition uniqueness:** one redeem transition = one `(Pkᵢ, Rᵢ)`. Re-proving the same transition cannot re-anchor: first-occurrence rejects a second publication of `Pkᵢ`. First-occurrence gives **transition** uniqueness, **not** reimbursement uniqueness.
- **Reimbursement uniqueness (MUST — claim-consumed marker):** first-occurrence alone does **not** prevent the same redeem ID from reimbursing multiple vault UTXOs across independent per-deposit Glock graphs. Binding a specific free vault outpoint into `redeem_commitment` is **not** constructible (the holder does not know which free outpoint will serve the claim at redeem time; two holders binding the same outpoint would permanently strand the second burn). Instead:
  1. The operator's **claim transaction publicly commits the redeem ID `(Pkᵢ, Rᵢ)`** on Bitcoin (a **claim-consumption marker**).
  2. The reimbursement fraud statement includes the conjunct: **no prior confirmed, valid, unchallenged reimbursement claim carries the same `(Pkᵢ, Rᵢ)`** (§4.3.2) — **slashed / successfully-counterproved / failed markers are excluded** from the uniqueness set (NEW-02).
  3. A second claim for the same redeem is **counterprovable** by a Bitcoin inclusion proof of an earlier **valid unchallenged** claim — the same 1-honest-watchtower challenge class as any other false claim. A malicious operator **MUST NOT** be able to poison a redeem ID with a slashed marker and block an honest retry.
- **Payout binding and claim-marker uniqueness (MUST — NH-02 / NEW-02):** the payout is an ordinary P2TR owned by `btc_recipient`; the operator **cannot** spend it (no key), so "consume the payout outpoint" is **not** a literal UTXO spend. Instead:
  1. Define a **claim-marker namespace**: the operator's reimbursement claim publicly commits the tuple `(Pkᵢ, Rᵢ, payout_txid, payout_vout)` as a **first-occurrence marker** in that namespace on Bitcoin.
  2. **Uniqueness = first-marker rule over the valid set only:** a second claim reusing the same `(Pkᵢ, Rᵢ)` **or** the same `(payout_txid, payout_vout)` is **counterprovable** by a Bitcoin inclusion proof of an earlier **valid, unchallenged** marker (same 1-honest-watchtower class as B-05 / claim-consumption). The operator does **not** spend the recipient's UTXO.
  3. **Slashed-marker exclusion (MUST — NEW-02):** only a **valid, unchallenged** claim marker consumes the redeem ID / payout outpoint for uniqueness. A marker that is **slashed**, **successfully counterproved**, or otherwise **failed** under the challenge path is **excluded** from the uniqueness set and **MUST NOT** block a later honest claim for the same redeem ID or payout outpoint.
  4. **Claimant-funded payout by value-accounting (MUST — NEW-02):** the fraud statement **MUST** prove that the **claiming operator funded the payout** by **value-accounting over bonded inputs**, not by mere presence of one bonded-key input. Under `SIGHASH_SINGLE|ANYONECANPAY`, an attacker could attach a small bonded input to a transaction mostly funded by the real operator; a single-input key-equality check is therefore insufficient. Exact rule (§4.3.2 item 12):
     - each input **signed by the claimant's bonded key** contributes its value to the claimant's funding sum;
     - inputs **not** signed by the claimant's bonded key are **value-ignored** (contribute **zero** to the claimant's funding);
     - the summed value of claimant-controlled inputs **MUST** cover **payout amount + mining fee**.
  5. **Ordering (keep):** the payout confirmation height **MUST** be **>** the first-occurrence height of `(Pkᵢ, Rᵢ)`.
  6. "**Consume**" in this document means the logical first-marker over the **valid unchallenged** set, **not** a UTXO spend. This closes historical/reused-output replay without requiring the operator to control the payout key, and without letting a slashed poison-marker freeze an honest redeem.
#### 3.5.6 Payout template mapping (bridge-facing)

The holder supplies a payout template using `SIGHASH_SINGLE | ANYONECANPAY`:

- Output 0 (or the signed output index): P2TR to `btc_recipient`, amount **≥ `redeem_amount − max_fee`** where `max_fee < redeem_amount` and the subtraction is an exact non-negative wide-integer (NH-03; §2.6 gadgets); the operator's actual fee is market-set at fronting time subject to that ceiling — §4.4.
- Any operator **MAY** fund the input side from **its own funds**.

The bridge fraud statement binds this template's paid output to the opening of `redeem_commitment`. An operator that pays a different address, or pays strictly less than `redeem_amount − max_fee`, **MUST** fail the reimbursement claim under an honest challenge path.

#### 3.5.7 Why not a separate BurnProof or burned SMT

Earlier research (`BRIDGE_MVP.md` §4, `BITVM_BRIDGE.md` §4) proposed a dedicated `BurnProof` ProofType emitting public `(burn_amount, btc_recipient, withdrawal_nonce)` and a global `burned_coins_smt`. That design is incompatible with:

- post-#97 on-chain nullifiers as the sole Bitcoin-published object `(Pkᵢ, Rᵢ)`;
- specification.md §2.2 single circuit `C` (InitialProof / AccountUpdateProof only);
- specification.md §6.5 version-branch dispatch for issuance (redemption is a holder transition, not a new ProofType).

The TS3 design reuses ordinary AccountUpdateProof transitions: value leaves circulation by `Out == 0` with a non-zero `redeem_commitment`, and uniqueness is the existing first-occurrence rule. No new on-chain object is introduced for burns.

### 3.6 Supply auditability

**Publicly verifiable from chain data alone = an upper bound (MUST — M-04):**

```
circulating zkBTC  ≤  BTC locked in the public vault UTXO set
```

Any observer can sum the public vault UTXOs on Bitcoin and treat that sum as a hard ceiling on circulating zkBTC (a mint requires a matching vault-output amount under clause (e)/(h); minting without vault backing is in-circuit impossible under the TS3 rules).

**Exact circulating figure is not protocol-enforced from chain data alone.** Parent nullifiers reveal no amount or asset, and proof validity remains off-chain (specification.md §3.1 / §3.2). An observer **cannot** distinguish vaulted-but-never-minted deposits or slot-burned mints from successfully minted ones without off-chain proofs. Public deposits and later payouts permit **correlation**, not protocol-level equality of

```
circulating  ==  Σ vaulted  −  Σ redeemed
```

Aggregate circulating supply therefore remains an **upper bound** (`circulating ≤ current backing vault balance`). It is **not** exactly computable from chain data alone.

**Published attestation ledger (for exact audit — optional).** Exact circulating supply requires a **published aggregate mint-minus-redeem attestation** (or equivalent proof/opening ledger). Note carefully:

- A specification.md **§5.7-style balance attestation proves one account**, not aggregate supply. It **MUST NOT** be implied that §5.7 alone yields the circulating total.
- If an **aggregate** mint-minus-redeem attestation is offered, it **MUST** be defined as such (a separate attestation form), not smuggled in under §5.7.
- **Without** such a ledger, only the upper bound plus public deposit/payout correlation exists — **not** protocol-enforced equality.

**Default published form (SHOULD).** Because publishing raw redeem openings would deanonymize `btc_recipient`, the default published form for holder-facing audit **SHOULD** be a **specification.md §5.7-style balance attestation** (per account), not raw openings. Raw openings **MAY** be disclosed under holder consent or legal process; they are not the default public audit surface. Aggregate exact supply, if published, uses the separate aggregate attestation form above.

**Contrast token standard 1:** mint amounts are not publicly summable at all (report-intern constraint 5; risks.md D-13). TS3 improves on TS1 by binding every mint to a public vault UTXO (upper-bound audit) and by enabling optional published attestations for exact figures.

**Honest trade-off:** vault deposit amounts and L1 payout amounts remain public by L1 visibility; internal transfers stay fully shielded (REQ-2 intact). Exact supply equality is an attestation/ledger property, not a pure chain-scan invariant. The default remains the upper bound + optional attestation, not raw openings.

### 3.7 Protocol-version consequence (v1 freeze) and migration

TS3 requires new circuit digests. Per specification.md §1.7.8 (v1 freeze): any change to the frozen circuit surface defines a **new protocol version** with **new digests and new lineages**; v1 artefacts are never edited in place.

**Normative migration / coexistence rules:**

1. zkBTC exists **only** in the v2-circuit universe. There is **no** cross-version receive between v1 and v2 lineages (cyclic recursion requires fixed verifier data within a lineage).
2. Existing v1 assets are unaffected and **MUST NOT** migrate implicitly into v2.
3. The v2 circuit **MUST** ship **all** standards (1, 2, and 3) as branches so the new universe is complete from genesis — creators of non-zkBTC assets can still issue under TS1/TS2 on v2.
4. ProofData layout v2 = six v1 fields + `redeem_commitment` (§3.7.2), with a new `circuit_digest(C)` pin for the v2 circuit. **`C_balance` is re-pinned for v2** (§3.7.2 — M-02): both digests change.
5. From the v2 release onward, §1.7.8-style freeze discipline applies to the **v2** surface: further changes are further version bumps, not in-place edits.

#### 3.7.1 Coexistence table

| Asset class | Circuit universe | Can receive from v1 lineage? | Notes |
|-------------|------------------|------------------------------|-------|
| Pre-existing v1 TS1/TS2 assets | v1 | Yes (within v1) | Frozen; unchanged |
| New TS1/TS2 assets issued on v2 | v2 | No | Same standard rules, new digests |
| zkBTC (TS3) | v2 only | No | Requires LCP + redeem field |
| Transitional bridged asset (§9) | v1 (TS1) | Yes (within v1) | Not named zkBTC |

Wallets **MUST** key assets by `asset_id` and circuit lineage, never by display name alone. A UI **MUST NOT** present a transitional asset under the zkBTC product name (§9).

#### 3.7.2 v2 circuit surface (pinned)

This subsection pins the consensus-relevant cryptographic surface for the v2 release. All values below are protocol constants of that release; changing any of them is a version bump.

**ProofData order and serialization (MUST — M-02).**

v1 `ProofData` (specification.md §1.4) is the six 32-byte digests in this order — **192 bytes**:

```
serialize(ProofData_v1) :=
    new_account_state_hash ‖ output_coins_root ‖ input_nullifiers_root
  ‖ coin_history_root ‖ nav_commitment ‖ npk_commit
```

v2 appends one field after the six v1 fields:

- **field 7** `redeem_commitment` — 32-byte Poseidon digest.

A **TS3 mint** therefore exposes:

```
{ six v1 fields, redeem_commitment (= zero-sentinel for a mint) }
```

A non-mint transition (including redeem) exposes:

```
{ six v1 fields, redeem_commitment (non-zero iff redeem) }
```

```
serialize(ProofData_v2) :=
    serialize(ProofData_v1) ‖ redeem_commitment
```

Total length: **224 bytes** (192 + 32). This is the pin **before** the short-lived `tip_height` extension was added and then removed (NEW-HOLE-01 / R-04 invert): host-side freshness and the 8-byte `tip_height` field are **gone**. `H(ProofData) := SHA-256(serialize(ProofData_v2))` for all v2 transitions (S2C binding unchanged in structure; preimage length grows from 192 → 224).

**Zero sentinels (MUST).**

| Field | Non-applicable path | Sentinel |
|-------|---------------------|----------|
| `redeem_commitment` | non-redeem (incl. mint) | 32 zero bytes |

There is **no** `tip_height` field and **no** tip/freshness per-branch sentinel.

**Public-input limb positions for the new field.**

Parent v1 layout for `C` (specification.md §2.5): six ProofData fields = five Poseidon digests (**20** field elements) + `npk_commit` (**8 × u32 limbs**) = **28** elements from `ProofData`, then `consumed_pubkey` (**8**), then `network_id` (**4**) — **40** application public-input elements.

v2 inserts `redeem_commitment` (Poseidon digest, **4** Goldilocks field elements) as field 7 **immediately after** `npk_commit` and **before** `consumed_pubkey`:

| Region | Elements | Notes |
|--------|----------|-------|
| ProofData fields 1–5 (Poseidon) | 20 | unchanged |
| `npk_commit` (SHA-256, 8 × u32 LE limbs) | 8 | unchanged |
| **`redeem_commitment` (Poseidon, 4 elements)** | **4** | **new — field 7** |
| `consumed_pubkey` | 8 | unchanged position after ProofData |
| `network_id` | 4 | unchanged last application PI |
| **Total application PI** | **44** | was 40 on v1 |

A conforming verifier reads `serialize(ProofData_v2)` from the first **32** public-input elements' encodings (20 + 8 + 4), `consumed_pubkey` from the next **8**, and `network_id` from the final **4**.

**`C_balance` re-pin (MUST — M-02).** `C_balance` **cannot** remain byte-identical under a v2 `C`. It recursively verifies a `C` proof under pinned `C` verifier data (parent specification.md §783 / §1092), so a new v2 `C` changes `C_balance`'s embedded verifier data and digest. **Both** `C` and `C_balance` receive new v2 digests: `circuit_digest(C)` **and** `circuit_digest(C_balance)` **MUST** be re-pinned for the v2 release (one pair per network tag). There is **no** "C_balance unchanged by TS3" claim.

**`genesis_tag`.** `AssetIdV3` reuses the v1 `genesis_tag` value: the fixed constant ASCII string **`zkCoins/v1/genesis`** (specification.md §1.4). Do **not** invent a new genesis tag for TS3.

**Reused v1 surface (MUST NOT change).** v2 reuses v1's `m_state` strings, network tags (`zkCoins/v1/mainnet` \| `testnet` \| `regtest`), activation parameters, and accumulator namespace **unchanged**. The **only** circuit-surface additions for TS3 are: the `redeem_commitment` field, the TS3 mint/redeem branches of `C`, the recursive LCP interface consumed by clause (e) (`MoveToBacked` confirmation), and the re-pinned `C_balance` verifier data. A new `circuit_digest(C)` **and** a new `circuit_digest(C_balance)` **MUST** be pinned for the v2 circuit (one pair per network tag).

**LCP consensus / S2C inputs (MUST pin).** The following are consensus parameters of the v2 release (circuit constants and/or S2C-relevant public inputs of `C_lcp` / the mint branch):

- LCP **checkpoint header** hash (and its height);
- **`D_mint`** and optional upper slack **`S`** (§3.3(e), §4.4). There is **no** freshness window `W`.

**Recursion-only values (MUST NOT enter on-chain public inputs).** The redeem-branch values required by the reimbursement statement (In/Out/redeem_amount openings, recursive proof of the TS3 redeem branch — §4.3.2) are exposed **only** to the reimbursement / fraud circuit via recursive verification. They **MUST NOT** enter the on-chain public-input surface of `C` or of any Bitcoin-published object. A redeem transition therefore remains on-chain indistinguishable from any other transition **until** an operator's reimbursement claim marker appears (§8.2).

---

## 4. Bridge profile — Glock-based reserve (the off-circuit half)

### 4.0 Construction decision and maturity gate

**Decision (2026-06-06, user; recorded in bitvm-bridge-research.md):** the zkBTC bridge is built on **Glock** — no BitVM2 intermediate, no federation-multisig V0.

**Rationale (facts + design choice):**

| Claim | Status | Source |
|-------|--------|--------|
| Glock fraud proof reduces to a single 64-byte Schnorr signature | Unaudited construction claim | `bitvm-bridge-research.md` (cites ePrint 2025/1485 / Alpen Glock blog); report-alpen supports "signature as fraud proof" without pinning 64 bytes |
| Projected on-chain efficiency vs BitVM2 | Unaudited vendor projections — **both** figures retained | report-alpen: **up to ~1000×**; `bitvm-bridge-research.md`: **430–550×** (Glock25 variant claims 550×). Do **not** silently pick one |
| Eagen / Linus author-cluster alignment with Shielded CSV | Research note | `bitvm-bridge-research.md` (Argo ePrint 2026/049; Ideal Group cluster) |
| Strata is the reference Glock deployment path | Fact (Alpen direction) | Alpen docs; report-alpen |
| BitVM2/Clementine parameters | Reference baselines only | report-citrea |

**Verifier abstraction.** The verifier is behind a trait. **Glock is normative.** BitVM2 / Clementine values appear only as **parameter and economics reference baselines**, not as inherited protocol properties.

#### Maturity gate (blocking — design document, not build order)

Until **all** of the following clear, this document is a design specification only; no production zkBTC launch and no build-order commitment:

| # | Gate | Notes |
|---|------|-------|
| M1 | Glock published mainnet + public audit | No mainnet bridge as of research date; audits ongoing for Alpen stack |
| M2 | Live Glock reference deployment (Strata or equivalent) | Signet / testnet progress is not sufficient alone |
| M3 | Demonstrated Plonky2 → DV-Pari conversion of the zkCoins compliance predicate | Open; needs work with Eagen / Linus (bitvm-bridge-research.md) |

### 4.1 Roles

| Role | Function |
|------|----------|
| **User / Minter** | Requests peg-in by depositing; holds and transfers zkBTC; initiates redeem and submits opening + payout template. Any depositor **MAY** mint under the asset's mode (§3.2) |
| **Gatekeeper** (optional) | Per-mint quality authority **and canonical-chain anchor** when `gatekeeper ≠ 0³²`: source-of-funds screening + vault legitimacy vouch + **withholds `Pk_mint` signature until `MoveToBacked` is confirmed on its own canonical Bitcoin view** (R-04); produces `Pk_mint` nullifier (approval = admission). **No** peg-out role |
| **Operators** | **N-of-N** co-sign the **pre-signed Glock graph** at setup (`MoveToBacked`, claim/challenge/payout connectors — **no** cooperative-refund leaf on the backing-only vault), then **delete** signing shares (MUST — NEW-01: presigning set is N-of-N, not t-of-n); establish Glock garbling pairs; front peg-out BTC from own funds; claim vault reimbursement along the pre-signed graph only (**no live vault CHECKSIG** — NEW-01). Aggregate keys **MUST** be in `operator_set_root` for this asset |
| **Watchtowers / challengers** | Challenge false claims along established garbling paths (see open dependency (a)) |
| **Security council / admin keys** | **None.** Deliberate divergence from Citrea and Strata reference deployments |

Holders **MAY** join as operators at setup (self-fronting), subject to the cost note in (b).

#### Glock-specific role notes (open dependencies — not assurances)

**(a) Permissionless challenging is NOT automatic under Glock.** Glock's DV-SNARK is a **designated-verifier** construction. A watchtower is another operator holding an established garbling pair, not an arbitrary third party. Permissionless challenging is Alpen roadmap language ("next frontier"), not a current documented property. This document labels it an **open dependency**. Sources: report-alpen §2.2 / §5; Alpen "Inside Alpen 2025" blog; Glock ePrint 2025/1485.

**(b) Self-fronting is costlier than under MuSig2.** Operator onboarding requires **pairwise** garbled-circuit setup with every other operator — **O(N²)** garbling — not merely co-signing a MuSig2 aggregate. "Large holders join as operators" is a heavier commitment than Clementine-style self-operation. Re-assess feasibility honestly at launch; do not assume retail holders will self-front.

**(c) No-council diverges doubly from the reference deployment — closed by graph-level claim serialization.** Strata carries a **Payout Administrator** specifically against the documented **watchtower one-shot** weakness: a single successful counterproof may permanently weaken a watchtower versus that operator; the PA can burn a connector to block payout (report-alpen §3.2 / §4; Alpen protocol-administration docs). Without a PA, "claims become void" and "claim-gating below capacity" are **not** enforceable in a councilless presigned-graph system (nobody can halt others' presigned claims; K parallel claims would consume K one-shots before slash #1).

**Normative Glock-graph construction requirement (replaces the Strata Payout-Administrator function with graph structure):**

- **Per-operator claim serialization:** each operator's claims are chained through a **sequencing connector** so claim `N+1` is spendable only after claim `N` is resolved (reimbursed or slashed).
- A successful counterproof **slashes the operator's bond and burns the sequencing connector**, which really ejects the operator (no further claims possible).
- Consequence: one operator consumes **at most one** watchtower one-shot before removal. The independent-watchtower floor (§4.4) therefore bounds **independent operators**, not sequential claims of one operator.

This is a technical hole closed by graph structure, not a style point.

### 4.2 Peg-in (permissionless mint; optional gatekeeper)

Numbered happy path (**deposit taproot** → co-signed **`MoveToBacked`** → **backing-only vault output** → deep mint). These are two distinct UTXOs with cleanly separated rights (R-01 inverted binding; analogous to Clementine's MoveToVault-before-refund, but named `MoveToBacked` here because the output is permanently backing-only):

1. **Deposit preparation (deposit taproot).** The minter constructs a **deposit taproot** address (what the user pays to; pre-`MoveToBacked`). Its script tree includes:
   - vault / bridge leaf consistent with spending into the pre-signed `MoveToBacked` for an `agg_key` admitted by this asset's `operator_set_root` (N-of-N MuSig2 / graph deposit path as required by the graph);
   - **co-sign gate** for firing `MoveToBacked` (MUST — INV-01 consent + anti-griefing): the **depositor's co-signature is required in both modes**; in **gatekeeper mode** the **gatekeeper's co-signature is additionally required** (anti-griefing after refusal). Implementation: a co-sign tapleaf or additional required signature(s) on the pre-signed `MoveToBacked` path;
   - `recipient_commitment` leaf (§3.3(g));
   - in **no-gatekeeper** mode: `depositor_base_commitment` leaf (§3.2.1.2) — **MANDATORY**;
   - **depositor refund leaf** with `OP_CSV` of `refund_timelock` blocks paying the minter (`refund_timelock` is a bridge-epoch parameter — §4.4 — not part of `asset_id`). This leaf is the depositor's **only** unilateral reclaim path and is used **only if `MoveToBacked` never happens**.
2. **User deposit.** Minter broadcasts a Bitcoin transaction paying exactly one allowed denomination amount to that deposit taproot.
3. **Presign (MUST — NEW-01).** Operators generate and **N-of-N** **pre-sign the entire per-deposit Glock transaction graph** (`MoveToBacked`, claim/challenge/reimbursement/payout connectors — **no** cooperative-refund transaction on the backing-only vault). Content is fixed at setup → txids fixed → the downstream reimbursement graph stays pre-signable. After setup signatures are complete, per-signer signing shares for those graph transactions **MUST** be **deleted**. The presigning set is **N-of-N**, not a `t < N` threshold (NEW-01 — §2.1).
4. **`MoveToBacked` (MUST — R-01 / R-04 inverted binding + INV-01 consent).** Operators (with the **co-sign gate** of step 1: **depositor always**; **gatekeeper also** in gated mode) execute **`MoveToBacked`**: an **ordinary pre-signed, nullifier-free graph transaction** that spends the user's deposit output **through the vault leaf under the N-of-N (Glock aggregate) signature produced at setup** into a **backing-only** vault UTXO whose scriptPubKey is **byte-equal** to `instantiate(vault_template, asset_id, agg_key, epoch)`. `MoveToBacked` **consumes** the deposit output and thereby **extinguishes** the deposit-taproot refund leaf. Bitcoin UTXO exclusivity is the arbiter between `MoveToBacked` and the deposit refund leaf: `MoveToBacked` **MUST** fire before `refund_timelock`, exactly like Clementine's MoveToVault-before-refund.
5. **Backing-only vault output (MUST — R-01 / NEW-01 / B-01).** The resulting **vault output** (the mint anchor, post-`MoveToBacked`) carries **NO depositor refund leaf and NO cooperative refund leaf**. Its tapleaves are only: the operator/reimbursement leaves + claim/challenge/sequencing connectors (NEW-01 form: pre-signed graph commitments, **no live `agg_key` CHECKSIG**, CSV = Glock claim/challenge windows — B-06 / §4.4) and the `asset_id ‖ epoch` commitment leaf (§3.1.1). There is **no** mint-window CSV formula and **no** refund-vs-mint-window race (there is no refund path on this output).
6. **Deep finality window.** `MoveToBacked` becomes mint-eligible only when confirmed at depth **≥ `D_mint`** (optionally ≤ `D_mint + S`) on the chain used for the LCP (§3.3(e), §4.4). Long finality is acceptable per REQ-4. **In gatekeeper mode**, mint settlement further requires the gatekeeper's **own canonical Bitcoin view** to show the same confirmation (step 7 / R-04).
7. **TS3 mint.**
   - **Gatekeeper-gated (MUST — R-04 canonical anchor):** the gatekeeper verifies the mint's witness/inputs (source-of-funds, LCP-proven `MoveToBacked` to the asset's instantiated backing-only vault, committed recipient, `operator_set_root` membership against the asset-bound root — §3.2.1.1) **and**, on its **own canonical Bitcoin view**, that (i) `MoveToBacked` is confirmed to depth ≥ `D_mint` on the **canonical** chain and (ii) the deposit output was **not** refunded on the canonical chain; **only then** does it sign `m_state` under `Pk_mint` (approval = nullifier admission; **withhold until canonical**). The final proof `C` is constructed afterward embedding that signature. Clauses (a)–(h) are proven against the **vault outpoint** (N-of-N witness + instance byte-equality + recursive `operator_set_root` equality + `MoveToBacked` depth ≥ `D_mint`). The one-shot mint nullifier `(Pk_mint, R)` is published. Co-signed `MoveToBacked` alone does **not** settle a mint — the gate is the withheld final mint signature.
   - **No-gatekeeper:** the depositor signs under depositor-anchored `Pk_mint` (§3.2.1.2); same clauses (a)–(h) with `depositor_base` opening. **Honest limitation:** no external canonical observer — private-fork amortization is **not** closed for pooled fungible reserves (§3.2.1.2, §6.4); **MUST NOT** be marketed as trust-minimized backing.
   - Coin delivery uses ordinary zkCoins delivery to `recipient`. Receivers/bridge **MUST NOT** re-check host-side freshness or vault unspentness: the mint LCP already proves `MoveToBacked` confirmation in-circuit (§3.3.2); canonicity binding to the Bitcoin tip is the gatekeeper's mint-time duty when designated.

**Ordering rule and consented irrevocable contribution residual (R-01 / INV-01).** After `MoveToBacked` there is **no unilateral depositor reclaim** and **no cooperative refund** of the vault-backed BTC. The depositor's unilateral protection is the **pre-`MoveToBacked` deposit-taproot refund** only. If `MoveToBacked` fires but the mint never settles (e.g. gatekeeper/operator fails after `MoveToBacked`), the vaulted BTC is **not** merely frozen recoverable BTC: because reimbursement is cross-graph (any same-asset in-set vault can back a redeem), it becomes an **irrevocable, consented contribution to the shared reserve** and **MAY** be redeemed by another holder — deliberately, so R-01 cannot re-open one level deeper with a refund race. Because `MoveToBacked` fires only with the **depositor's co-signature in both modes** (and the gatekeeper's co-signature additionally in gated mode — step 1 / 4), this contribution is **consented**, not imposed (cross-ref §4.5 no-council / operator-liveness class; §5 residual list). In gatekeeper-gated mode this is an accepted **gatekeeper-liveness residual at entry** (the quality gate *and* canonical-chain anchor *is* a mint-time liveness dependency — §6). In no-gatekeeper mode the residual is depositor operational (co-sign `MoveToBacked` only when accepting the contribution risk / ready to mint). **Attack closed by R-01:** a raw vault refund leaf at `refund_timelock` (~200 blocks) would mature well before the mint window (~2016 blocks), letting a depositor mint **and then** refund → destroy backing; separating the UTXOs and making the post-`MoveToBacked` output permanently backing-only extinguishes that path.

**Failure table:**

| Failure | Outcome |
|---------|---------|
| Gatekeeper refuses **before** `MoveToBacked` (does not co-sign) | Minter reclaims via **deposit-taproot** refund leaf after `refund_timelock`; BTC never stuck on refusal; third parties cannot force `MoveToBacked` (gatekeeper co-sign required in gated mode) |
| Depositor withholds co-signature on `MoveToBacked` | `MoveToBacked` does not fire; minter may reclaim via deposit-taproot refund after `refund_timelock` (INV-01: contribution never imposed) |
| Gatekeeper withholds mint signature after canonical check fails / not yet ready | No mint settles; if `MoveToBacked` already fired with depositor (+ gatekeeper) co-sign, BTC is an irrevocable consented reserve contribution (INV-01) |
| Gatekeeper/operator fails **after** `MoveToBacked` (mint never settles) | Vaulted BTC is an **irrevocable, consented contribution to the shared reserve** (cross-graph redeemable by others — not merely frozen recoverable BTC) |
| Operators fail to fire `MoveToBacked` | Minter reclaims via **deposit-taproot** refund leaf after `refund_timelock` |
| Mint settles | Minter/recipient holds zkBTC; backing-only vault remains under pre-signed claim/challenge graph for later peg-out (**no** live CHECKSIG) |

**Plain statement:** peg-in **depends on the gatekeeper only when one is designated** — that **is** the optional quality gate **and** the canonical-chain anchor for mint settlement (including the gated `MoveToBacked` co-sign and the withheld `Pk_mint` signature until canonical confirmation). REQ-4 concerns exit only (gatekeeper-independent). Trust-minimized pooled backing effectively **requires** that gatekeeper (or equivalent canonical oracle) — §5 / §6.4.

#### 4.2.1 Deposit taproot and vault output structure (normative outline)

Exact script templates are launch-time artefacts of the Glock graph compiler (`PROVISIONAL` byte pin — NEW-03). The normative **semantic** requirements on the structure are:

1. **Deposit vault path** spends only into the **pre-signed** `MoveToBacked` under the N-of-N aggregate / MuSig2 path as required by the reference construction — **not** via the user's refund leaf. The aggregate key **MUST** be admitted by `operator_set_root`. Signatures for `MoveToBacked` are produced at setup and the signing shares **MUST** then be deleted (NEW-01). Firing **MUST** require the co-sign gate of §4.2 step 1: **depositor co-signature in both modes** (INV-01); **gatekeeper co-signature additionally** in gatekeeper mode.
2. **Recipient commitment path or leaf data** carries `recipient_commitment` so clause (g) can open it; the commitment **MUST** be fixed before the user signs the deposit.
3. **Depositor-base commitment (no-gatekeeper mode)** carries `depositor_base_commitment` so clause (b) can open it; **MANDATORY** when `gatekeeper = 0³²`.
4. **Deposit refund path (deposit taproot only — R-01)** pays the minter after `refund_timelock` CSV **if and only if** `MoveToBacked` does not complete. `MoveToBacked` consumes this output and extinguishes the refund. This is the depositor's **only** unilateral protection.
5. **Vault output script** after `MoveToBacked` **MUST** be byte-equal to `instantiate(vault_template, asset_id, agg_key, epoch)` (§3.1.1 — NUMS internal key + ordered pre-signed-graph tapleaf set; **no** depositor refund leaf; **no** cooperative refund leaf). Byte-equality is relative to the launch-pinned template (NEW-03).
6. **All vault-output value-moving spend paths MUST be CSV-locked to the Glock claim/challenge windows** (B-06 / §4.4) after `MoveToBacked` confirmation (operator/reimbursement leaf, claim/sequencing connectors). **MUST NOT** include a depositor refund leaf. **MUST NOT** include a cooperative refund leaf. **MUST NOT** include a live free-form `agg_key` CHECKSIG (NEW-01). There is **no** `D_mint + S + W + 1` mint-window CSV term.
7. **Internal key (MUST — NUMS on vault).** The vault output's internal key **MUST** be the unspendable NUMS point of §3.1.1 so there is **no key-path spend**. Deposit outputs **SHOULD** likewise use NUMS or equivalent so that no single party can bypass script paths — matching Strata/Clementine deposit style (report-alpen deposit flow; report-citrea deposit flow).
8. **Pre-signed graph only (MUST — NEW-01).** Every vault spend is a pre-committed graph transaction (reimbursement claim/challenge/payout connectors), each authorised by setup-time N-of-N signatures with keys then deleted. A live CHECKSIG by the current key-holders is **forbidden**. The presigning set is **N-of-N**, not t-of-n.

### 4.3 Peg-out (gatekeeper-independent)

Numbered happy path:

1. **Consolidate.** Holder consolidates internally (shielded transfers) to an available payout denomination of the current epoch.
2. **Redeem transition.** Holder proves a redeem (§3.5): burns the denomination, sets non-zero `redeem_commitment` (incl. `max_fee` with `max_fee < redeem_amount`), anchors `(Pkᵢ, Rᵢ)`.
3. **Request.** Holder submits the opening `(redeem_amount, btc_recipient, max_fee, redeem_blind)` and a payout template (`SIGHASH_SINGLE|ANYONECANPAY`, P2TR to `btc_recipient`, amount ≥ `redeem_amount − max_fee`) to **any** operator.
4. **Front.** Operator fronts BTC from **own funds** (not the vault) to the payout template, choosing an actual fee `≤ max_fee`. The mining fee of the payout transaction is funded by the operator's own input/anchor — **never from vault value**.
5. **Claim.** Operator claims vault reimbursement via the Glock claim / challenge machinery (a **pre-signed graph** path — NEW-01; never a live vault CHECKSIG). The claim transaction **publicly commits the claim-marker tuple `(Pkᵢ, Rᵢ, payout_txid, payout_vout)`** on Bitcoin as a first-occurrence marker in the claim-marker namespace (logical claim-consumption + payout first-marker — §3.5.5 NH-02 / NEW-02). The operator does **not** spend the recipient's payout UTXO. Claims of one operator are **serialized** through that operator's sequencing connector (§4.1(c)). The claim **MUST** prove the claimant funded the payout by **value-accounting over bonded inputs** (§4.3.2 item 12 / NEW-02).

**Fraud statement (operator reimbursement claim):** the full conjunct list of §4.3.2 (accumulator + S2C + recursive `C` verification + consumed-key binding + redeem branch + asset binding + value preservation + canonical payout under `max_fee` + claim-marker uniqueness over the **valid unchallenged** set + claimant-funded payout by value-accounting). Verified via the DV-SNARK / garbled path; wrong claims are killed by a single Schnorr signature as fraud proof (Glock property; `bitvm-bridge-research.md` records the 64-byte form).

6. **Reimbursement.** After the challenge window without successful challenge, operator takes reimbursement from the vault along the pre-signed graph: the claim **MUST** remove **exactly `redeem_amount`** from the vault (NH-01) — vault-input value minus change-back-to-the-same-vault-descriptor equals `redeem_amount`, with the change output constrained back to the (in-set) vault. The mining fee is funded by the operator's own input/anchor, **never from vault value** (else backing erodes below remaining supply). A second claim for the same `(Pkᵢ, Rᵢ)` or the same payout outpoint is counterprovable by inclusion of an earlier **valid, unchallenged claim-marker** (logical first-marker, not a UTXO spend of the payout; slashed markers excluded — NEW-02).
**The gatekeeper appears nowhere in this path (REQ-4).** Exit is gatekeeper-independent and operator-liveness-bounded.

**Liveness residual (honest):** exit requires ≥ 1 live, liquid, willing operator. Landscape shortlist 1 marks this **PARTIAL**; bitvm.org states that without at least one honest operator "the funds become unspendable eventually" (landscape report §2.1 citing `https://bitvm.org/bitvm2`). Dishonest operators cannot steal under 1-of-N setup honesty + functioning watchtowers; worst case under that model is freeze / burn of affected deposits, not silent theft.

**Cross-graph note.** Because peg-out is cross-graph, the fraud statement's asset-equality conjunct (B-04 / §4.3.2 item 6) plus `operator_set_root` membership together ensure a redeem only draws honest, in-set vaults of the same asset.

#### 4.3.1 Peg-out failure modes

| Scenario | Outcome | Residual class |
|----------|---------|----------------|
| Assigned operator offline | Reassignment after timeout (§4.4); another operator fronts | Liveness delay |
| All operators refuse one holder | Exit stalls until some operator serves or self-fronting holder acts | Liveness / ransom |
| All operators disappear | Vault UTXOs locked under presigned paths; no pure user self-spend without covenants (§10) | Liveness freeze |
| Operator claims without valid redeem | Watchtower challenge; single-Schnorr fraud-proof path; bond slash + sequencing-connector burn | Safety (if watchtowers work) |
| Watchtower one-shot vs one operator | Sequencing connector ejects the operator after one successful counterproof (§4.1c); floor covers independent operators | Safety design hole only if floor of independent operators fails |
| Double reimbursement claim for same `(Pkᵢ, Rᵢ)` | Counterprovable by Bitcoin inclusion of earlier **valid unchallenged** claim-marker; slashed markers do not block retry (NEW-02) | Safety (1-honest watchtower) |
| Payout outpoint reused across claims | Counterprovable by first-marker of earlier valid claim-marker tuple (NH-02; logical marker, not UTXO spend); claimant must fund by value-accounting over bonded inputs (NEW-02) | Safety (1-honest watchtower) |
| Free-rider claim on another's payout | Fraud statement fails value-accounting: sum of inputs signed by claimant's bonded key does not cover payout + fee; non-bonded inputs are value-ignored (NEW-02) | Safety |
| Gatekeeper offline or hostile | **No effect** on peg-out | REQ-4 property |

#### 4.3.2 Fraud-statement witness (bridge circuit)

The Glock/DV-SNARK path that authorises operator reimbursement **MUST** verify a statement equivalent to the **old accumulator + S2C checks PLUS the additions below** — a full conjunct list, not a replacement of the accumulator checks. All of the following **MUST** hold:

```
Exists opening (asset_id, redeem_amount, btc_recipient, max_fee, redeem_blind)
and a redeem transition proof such that:

  1. (Pkᵢ, Rᵢ) is first-occurrence completed on the Bitcoin-derived zkCoins
     nullifier accumulator.
  2. Rᵢ S2C-opens H(ProofData) containing redeem_commitment, where
     redeem_commitment = Hc("zkCoins/v2/RedeemCommit",
                            asset_id ‖ redeem_amount ‖ btc_recipient
                            ‖ max_fee ‖ redeem_blind).
  3. Recursive verification of the redeem transition's C proof under the
     pinned v2 verifier data (parent specification.md §5.6 requires this).
  4. Pkᵢ == redeem_proof.consumed_pubkey
     (§5.6 anti-naked-nullifier binding; specification.md ~2094).
  5. The verified transition took the TS3 redeem branch:
     In(zkBTC) == redeem_amount and Out(zkBTC) == 0
     (proven via the recursive proof — see exposition note).
  6. asset_id in the opening equals the zkBTC asset_id bound to this vault
     (via vault_template / instantiate and operator_set_root; MUST — else a
     self-issued cheap foreign TS3 asset with its own vault and redeem
     could drain this asset's vault). The vault being drawn from MUST have
     agg_key admitted by this asset's operator_set_root.
  7. Fee bounds (NH-03): max_fee < redeem_amount, and
     redeem_amount − max_fee is computed as an exact non-negative
     wide-integer (parent §2.6 gadgets) — no underflow, no zero payout
     from wrapping.
  8. The Bitcoin payout output is P2TR(btc_recipient) with amount
     ≥ redeem_amount − max_fee, confirmed on the canonical chain
     (the receiver's / challenger's own view at deep depth — NOT
     "the operator's claimed chain").
  9. Payout binding (NH-02 — logical claim-marker, not UTXO spend): the
     claim publicly commits the claim-marker tuple
     (Pkᵢ, Rᵢ, payout_txid, payout_vout) as a first-occurrence marker
     in the claim-marker namespace; that payout outpoint's confirmation
     height is strictly greater than the first-occurrence height of
     (Pkᵢ, Rᵢ); a second claim reusing the same (Pkᵢ, Rᵢ) or the same
     (payout_txid, payout_vout) is counterprovable by inclusion of an
     earlier **valid, unchallenged** marker. The operator does NOT spend
     the recipient's UTXO.
 10. Claim-marker uniqueness over the valid set only (NH-02 / NEW-02 —
     §3.5.5): no prior **valid, unchallenged** reimbursement
     claim-marker carries the same (Pkᵢ, Rᵢ) or the same
     (payout_txid, payout_vout). **Exclusion rule (MUST):** a marker that
     is **slashed**, **successfully counterproved**, or otherwise
     **failed** under the challenge path is **excluded** from the
     uniqueness set and MUST NOT block an honest retry. Only a valid,
     unchallenged claim consumes the redeem ID / payout outpoint for
     uniqueness.
 11. Value preservation (NH-01): the reimbursement removes exactly
     redeem_amount from the vault —
       vault_input_value − change_to_same_vault_descriptor
         == redeem_amount
     with the change output constrained back to the same in-set vault
     descriptor. The mining fee is funded by the operator's own
     input/anchor, NEVER from vault value.
 12. Claimant funded the payout by value-accounting (MUST — NEW-02):
     the fraud statement MUST prove the payout is funded by inputs the
     claimant controls. Value-accounting rule:
       - each input signed by the claiming operator's bonded key
         (the key / bond identity registered for this operator in the
         pre-signed graph) contributes its full value to the claimant's
         funding sum;
       - inputs NOT signed by the claimant's bonded key are
         value-ignored (contribute zero to the claimant's funding);
       - the summed claimant-controlled value MUST cover
         payout amount + mining fee.
     Mere presence of one bonded-key input is NOT sufficient: under
     SIGHASH_SINGLE|ANYONECANPAY a front-runner could attach a small
     bonded input to a tx mostly funded by the real operator and steal
     reimbursement. Value-accounting closes that hole.
```

**Fee rule (normative).** `max_fee` is a **ceiling** committed inside `redeem_commitment` with `max_fee < redeem_amount`. Payout **MUST** pay `btc_recipient` at least `redeem_amount − max_fee` (exact non-negative wide-integer subtraction). This is provable and market-viable (the operator sets its actual fee ≤ `max_fee` at fronting time). An **exact** fixed fee **MUST NOT** be bound: a fee spike between redeem burn and fronting would otherwise leave the coin permanently unservable (loss of funds).

**Value-preservation rule (normative — NH-01).** Reimbursement **MUST** remove **exactly `redeem_amount`** from the vault. Any wording that takes `redeem_amount + fee` from the vault is **incorrect**: the fee is operator-funded. Otherwise backing erodes below remaining circulating supply.

**Exposition note (MUST — protects §8.2 until claim).** The redeem-branch values (`In`/`Out`/`redeem_amount`/opening) are exposed **only to the reimbursement circuit via recursive verification**, **NEVER** as on-chain public inputs of `C`. A redeem transition therefore stays on-chain indistinguishable from any other transition **until** the operator's reimbursement claim marker appears; that marker then links the redeem to its payout (§8.2). Cross-check: §3.7.2 "recursion-only values".

Exact packing into DV-Pari public inputs is conversion-path work (§11). The token standard fixes the **semantic** statement so the conversion cannot silently weaken it.

### 4.4 Parameters (normative table)

Denominations, `refund_timelock`, mint-depth parameters, and related deposit-epoch economics are **per-deposit-epoch bridge parameters**, not `IssuanceTerms_v3` fields. Changing them for **new** deposits does not change `asset_id`. Existing vaulted deposits keep the parameters of their epoch's presigned graph. (`refund_timelock` governs the deposit taproot only — consistent with denominations staying outside token identity.) There is **no** mint-freshness window `W` and **no** host-side `tip_height` rule.

| Parameter | Value | Reference baseline | Rationale |
|-----------|-------|--------------------|-----------|
| **Denominations (start set)** | **{0.1, 1, 10} BTC** | Strata testnet 2 BTC; Clementine 10 BTC | High minima allowed by REQ-4; retail-relevant without the smallest tier |
| **0.01 BTC denomination** | **Gated** behind maturity gate | Earlier research sketches used 0.01 | Projected Glock dispute cost ~35k–100k sats (`bitvm-bridge-research.md` Costs table) is 3–10% of a 0.01 BTC deposit; fee-spike / challenger-collateral weakness hits small denominations hardest; per-deposit graph setup scales with deposit count (100× more graphs per BTC at 0.01 vs 1). Enable **only after mainnet evidence of Glock economics** |
| `refund_timelock` | 200 blocks (`PROVISIONAL`) | Clementine / BITVM_BRIDGE | ~33 h unilateral user reclaim on **deposit taproot only** if `MoveToBacked` stalls; **not** on vault output (R-01); **not** in `asset_id` |
| `D_mint` | ~2016 blocks (`PROVISIONAL`) | Bridge security horizon; long finality OK per REQ-4 | Mint LCP: `MoveToBacked` confirmation depth lower bound (§3.3(e)); private-fork mining for mint value economically irrational at this depth |
| `S` | Launch param (`PROVISIONAL`, optional) | — | Mint LCP depth upper slack (when configured: depth ∈ `[D_mint, D_mint + S]`) |
| Vault spend-path CSV | Glock claim/challenge windows (B-06; same order as claim challenge window below) (`PROVISIONAL`) | Strata / Glock claim graph | Operator/reimbursement + claim/sequencing connectors only — script-path under NUMS; pre-signed graph (no live CHECKSIG); **no** depositor or cooperative refund leaf on backing-only vault (R-01 / NEW-01); locked after `MoveToBacked`. **Not** a mint-window formula |
| Operator reassignment timeout | 504 blocks (`PROVISIONAL`) | Strata | ~3.5 days before reassignment |
| Claim challenge window | 1064 blocks (`PROVISIONAL`) | Strata (~1.4 weeks) | Long windows OK per REQ-4; also pins the vault claim/challenge CSV order of magnitude (B-06) |
| Operator bond | Glock-scale; exact = launch param (`PROVISIONAL`) | Clementine ~2 BTC (BitVM2-era); Alpen BitVM2 pain ~5 BTC class | Must match Glock slash economics once published; slash burns sequencing connector (§4.1c) |
| Payout fee | Market-set under `max_fee` ceiling committed in `redeem_commitment` with `max_fee < redeem_amount`; baseline 0.003 BTC (`PROVISIONAL`) | Strata testnet | Operator keeps fee ≤ `max_fee`; fee never taken from vault (NH-01); no exact fixed fee bound into the commitment |
| Minimum independent watchtower count | **≥ 3** (`PROVISIONAL` floor) | Strata PA covers one-shot; we replace PA with sequencing connectors | Floor bounds **independent operators** (each consumes ≤1 one-shot before ejection), not sequential claims of one operator (§4.1c) |

Mark every value pending Glock-mainnet reality **`PROVISIONAL`** until launch parameters are fixed against live economics.

### 4.5 No-council trade-off

This profile has **no** emergency multisig, **no** admin keys, and **no** in-place upgrade path for a live vault graph. Combined with NEW-01, the vault **presigning set is N-of-N** (not t-of-n) and there is **no live threshold signing path** that a current operator coalition could use to improvise vault spends: every vault movement is a pre-signed graph transaction whose setup keys are deleted.

**Consequence of a critical bug** in circuit, graph, or garbling: affected deposits can irreversibly freeze (BitVM-family property: under 1-of-N honesty, worst case is burn / freeze, not silent theft by a minority). Without a Security Council, there is no trusted party that can sweep funds to a Safe Harbor. If `MoveToBacked` fires but the mint never settles, the backing-only vault is an **irrevocable, consented contribution to the shared reserve** (no cooperative refund, no depositor vault refund — R-01 / INV-01; may be consumed by another holder's cross-graph redeem — §4.2 / §3.3.2 / §3.4), not recoverable via a live multisig or depositor reclaim.

**Required discipline before mainnet:**

- §1.7.8-grade freeze discipline on the v2 circuit surface;
- differential testing of LCP and mint/redeem branches;
- external audit gate on the v2 circuit, Glock stack, and **pre-signed** graphs **before** mainnet (including verification that setup signing shares are deleted and that no live `agg_key` CHECKSIG leaf remains on vault outputs);
- the §4.1(c) per-operator **sequencing connector** plus the §4.4 independent-watchtower floor close the one-shot weakness that Strata's Payout Admin covers (graph structure, not an admin key).

**Upgrades:** new-vault migration only — new deposits into a new graph / new `vault_template` or new `operator_set_root` (new `asset_id` if those bound fields change); holders redeem-and-re-peg to move. Never in-place rotation of a live vault's admin keys or of a gatekeeper (gatekeeper rotation = new asset — §3.1).

**Comparison:** Citrea's Security Council (3-of-5) **can** move funds in emergency / upgrade paths (report-citrea §4.2 / §4.4). This design refuses that trust root deliberately and pays for it with irreversibility.

### 4.6 Launch gates (normative)

Two blocking gate families. Both **MUST** clear before any public claim that a deployed asset is **zkBTC** under this specification.

#### (A) REQ-4 gates

Without these, the REQ-4 claim is **false** (a mint-time party re-enters on the safety or liveness axis of exit).

1. **Operator-set majority foreign to any single mint-time party at vault genesis.** Gatekeeper-affiliated (or, in no-gatekeeper mode, any single organiser-affiliated) operator keys **MUST** be strictly fewer than half of the operator set bound in `operator_set_root`. Bootstrap capture (one organisation == entire operator set) reintroduces that party's control of exit liveness and, with collusion, safety edges — and would also make the 1-of-N honesty assumption vacuous (Part 2).
2. **Setup integrity (Glock form).** For every dispute path, there **MUST** be a minimum number of **independent garbler counterparties**, with normatively fixed cut-and-choose parameters. No single mint-time party **MUST** be the only counterparty in any garbling pair. Rationale: toxic-waste / forgery control — a captured setup lets the holder of the setup secret forge or void fraud proofs and drain the vault, which is a dependency on the **safety** axis.  
   **Open point:** IF a global circuit-specific setup artifact also exists in DV-Pari (to be verified against the Glock paper — part of the unproven conversion path), the classic "MPC ceremony with independent contributors" gate **MUST** apply there too. Do not abstract this uncertainty away.
3. **Documented holder → operator onboarding** (self-fronting), acknowledging the **O(N²)** pairwise garbling cost of §4.1(b).
4. **Challenger economics documented.** Name deployed Clementine's self-funded-challenge gap (challengers must self-fund; cross-chain reimbursement not deployed — report-citrea) as the **anti-pattern** to solve under Glock economics.

#### (B) Maturity gates

Restatement of §4.0 as a checklist:

- [ ] Glock mainnet live
- [ ] Glock / bridge audit published
- [ ] Reference deployment live (Strata or equivalent)
- [ ] Plonky2 → DV-Pari conversion of the zkCoins predicate demonstrated

---

## 5. Trust matrix

| Concern | What must hold | Who | Failure effect | Gatekeeper-dependent? |
|---------|----------------|-----|----------------|----------------------|
| **Reserve safety** | 1-of-N setup honesty (key deletion / correct garbling + cut-and-choose); per-operator sequencing connectors; ≥ floor independent watchtowers; sound Glock crypto; `operator_set_root` honesty basis | Operators / watchtowers / setup | False claim reimburses thief; or vault frozen | **No** (if gates A hold) |
| **Mint integrity / canonicity** | TS3 clauses (a)–(h); LCP proves `MoveToBacked` at depth ≥ `D_mint` + N-of-N; recursive `operator_set_root` equality; **and** (gatekeeper mode) gatekeeper withholds `Pk_mint` until `MoveToBacked` is confirmed on its **own canonical Bitcoin view** and the deposit is not refunded there (R-04) | Minter + **gatekeeper as canonical-chain anchor** when designated; depositor co-sign on `MoveToBacked` always (INV-01) | Unbacked mint; private-fork amortization mint; self-controlled vault; or (no-gk) non-canonical mint if operators reimburse it | **Yes for trust-minimized pooled canonicity** when designated (structurally load-bearing — R-04); structural legitimacy always via asset-bound `operator_set_root`. **No-gatekeeper: not closed** — see residual 9 |
| **Transfer** | Ordinary §2 soundness + nullifier first-occurrence | Protocol | Double-spend / invalid transfer rejected | **No** |
| **Redeem liveness** | ≥ 1 live liquid operator; bonds / fees economic under `max_fee` | Operators | Exit stalls (ransom / freeze risk) | **No** |
| **Redeem safety** | Full §4.3.2 fraud statement; claim-marker uniqueness (logical first-marker); value preservation; designated-verifier / watchtower paths | Operators / watchtowers | Unbacked vault drain | **No** (if gates A hold) |
| **Entry quality** | Gatekeeper SoF + vault legitimacy vouch (when present); else structural only | Gatekeeper / none | Tainted mint waved through; or refusal / delay with refund leaf | **Yes** when designated (by design) |

**Residual assumptions (honest list):**

1. 1-of-N setup honesty (garbling / cut-and-choose per Glock; key-deletion style covenant emulation for presigned paths) over the **asset-bound** operator set (`operator_set_root`).
2. ≥ 1 independent operator for exit liveness.
3. ≥ floor independent watchtowers (normative `PROVISIONAL` ≥ 3) **and** per-operator claim serialization (§4.1c) against the watchtower one-shot weakness.
4. Bitcoin adversary below ~45–50% hashrate for the relevant challenge horizon (Clementine / whitepaper class bounds; report-citrea).
5. Deep-finality of `MoveToBacked` at depth ≥ `D_mint` on the proven LCP chain (§3.4); residual reorg deeper than `D_mint` is D-16 class. **Canonical binding** of that chain to the Bitcoin tip is **not** in-circuit alone: in gatekeeper mode it is the gatekeeper's mint-signing duty (R-04).
6. Open dependency: permissionless challenging availability under designated-verifier Glock (§4.1a).
7. When a gatekeeper is designated: gatekeeper liveness at mint time (quality filter **and** canonical-chain anchor — §6), including the gated `MoveToBacked` co-sign and withholding `Pk_mint` until canonical confirmation. Not a custody dependency over circulating coins; **is** load-bearing for trust-minimized mint canonicity.
8. **Consented irrevocable reserve contribution residual (R-01 / INV-01):** if `MoveToBacked` fires (with **depositor co-signature in both modes**, plus gatekeeper co-signature in gated mode) but the mint never settles, the backing-only vault BTC becomes an **irrevocable, consented contribution to the shared reserve** (cross-graph redeemable by other holders) — not merely frozen recoverable BTC (§3.3.2 / §3.4 / §4.2). Unilateral escape only pre-`MoveToBacked` via the deposit refund leaf.
9. **No-gatekeeper canonical-anchor gap (R-04 hard limitation):** without a gatekeeper (or equivalent canonical-oracle role), there is **no external canonical observer** at mint settlement. Private-fork amortization against a pooled fungible reserve is **not closed**. Backing integrity then **additionally** depends on reimbursement operators refusing to reimburse against non-canonical vaults (best-effort operator-honesty / oracle assumption). This class is **materially weaker** and **MUST NOT** be presented as trust-minimized pooled backing. **A trust-minimized pooled zkBTC effectively REQUIRES a gatekeeper (or equivalent canonical oracle)** (REQ-3, §6.4).

---

## 6. Gatekeeper model and compliance

### 6.1 Why a gatekeeper

Without an entry filter, coins from a hack/theft or sanctioned sources could be minted into the shielded system and zkCoins abused for laundering. That harms **all** holders' fungibility, the token's reputation, and regulatory acceptance. The gatekeeper screens **source-of-funds** and **vault legitimacy** at entry.

**Additionally — and structurally load-bearing for pooled backing (R-04):** the gatekeeper is the **canonical-chain anchor**. The mint LCP proves `MoveToBacked` confirmed at depth ≥ `D_mint` on *some* header chain; nothing in-circuit alone binds that chain to the verifier's **canonical** Bitcoin view. Because only the gatekeeper can produce the `Pk_mint` signature (`sk_mint = sk_gk + h`) that settles the mint, and the gatekeeper **withholds** that signature until it has verified on its **own canonical Bitcoin view** that (i) `MoveToBacked` is confirmed to depth ≥ `D_mint` on the canonical chain and (ii) the deposit was not refunded there, a private-fork `MoveToBacked` yields no mint. A co-signed `MoveToBacked` alone is insufficient (setup signatures are valid on any fork). The gatekeeper's remit is therefore **both** (1) source-of-funds / vault-legitimacy screening **and** (2) the canonical-chain anchor that makes **trust-minimized pooled backing** possible. This is why the gatekeeper is **structurally load-bearing**, not merely reputational.

Permissionless minting without any quality authority is still protocol-valid (no-gatekeeper mode) but is a **materially weaker security class** (§6.4): structural deposit-backing and `operator_set_root` still prevent unbacked inflation and self-controlled-vault drains under honest LCP use, yet there is no per-mint source-of-funds filter, no per-mint legitimacy vouch, and **no external canonical observer** — so the private-fork amortization attack against a pooled fungible reserve is **not closed**.

### 6.2 Whose interest

The gatekeeper represents the interests of the **asset's existing holders** — their coins' value and fungibility depend on the token not becoming a laundering vehicle. A holder-committee threshold key (MuSig2/FROST aggregate; still a single x-only key in-circuit) operationalises "represents holders." **Threshold / FROST is allowed only for the gatekeeper key** (approval liveness; cannot create unbacked mints). The vault **presigning / operator set MUST be N-of-N** (NEW-01 — §2.1): one honest share deletion is what delivers 1-of-N setup safety; a `t < N` operator threshold would leave `N−1 ≥ t` shares able to sign after one honest deletion. For the **gatekeeper**, N-of-N is discouraged (loss of a single member key permanently disables minting; rotation = new asset); threshold (t-of-n) for the gatekeeper is **RECOMMENDED** (§2.1).

### 6.3 What the gatekeeper is NOT (the guarantee)

The gatekeeper gates **ENTRY (new mints) only**. Mechanism for each non-power:

| Claimed abuse | Why it fails |
|---------------|--------------|
| Freeze circulating coins | No gatekeeper role in §2 holder transitions |
| Claw back settled mints or transfers | No protocol clawback; coins are ordinary §2 state |
| Block transfers | Same as freeze — no gatekeeper clause |
| Block redemptions | No gatekeeper role in §4.3 peg-out; REQ-4 |
| Mint unbacked supply | Deposit-backing clauses (e)/(f)/(h); LCP + amount discipline; gated mode also withholds `Pk_mint` until **canonical** `MoveToBacked` (R-04) |
| Redirect a mint | Clause (g) recipient binding |
| Double-mint one deposit | First-occurrence on deterministic `Pk_mint` |
| Inflate beyond real deposits | Same deposit-backing + uniqueness |
| Add/remove/rotate itself in place | `gatekeeper` frozen in `asset_id`; rotation = new asset |

Even a **compromised** gatekeeper can only wave through a tainted mint (including by skipping the canonical-chain check — re-opening R-04) or burn a `Pk_mint` slot — never steal existing coins or inflate beyond circuit-enforced deposit-backing. So a gatekeeper is a **liveness dependency at mint time** and a **canonicity / entry-integrity dependency**, never a custody dependency over circulating coins or redemptions.

### 6.4 Trade-off (honest) and security classes

| Class | Gatekeeper | Operator-set binding | Source-of-funds filter | Canonical-chain anchor (R-04) | Mint-time liveness dependence |
|-------|------------|----------------------|------------------------|-------------------------------|-------------------------------|
| **Gatekeeper-gated zkBTC** | Present (`gatekeeper ≠ 0³²`) | `operator_set_root` in `asset_id` + per-mint legitimacy vouch | Yes (gatekeeper remit) | **Yes** — gatekeeper withholds `Pk_mint` until canonical `MoveToBacked` confirmation (§3.2.1.1) | Yes (gatekeeper must be online/willing to approve after canonical check) |
| **No-gatekeeper zkBTC** | Absent (`0³²`) | `operator_set_root` in `asset_id` **only** (structural) | No | **No external observer** — depositor produces mint signature; private-fork amortization **not closed** for pooled reserves | No gatekeeper dependence; depositor produces mint |

A gatekeeper adds mint-time liveness dependence in exchange for reputation assurance **and** for the **canonical-chain anchor** that makes trust-minimized pooled backing possible. A no-gatekeeper token has no such dependence but no entry filter and **no external canonical observer**.

**Prominent limitation (MUST state — R-04).** A **trust-minimized pooled zkBTC effectively REQUIRES a gatekeeper (or an equivalent canonical-oracle role)**. In no-gatekeeper mode, with `Pk_mint` anchored on the depositor's own key, the depositor produces the mint signature itself: the private-fork amortization attack is **not closed** for a pooled fungible reserve. Backing integrity then **additionally** depends on reimbursement operators refusing to reimburse against non-canonical vaults (a best-effort operator-honesty / oracle assumption). No-gatekeeper pooled mode is therefore **materially weaker** than gatekeeper-gated mode and **MUST NOT** be presented as trust-minimized backing. The gatekeeper is **structurally load-bearing**, not merely reputational.

**Ship condition for no-gatekeeper mode.** A no-gatekeeper zkBTC is shippable **only** with `operator_set_root` bound in `asset_id` (structural legitimacy). It is a **materially weaker security class** than a gatekeeper-gated one (no source-of-funds filter, no per-mint legitimacy vouch, **no external canonical observer**) and **MUST NOT** be marketed as equal or as trust-minimized pooled backing. The market chooses.

### 6.5 Competing deployments

Restatement of §2.5: because `gatekeeper` and `operator_set_root` (and `H(vault_template)`) are bound into `asset_id`, each combination is a distinct asset. Anyone can deploy a competing zkBTC with their own or no gatekeeper; wallets key by `asset_id`; adoption decides which wins.

### 6.6 Compliance surface summary

**REQ-3 rationale.** Optional gatekeeper approval at mint prevents (when designated) wash-in of tainted BTC while keeping issuance permissionless for minters, **and** supplies the **canonical-chain anchor** without which trust-minimized pooled backing is not achieved (R-04 / §6.1 / §6.4). Minting economic activity and gatekeeping remain separate roles. A gatekeeper (or equivalent canonical oracle) is effectively **required** for trust-minimized pooled zkBTC; no-gatekeeper mode remains protocol-valid as a weaker class.

**REQ-2 and REQ-4 are deliberate.** The gatekeeper **MUST NOT** be able to freeze or claw back circulating zkBTC, and **MUST NOT** be able to block a redemption. Flip side (state plainly): exits of later-sanctioned holders **cannot** be stopped either. Compliance that needs continuous transaction-level freeze would require a different product (not this one).

**What compliance retains (gatekeeper-gated assets):**

- **L1 surface:** every payout's `btc_recipient` is a public Bitcoin output; deposit provenance is screened at entry.
- **Entry refusal:** gatekeeper may refuse new mints (depositor reclaims via refund).

**What compliance does not get:**

- No transaction-level gatekeeper visibility inside the shielded zone (privacy holds for internal transfers).
- No gatekeeper veto on transfers or redemptions.

| Surface | Visible to gatekeeper / compliance function | Mechanism |
|---------|---------------------------------------------|-----------|
| Deposit UTXO | Yes (public Bitcoin) | L1 |
| Source-of-funds / KYC | Yes when gatekeeper process requires it (off-protocol) | Off-protocol |
| Mint recipient address | Bound in deposit commitment; mint goes only to that recipient | Clause (g) |
| Vault legitimacy | Gatekeeper vouch (gated) + in-circuit `operator_set_root` | §3.2 / §3.3(e) |
| Canonical `MoveToBacked` at mint | Gatekeeper's own canonical Bitcoin view (gated; withholds `Pk_mint` until confirmed) | §3.2.1.1 / R-04 |
| Internal transfers | No | Shielded §2 |
| Redeem request | No (unless gatekeeper is also chosen operator) | Off-chain to operators |
| Payout UTXO | Yes (public Bitcoin) | L1 |

### 6.7 Designed non-properties

State these so product and legal review do not invent protocol powers that do not exist:

1. **No freeze list** for circulating coins.
2. **No clawback** of settled mints or transfers.
3. **No gatekeeper signature** on redeem or payout.
4. **No selective mint redirect** after deposit (clause (g)).
5. **No in-place gatekeeper rotation** (new asset only).

---

## 7. What minters and the gatekeeper can and cannot do

### 7.1 Minter CAN

- **Deposit and request a mint** to a committed recipient (permissionless economic role).
- **Hold the minted coin** (or have it delivered to the committed recipient) and transfer freely (REQ-2).
- **Redeem** without gatekeeper cooperation (REQ-4).

### 7.2 Gatekeeper CAN (when designated)

- **Refuse / approve mints** at entry (source-of-funds + vault legitimacy).
- **See deposit provenance** on L1 and any off-protocol KYC data it requires.
- **Hold and manage `sk_gk`** under its key-management policy (including as a threshold aggregate).

**Key-management properties (normative analysis):**

- **Loss of `sk_gk`:** no **new** mints of this asset ever. Existing circulating supply and redemptions are **unaffected** (redemptions do not use `sk_gk`). For an **N-of-N** gatekeeper aggregate, loss of **any single** member key has the same permanent effect — threshold (t-of-n) is **RECOMMENDED** (§2.1 / GK-6).
- **Theft of `sk_gk`:** thief can approve mints for **future** real deposits (derive `sk_mint`, settle TS3 mints). Clause (g) recipient binding + clause (e) deposit reality still force real deposits to the committed recipients — the thief cannot mint without valid backing or redirect already-committed deposits. Worst realistic abuse: censorship / denial of service at entry, waving through tainted mints (reputation filter bypassed), and burning slots by blind-signing garbage (signing without checking inputs — §3.2.1.1).

### 7.3 CANNOT (gatekeeper and minter)

- **Mint without a fresh real `MoveToBacked` backing-only vault output** of matching amount under N-of-N and in-set `agg_key` — clauses (e), (f), (h).
- **Redirect a mint** — clause (g).
- **Mint twice per vault outpoint** — clause (f) + first-occurrence on `Pk_mint`.
- **Block transfers** — no gatekeeper/minter role in §2 holder transitions.
- **Block / censor redemptions** — no gatekeeper role in §4.3.
- **Inflate supply beyond the vault UTXO ceiling** — §3.6 upper-bound auditability.
- **Seize the vault unilaterally** — no unilateral vault path; spends only along presigned graphs.
- **Substitute a self-controlled operator set under this asset** — `operator_set_root` membership.

---

## 8. Privacy implications

Port of BITVM_BRIDGE.md §9, specialised for TS3.

### 8.1 Peg-in observability

The user's deposit on Bitcoin L1 is visible. Observers of the vault see:

- deposit amount (denomination-quantised);
- funding addresses;
- vault-move timing;
- temporal correlation with the subsequent mint nullifier inscription (vaulted amounts are public on L1; exact mint↔deposit linkage for third parties still requires the mint proof or a published attestation ledger — §3.6).

This is a privacy regression versus a pure off-chain mint, and a privacy improvement versus holding L1 BTC for all subsequent activity (internal transfers are shielded).

### 8.2 Peg-out observability (honest — NH-04)

Symmetric: `btc_recipient` is a public P2TR output; temporal correlation of redeem nullifier time with payout time is observable. `redeem_commitment` keeps redemption **details** off the public ProofData opening — only the bridge sees openings until claim time.

**Indistinguishability bound (MUST state honestly).** A redeem transition is on-chain indistinguishable from any other transition **only until the operator's reimbursement claim marker appears**. The claim marker then links that redeem (`(Pkᵢ, Rᵢ)`) to its payout outpoint. Redemption correlates on-chain anyway (public payout); this is an **accepted privacy boundary**, not a failure of the hiding commitment. Redeem-branch amounts and openings remain **recursion-only** for the reimbursement circuit (§4.3.2 exposition note; §3.7.2) and **MUST NOT** appear as on-chain public inputs of `C`.

### 8.3 Internal transfers

Unaffected: global anonymity set of shielded multi-asset transfers; gatekeeper and operators learn nothing about non-bridged traffic beyond what separate hosting roles already expose.

### 8.4 Mitigations

- Fresh L1 addresses per deposit and per payout.
- Holder-side timing discretion between mint and first transfer, and between redeem and requesting payout.
- Optional coinjoin after payout.
- Hiding recipient commitment on deposit (already normative in §3.3(g)) so operators see commitment, not plaintext, until mint delivery.

**Analogy:** Zcash t-address / z-address model — transparent edges, shielded interior. zkCoins-with-bridge has **less** privacy than zkCoins-without-bridge (L1 touch points) but keeps private interior transfers.

---

## 9. Transitional profile (NOT zkBTC)

Until the TS3 circuit and Glock maturity gates clear, an operator **MAY** run a custodial-window bridged BTC asset **today** under token standard 1 plus an operator service, following the lightning-bridge.md pattern:

- operator SLA for redemption (quote / burn-address or §5.6-link style proof of payment to a sink);
- mint policy matching observed L1 locks under operator honesty;
- no new wire protocol; ordinary sender/recipient roles.

### 9.1 Naming lock (normative)

Such an asset:

- **MUST** use its own asset name and `asset_id`;
- **MUST NEVER** use the name **"zkBTC"**;
- **MUST** carry the banner: *does not meet REQ-4 — redemption is an operator SLA, supply is operator-attested*;
- **MUST NOT** promise migration into zkBTC (different asset, different lineage universe).

### 9.2 What the transitional profile lacks vs TS3

| Property | Transitional (TS1 + SLA) | zkBTC (TS3 + Glock) |
|----------|--------------------------|---------------------|
| Supply audit | Operator-attested; amounts unobservable | Upper bound vs public vault UTXOs; exact via optional aggregate attestation (§3.6) |
| Mint bound to vault outpoint | Policy only | In-circuit LCP (N-of-N + deep finality + operator-set) + `Pk_mint` |
| Redeem | Operator SLA | Bridge claim keyed on `(Pkᵢ, Rᵢ)` |
| Gatekeeper on exit path | N/A (often SLA counterparty = operator) | No |
| Name | Must not be "zkBTC" | "zkBTC" reserved for this profile |
| Migration promise | Forbidden | N/A |

Discovery, if any, **SHOULD** use a distinct operator `features` flag (not the reserved zkBTC product name) and fail closed when absent — same spirit as lightning-bridge discovery.

---

## 10. Covenant upgrade path

Covenant soft forks (OP_CTV / CSFS / OP_CAT class) would allow an anyone-can-satisfy exit script of the form "valid burn / redeem proof → fixed payout template," removing the operator-liveness residual. Alpen engineer analysis notes that without covenants, BitVM-style bridges remain operator-mediated via presigned graphs; with CAT+CTV-style tools, unilateral trustless withdraws become designable. None of these opcodes is activated on Bitcoin mainnet as of mid-2026; realistic timeline is multi-year and uncertain (landscape report §2.11).

**Design consequence now:** the redeem statement (§3.5) is construction-agnostic — a hiding commitment plus an anchored ID `(Pkᵢ, Rᵢ)` — so a future covenant vault **MAY** consume the **same** statement without rewriting the token standard. This document does not promise activation dates or claim that covenants are near.

---

## 11. Open questions

1. **Glock mainnet and audit timing.** No public mainnet date as of research window; Alpen stack on signet / testnets; audits partial / ongoing.
2. **Plonky2 → DV-Pari conversion** of the zkCoins compliance predicate — blocking maturity gate; needs engagement with Eagen / Linus.
3. **Global circuit-specific setup artifact in DV-Pari?** Open point for launch gate A(2); verify against Glock paper and conversion work.
4. **Exact operator bond and challenge economics under Glock** once mainnet parameters exist (Clementine ~2 BTC and BitVM2 multi-MB disputes are reference only).
5. **Permissionless-challenging availability** under designated-verifier Glock (§4.1a) — open dependency.
6. **Watchtower-count floor calibration** (current `PROVISIONAL` ≥ 3) together with sequencing-connector graph structure against one-shot weakness without a Payout Administrator.
7. **LCP checkpoint governance and `D_mint` / `S` calibration.** Proposal: the v2 circuit release **pins** the checkpoint, `D_mint`, and optional `S` (§3.7.2); advancing any is a circuit-parameter release (new digests), not a live governance function. There is **no** freshness window `W`.
8. **Denominations final set** after mainnet economics (including whether/when 0.01 unlocks).
9. **Vault key rotation across deposit generations** without an admin path (new vault / new descriptor / new `operator_set_root` / migration only).
10. **DoS on gatekeeper entry** (mass junk deposit/mint requests) — rate limits and fee policy are gatekeeper operational concerns, not circuit rules.
11. **Interaction with Lightning / Arkade swap layers.** Liquidity rails on top of circulating zkBTC; `ARKADE_INTEGRATION.md` and `LIGHTNING_ATOMIC_SWAP.md` remain unaffected complements (inventory swaps, not reserve proofs).
12. **Operator-set root encoding** — exact Merkle/policy tree format for `operator_set_root` membership proofs (launch parameter; semantic membership is normative here).

---

## 12. References

### 12.1 zkCoins internal

- specification.md (docs `develop` @ e3b5d04) — §1.7.8 v1 freeze; §2.1 compliance predicate; §3.1–3.2 nullifier and S2C; §5.6 confirmation links; §6.5 token standards  
  `https://github.com/zk-coins/docs/blob/develop/docs/specification.md`  
  (URL also in `bitvm-bridge-research.md`)
- lightning-bridge.md — operator-service pattern (report-intern; repo path under zk-coins/docs)
- risks.md — bridge out of core scope; D-13 / D-16 / D-17 class boundaries (report-intern; repo path under zk-coins/docs)
- bitvm-bridge-research.md — June-2026 Glock decision; **explicitly cited source** for the 430–550× figure, single 64-byte Schnorr fraud-proof form, Argo ePrint 2026/049, dispute-cost table (~35k–100k sats projected), Eagen/Linus author-cluster note, and the specification.md GitHub URL above  
  (this repo: `research/bitvm-bridge-research.md`)
- BITVM_BRIDGE.md — May strategy draft (partially superseded)  
  (this repo: `research/zkcoins-design/BITVM_BRIDGE.md`)
- BRIDGE_MVP.md — May engineering draft; §4 ProofTypes / SMTs superseded  
  (this repo: `research/zkcoins-design/BRIDGE_MVP.md`)
- ARKADE_INTEGRATION.md, LIGHTNING_ATOMIC_SWAP.md — complementary liquidity rails  
  (this repo: `research/zkcoins-design/`)

### 12.2 Glock / Argo / Mosaic / BitVM

- Glock paper (Eagen) — `https://eprint.iacr.org/2025/1485`
- Mosaic paper — `https://eprint.iacr.org/2026/812`
- Argo paper — `https://eprint.iacr.org/2026/049`
- Alpen Glock blog — `https://www.alpenlabs.io/blog/glock-verification-on-bitcoin`
- Alpen Mosaic blog — `https://www.alpenlabs.io/blog/introducing-mosaic-glocks-final-piece`
- Alpen Strata bridge (historical BitVM2 post, superseded for mainnet direction) — `https://www.alpenlabs.io/blog/introducing-the-strata-bridge`
- Alpen BitVM2 cost analysis — `https://www.alpenlabs.io/blog/state-of-snark-verification-with-bitvm2`
- Alpen 2025 overview (audits, permissionless challenging roadmap) — `https://www.alpenlabs.io/blog/inside-alpens-2025`
- Alpen bitcoin bridge docs — `https://docs.alpen.org/how-alpen-works/bitcoin-bridge.md`
- Alpen protocol administration / safeguards — `https://docs.alpen.org/how-alpen-works/protocol-administration-and-safeguards.md`
- BitVM2 bridge paper — `https://bitvm.org/bitvm_bridge.pdf`
- BitVM2 writeup — `https://bitvm.org/bitvm2`
- BitVM3 paper — `https://bitvm.org/bitvm3.pdf`
- Storopoli BitVM / covenants note — `https://storopoli.com/posts/2025-02-10-bitvm.html`
- strata-bridge repository — `https://github.com/alpenlabs/strata-bridge`
- alpen rollup repository — `https://github.com/alpenlabs/alpen`

### 12.3 Citrea / Clementine (parameter reference baselines)

- Clementine trust-minimized bridge — `https://docs.citrea.xyz/essentials/clementine-trust-minimized-bitcoin-bridge.md`
- Using Clementine (10 BTC denomination) — `https://docs.citrea.xyz/essentials/using-clementine.md`
- Clementine signers — `https://docs.citrea.xyz/advanced/clementine-signers.md`
- Security council — `https://docs.citrea.xyz/advanced/security-council.md`
- Bridge system contract — `https://docs.citrea.xyz/developer-documentation/system-contracts/bridge.md`
- Clementine whitepaper PDF — `https://citrea.xyz/clementine_whitepaper.pdf`
- Clementine ePrint — `https://eprint.iacr.org/2025/776`
- Clementine repository — `https://github.com/chainwayxyz/clementine`
- Citrea introduction (mainnet since Jan 2026) — `https://docs.citrea.xyz/essentials/introduction.md`

### 12.4 Landscape sources (mechanism matrix)

- BitVM hub — `https://bitvm.org`
- tBTC v2 — `https://docs.threshold.network/tbtc-v2`
- Liquid federation — `https://liquid.net/federation`
- Liquid technical overview — `https://docs.liquid.net/docs/technical-overview`
- Stacks sBTC design — `https://stacks-network.github.io/stacks/sbtc.html`
- Stacks sBTC signers — `https://docs.stacks.co/learn/sbtc/sbtc-signers`
- Mercury Layer — `https://mercurylayer.com/`
- Arkade unilateral exit — `https://docs.arkadeos.com/learn/security/unilateral-exit`
- Arkade primer — `https://docs.arkadeos.com/primer`
- Covenant landscape commentary — `https://www.galaxy.com/insights/research/bitcoins-next-major-upgrade-op-cat-and-op-ctv`
- OP_CAT topic — `https://bitcoinops.org/en/topics/op_cat/`
- BIP-119 CTV — `https://github.com/bitcoin/bips/blob/master/bip-0119.mediawiki`

---

## 13. Change log

| Date | Change |
|------|--------|
| 2026-08-06 | Initial specification: TS3 (`issuance_version == 3`) + Glock-based zkBTC bridge profile; supersedes BRIDGE_MVP §4/§6.3 ProofType sketches and `IssuanceTerms_v2_glock_bridged` naming. |
| 2026-08-06 | Hardening: closed B-01..B-07, M-01..M-04 from the pre-freeze review — vault-outpoint mint + N-of-N + `D_mint`/`S` CSV window; `vault_template`/`instantiate`; full 7+ claim-consumed reimbursement statement; sequencing connectors; `max_fee`; bit-defined deposit key; pinned v2 surface (224-byte ProofData); `refund_timelock` out of terms; upper-bound supply audit; citation integrity via `bitvm-bridge-research.md`. |
| 2026-08-06 | Gatekeeper redesign: replace single issuer with optional per-token gatekeeper + operator-set-root legitimacy binding; close B-01/B-02/M-01/M-02/M-04/NH-01..04. |
| 2026-08-06 | Executability pass: close R-01 (NUMS vault taproot), R-02 (recursive operator_set_root binding), R-03 (gatekeeper input-verify-then-sign), R-04 (host-side freshness + strict boundary), R-05 (logical payout claim-marker), R-06/R-07. |
| 2026-08-06 | construction pass: R-01 (refund off vault output), R-04 (tip_height in ProofData_v2), NEW-01 (pre-signed-graph vault spend, no live CHECKSIG), NEW-02 (claimant-funded payout + slashed-marker exclusion), NEW-03 (canonical taproot + NUMS / honest launch-pin). |
| 2026-08-06 | mint↔vault binding inverted (MoveToBacked): mint proves MoveToBacked confirmation in-circuit; host-side freshness/tip_height/W removed; N-of-N presigning (threshold gatekeeper only); claim value-accounting; frozen-vault residual documented |
| 2026-08-06 | canonical-anchor pass: gatekeeper withholds the mint signature until canonical MoveToBacked confirmation (closes R-04 in gatekeeper mode); no-gatekeeper pooled backing documented as fundamentally weaker (no canonical observer); MoveToBacked-without-mint reframed as consented irrevocable reserve contribution with mandatory depositor co-signature (INV-01) |

---

## Appendix A — Normative checklist (D1–D10 coverage map)

| ID | Requirement | Section |
|----|-------------|---------|
| D1 | `IssuanceTerms_v3` complete (`gatekeeper`, `operator_set_root`, `vault_template`, `instantiate(…, agg_key, epoch)` with NUMS internal key + ordered Glock claim/challenge **pre-signed-graph** tapleaves (no live CHECKSIG; no depositor/cooperative vault refund leaf), terms_hash, asset_id preimage; denominations and `refund_timelock` **not** in terms) | §3.1, §3.1.1–§3.1.3, §4.4 |
| D2 | Mint-key derivation (`Pk_mint`; gatekeeper- vs depositor-base; MintKey domain; mod-n / even-y M-01) + mint consumes `Pk_mint` on **`MoveToBacked` vault** outpoint; gatekeeper verifies inputs **and own canonical Bitcoin view** then signs (not full proof); withholds until canonical `MoveToBacked` (R-04) | §3.2 |
| D3 | In-circuit mint clauses (a)–(h) incl. LCP: `MoveToBacked` vault outpoint, N-of-N witness, `C_lcp.operator_set_root == IssuanceTerms_v3.operator_set_root`, depth ≥ `D_mint`, instance byte-equality; **no** host-side freshness / `tip_height` / `W`; emission without self-credit; depositor co-sign on `MoveToBacked` both modes (INV-01) | §3.3, §3.3.1–§3.3.2 |
| D4 | Deep-finality + gatekeeper canonical-chain anchor (R-04); no transitive downstream re-check; optional first-recipient SHOULD; consented irrevocable reserve contribution residual (INV-01) | §3.4, §4.2 |
| D5 | Redeem: `redeem_commitment` incl. `max_fee < redeem_amount`, redeem ID `:= (Pkᵢ, Rᵢ)`, claim-marker uniqueness (logical first-marker on valid unchallenged set; slashed excluded; claimant-funded payout by **value-accounting**), value preservation (exactly `redeem_amount` from vault), payout ≥ `redeem_amount − max_fee` | §3.5, §4.3.2 |
| D6 | ProofData layout v2 (7 fields / **224 bytes**: six v1 + `redeem_commitment`; zero-sentinel for mint) + PI limbs + **`C_balance` re-pinned for v2** + `genesis_tag` + LCP pins (`D_mint`, optional `S`) + migration / coexistence | §3.5.2, §3.7, §3.7.2 |
| D7 | Bridge parameter table (`D_mint`, optional `S`, Glock claim/challenge CSV, NUMS vault internal key, deposit-taproot-only refund, pre-signed `MoveToBacked` + backing-only vault, N-of-N presigning, watchtower floor) vs Clementine / Strata baselines | §4.4 |
| D8 | Roles (minter / optional gatekeeper / operators; vault presigning **MUST** N-of-N; FROST/threshold **MAY only for gatekeeper**; N-of-N gatekeeper loss warning) + sequencing connectors + launch gates (operator-set foreign majority, setup integrity, self-fronting, challenger economics) | §2.1, §4.1, §4.6, §6 |
| D9 | Trust matrix + residual ≥1 operator + consented irrevocable contribution residual (INV-01) + no-gatekeeper canonical-anchor gap (R-04) + covenant path + no-council consequence (graph-level one-shot close) + gatekeeper mint-time liveness + canonical anchor | §5, §4.5, §6, §10 |
| D10 | Transitional profile: own name/id, SLA shape, "does not meet REQ-4" banner, NEVER "zkBTC" | §9 |
| D11 | Gatekeeper model: reputation + **canonical-chain anchor** rationale (R-04), CANNOT table (no mint without valid backing; no redirect; no special privilege), security-class honesty (**materially weaker** no-gatekeeper class; not trust-minimized pooled), competing tokens | §6, §2.1, §2.5 |
| D12 | Operator-set legitimacy: `operator_set_root` in asset_id; recursive LCP root equality (not bare boolean); cross-graph redeem draws in-set vaults only | §3.1.2, §3.3(e), §3.3.1, §4.3 |

## Appendix B — Supersession detail

| Prior sketch | Problem | Replacement |
|--------------|---------|-------------|
| Separate `IssuanceProof` / `BurnProof` ProofTypes | Violates single-circuit `C` (§2.2); conflicts with §6.5 version-branch dispatch | TS3 mint / redeem as branches of `C` on v2 surface |
| Global `peg_in_consumed_smt` / `burned_coins_smt` | New consensus objects; incompatible with post-#97 model | Per-deposit `Pk_mint` first-occurrence; redeem ID = `(Pkᵢ, Rᵢ)` |
| `IssuanceTerms_v2_glock_bridged` (issuer-less, version 2) | `issuance_version == 2` is capped-supply; incomplete legitimacy | `IssuanceTerms_v3` with optional gatekeeper + `operator_set_root` + `vault_template` binding |
| Single mandatory issuer (`issuer_pubkey` / REQ-3 monopoly) | Central party; conflates economic mint with quality control | Optional gatekeeper + permissionless minter; `Pk_mint` mode-dependent |
| Federation V0 / BitVM2 intermediate | Superseded by June-2026 Glock decision | §4.0 Glock-only path + maturity gate |
| Denominations / `refund_timelock` frozen in asset terms | Economics depend on unaudited projections; asset_id freeze | Bridge-side epoch parameters; start set {0.1, 1, 10}; `refund_timelock` out of terms |
| Fixed `vault_descriptor` in `asset_id` | Circular if asset-bound; cross-asset double-backing if shared | `H(vault_template)` + `instantiate(vault_template, asset_id, agg_key, epoch)` |
| Shallow LCP on user deposit outpoint | Historical inclusion ≠ current vault backing; private-fork refund forgeries | `MoveToBacked` vault outpoint + N-of-N + operator-set + depth ≥ `D_mint` |
| Host-side freshness / mint-window CSV race | Unconstructible mint↔vault co-transition; TOCTOU; tip sentinel ambiguity | Invert: mint proves `MoveToBacked` in-circuit; remove `tip_height`/`W`/`h_inscr`; Glock claim CSV only (R-01/R-04 invert; NEW-HOLE-01) |
| `agg_key` as vault internal key | Key-path spend bypasses all CSV locks | NUMS internal key; all spends via CSV-locked pre-signed-graph tapleaves (NUMS / no key-path) |
| Live `agg_key` CHECKSIG leaf on vault | Coalition signs arbitrary vault spend; bypasses fraud statement / connectors; breaks 1-of-N | Pre-signed-graph-only vault spends; setup signatures then keys deleted; no live CHECKSIG (NEW-01) |
| `t < N` vault presigning set | One honest deletion leaves `N−1 ≥ t` shares able to sign; breaks 1-of-N | Vault presigning **MUST** be N-of-N; threshold only for gatekeeper (NEW-01) |
| Depositor / cooperative refund leaf on vault output | `refund_timelock` matures before mint depth; mint-then-refund destroys backing | Refund only on deposit taproot; extinguished by `MoveToBacked`; post-`MoveToBacked` unminted → **irrevocable consented reserve contribution** (INV-01 / R-01) |
| LCP-only canonicity without external observer | Private-fork `MoveToBacked` + mint + canonical refund amortises unbacked supply | Gatekeeper withholds `Pk_mint` until own **canonical Bitcoin view** confirms `MoveToBacked` (R-04); no-gk documented as materially weaker |
| Gatekeeper-only co-sign on `MoveToBacked` | MoveToBacked without depositor consent → unconsented contribution to shared reserve | Depositor co-sign **both modes** (INV-01); gatekeeper co-sign additional in gated mode |
| Bare `operator_set_member_ok` boolean | Attacker proves membership under attacker root | `C_lcp` exposes `operator_set_root`; outer `C` checks equality with asset root (R-02) |
| "Verify full mint proof before signing" | Circular (proof embeds signature) | Gatekeeper verifies inputs, signs, then proof is built (R-03) |
| Literal "consume payout UTXO" | Operator has no key on recipient P2TR | Logical claim-marker first-occurrence on `(Pkᵢ, Rᵢ, payout_txid, payout_vout)` (R-05) |
| Any claim-marker (incl. slashed) blocks uniqueness | Malicious poison-marker freezes honest redeem | Only valid unchallenged markers consume uniqueness; slashed/failed excluded (NEW-02) |
| Claim with one bonded-key input only | Front-runner attaches small bonded input to real operator's funded tx (`SIGHASH_SINGLE\|ANYONECANPAY`) | Value-accounting: sum of bonded-key-signed inputs covers payout + fee; non-bonded inputs value-ignored (NEW-02) |
| "Sort by tapleaf_hash" as full tree pin | BIP-341 sorts only sibling pairs; tree shape underdetermined; NUMS deferred | Fixed leaf order key + left-complete balanced tree-shape rule + pinned NUMS derivation; connector bytes launch-pinned (NEW-03) |
| `C_balance` "unchanged" under v2 `C` | Recursive verifier data embeds `C`; digest must change | Both `C` and `C_balance` re-pinned for v2 (M-02) |
| Exact aggregate supply from chain data | Vaulted-unminted / slot-burn indistinguishable | Upper bound only; optional aggregate attestation (M-04) |
| Reimbursement without value preservation / payout bind | Vault drain or historical payout replay | Exactly `redeem_amount` from vault; claim-marker on payout `(txid,vout)`; `max_fee < redeem_amount` (NH-01..03) |
| Watchtower floor alone (no PA) | One-shot exhaustion across sequential claims | Per-operator sequencing connectors + floor over operators |
| Self-controlled N-of-N under permissionless mint | 1-of-N honesty vacuous; unbacked cross-graph redeem | `operator_set_root` bound in `asset_id` + recursive `C_lcp.operator_set_root` equality |

---

*End of design specification. No code. Not a build order until maturity gates §4.0 / §4.6(B) and REQ-4 gates §4.6(A) clear.*
