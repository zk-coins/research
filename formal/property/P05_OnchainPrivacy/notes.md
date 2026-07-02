# P05 — On-chain Privacy / Unlinkability — notes

P05 is an **OBSERVATIONAL** property. Unlinkability itself rests on cryptographic
**axioms** (A3 root/nullifier preimage-resistance, BIP-32-PRF rotating-key
unlinkability, A2 nk-secrecy); this package does **not** claim those verified.
What is machine-checked is the **composition surface**: the chain-observer
projection a verifier publishes, and the structural/dynamic facts about that
projection that the axioms then compose with to deliver unlinkability. The split
is stated honestly throughout, and — applying the discipline from the P10
vacuity-defect fix — every machine-checked claim is shown to have real content
(a reachability/vacuity probe and a negative control are mandatory and recorded
below). No tautology is shipped as a dynamic claim.

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so a
divergent result on a future version is attributable.

## What this is

Phase-2 deliverable: the on-chain privacy bound of Spec Sec. 3, formalised over
the **full-fidelity on-chain state machine** [`module/Onchain.tla`](../../module/Onchain.tla)
— the **same** machine P02 No-Double-Spend is proven over, reused unchanged.
`property.tla` EXTENDS `Onchain` (which EXTENDS `Foundations` + `Assumptions`) and
defines the chain-observer projection `ChainView`, the dynamic invariant
`PublisherOnlyLink`, the structural fact `NoMemberStructureOnChain`, the composite
`INV_P5`, the set-projection inductive invariant `IndInv_P5` with its
assignment-form `IndInvInit`, the implication target `ObservableGuarantee`, and
the constant initialiser `P5ConstInit`.

## The chain-observer projection (post-#40 reality)

The single most important post-#40 fact: the on-chain footprint is a
**constant-size** `BatchInscription` (231 bytes, Sec. 3.5 byte layout). A
chain-only observer learns **only**

```
{ publisher_pubkey, prev_root, new_root, bundle_locator, block_anchor }
```

and **nothing else** — **not** the record count `m`, **not** any per-spender
input count `k_j`, **not** any individual nullifier. The `SpendRecord`s, the
member nullifiers, and the `AggregateBatchProof` live **off-chain** inside the
`BatchBundle` (Sec. 3.1, Sec. 4.6). Sec. 3.1 verbatim: a `BatchInscription`
"reveals no amount, asset, sender, receiver, nor any individual nullifier."

`ChainView(b)` encodes exactly this: it projects each admitted inscription to the
five on-chain fields and **drops** the Onchain record's `batchNullifiers`,
`memberValidities`, and `anchorOk` — those are bundle-/admission-internal, not
inscribed bytes.

## Model-vs-wire honesty (the A16/A3 boundary)

`Onchain.tla` models a root **as** the set of nullifiers it commits to
(A16/`RootCommitsSet`): in the **model** `prevRoot`/`newRoot` literally carry the
nf-set. On the **wire** they are 32-byte Poseidon/SMT roots whose preimage is
hidden by **A3** (root preimage-resistance). The set-representation **is** the
A16/A3 boundary. This is why the dynamic invariant is designed to have real
content **despite** the representation: it does not assert "the observer cannot
read the set" (false in the model, true on the wire under A3 — an axiom). It
asserts a relation that is non-trivial **even with the model's full visibility
into the committed set**: that no account identity key behind any committed
nullifier ever coincides with the one genuinely on-chain identity, the publisher
key (`PublisherOnlyLink`).

## The dynamic / structural / axiom table

| Layer | Item | What it says | How certified |
|---|---|---|---|
| **DYNAMIC** | `PublisherOnlyLink` | Every admitted inscription's `ChainView.publisherPk` is a publisher key and **never** equals an account identity key (`owner` = address = H(Pk0), or `current_pubkey` = rotating Pk_i) of any account behind any on-chain nullifier — the §3.5 claim "the publisher identity is the only on-chain link". | **UNBOUNDED** via set-projection inductive invariant `IndInv_P5` ([P2]+[P3]+[P4]); bounded history-quantified `INV_P5` ([P1]). Negatively controllable (see negative control). |
| **STRUCTURAL** | `NoMemberStructureOnChain` | The observable projection carries **exactly** the five on-chain fields and **no** bundle-only field (`batchNullifiers`/`memberValidities` absent from `DOMAIN ChainView`). | **By-construction** property of the projection function; checked bounded length 6 ([P5]) to confirm well-formedness. Clearly labelled structural — not exercised by the transition relation, not the load-bearing dynamic claim. |
| **AXIOM** | A3 | Root/nullifier preimage-resistance; the set-representation of roots is the A16/A3 boundary (model carries the set; wire hides it behind A3). | Quoted, scoped. **NOT verified here.** |
| **AXIOM** | BIP-32-PRF | Rotating-key unlinkability: fresh hardened Pk_i per transition (Sec. 1.2); no key path links two transitions without the seed. | Quoted, scoped. **NOT verified here.** |
| **AXIOM** | A2 | nk-secrecy: `nf = Hc("Nullifier", nk ‖ identifier)` is a random-looking digest without `nk` (Pass-3 P5). | Quoted, scoped. **NOT verified here.** |
| **AXIOM** | Network hygiene | Publisher funding/UTXO exposure (§3.8 broadcaster-paid = MAY), NIP-44/NIP-59 fingerprinting, relay/Tor choice, long-run intersection attacks. | Pass-3 P5 **MEDIUM** half. **OUT OF SCOPE** (operational, not spec-enforceable). |

## Property statement (M4 ground-truth)

- **Prose spec sections formalised:** Sec. 3.1 (the on-chain object — constant-size
  `BatchInscription`; "reveals no amount, asset, sender, receiver, nor any
  individual nullifier"), Sec. 3.5 (inscription byte layout + metadata note —
  record count hidden on-chain, `k_j` bundle-only, "the publisher identity is the
  only on-chain link"), Sec. 1.2/1.4 (rotating per-transition Pk_i; account
  address = H(Pk0); nf unlinkability). Baseline `docs@ed7fdece` (spec-v1.1 = `b6972b8` + `docs#46`/`#47`/`#48`).

- **Pass-3 §P5 statement (the oracle), quoted verbatim:**
  > **Statement.** A passive observer of Bitcoin learns from a `SpendRecord` only:
  > that **some** zkCoins transition occurred, the input-count `kⱼ` (acknowledged
  > metadata leak per §3.5), and the rotating `Pkᵢ` plus the spent `nf`s — but
  > cannot recover the owner address, the amount, the asset, the recipient, or
  > link to any other `SpendRecord` of the same account.
  >
  > **Game.** A wins if it can, with non-negligible probability, output a
  > partition of admitted `SpendRecord`s such that each partition class
  > corresponds exactly to one account.
  >
  > [attack classes: direct linkage via `Pkᵢ` (BIP-32 hardened, out under A9);
  > direct linkage via `nf` (A3 + A2, `nk` never public); linkage via `inr`/`ocr`
  > (A3 preimage-resistance); linkage via `k_j` — the **accepted, documented
  > leak** (§3.5); inscription envelope metadata (generic marker); publisher
  > behaviour/timing (§3.8 broadcaster-paid, MAY); cross-protocol fingerprinting
  > (§4.7, Tor/cover traffic); long-run intersection attacks (acknowledged in
  > `risks.md`).]
  >
  > **Verdict.** Sound for the **stated** privacy bound (on-chain hides amount,
  > asset, parties, graph; leaks input-count). **Confidence: HIGH for on-chain
  > unlinkability**, **MEDIUM** for end-to-end network-layer privacy (which
  > depends on operational hygiene the spec calls out but cannot enforce).

## Post-#40 delta (the Phase-4 reconciliation input)

**Pass-3 was written PRE-#40.** It states the on-chain observer learns `k_j` (the
accepted input-count leak), the rotating `Pkᵢ`, and the spent `nf`s — i.e. it
assumes a per-`SpendRecord` on-chain surface. **That surface no longer exists
post-#40:** the `SpendRecord`s, their nullifiers, and `k_j` all moved
**off-chain** into the `BatchBundle`, and the on-chain footprint became the
constant-size `BatchInscription` carrying only `{publisher_pubkey, prev_root,
new_root, bundle_locator, block_anchor}`. **The redesign STRENGTHENS P5:** the
accepted `k_j` leak is **gone from the chain** (it is now bundle-only, visible
only to a party that fetches and is authorised for the bundle), and the publisher
pubkey is a **new on-chain datum** — which is exactly the sole (non-account)
on-chain link this package machine-checks via `PublisherOnlyLink`. So the
HIGH on-chain bound Pass-3 records is not merely confirmed; the post-#40 chain
surface is **strictly narrower** than the one Pass-3 graded HIGH, and the only new
on-chain identity is proven categorically disjoint from every account identity.

## spec-v1.1 (docs#47) delta — verdict unchanged/strengthened (diff-confirm)

The spec-v1.1 baseline (`docs@ed7fdece`) changed the `bundle_locator` preimage
from `Hc("BatchBundle", serialize(BatchBundle))` to
`Hc("BatchBundle", prev_root ‖ new_root ‖ u32-be(m) ‖ member_root)` (docs#47). **P5
is unchanged/strengthened:** the on-chain footprint is still a single opaque
32-byte locator carried in `ChainView` as an opaque scalar (preimage-bound under
A3); the new `member_root` and its ORDERED member preimage live **off-chain**
inside the `BatchBundle`, so a chain-only observer learns nothing new. `docs#46`
(deployment topology, optional external bitcoind/relay as a documented A13 trust
trade-off) is verification-neutral. The order-binding the new preimage gives is an
**integrity** property machine-checked in `property/P02_NoDoubleSpend/member_root.tla`,
not a privacy leak — it constrains what a publisher can do under one proof, not
what an observer can read. All six `verify.sh` privacy checks re-confirm verbatim.

## INV / IndInv design and the Seq-variable scope (same as P02)

`PublisherOnlyLink` and `NoMemberStructureOnChain` both quantify over `DOMAIN
onAdmittedChain`. Apalache encodes a `Seq` with a **static capacity**, so an
inductive step assuming-and-reestablishing a chain-quantified property of
arbitrary length is not one unbounded SMT query — exactly the situation P02
documents for its `prev_root` continuity. We handle it identically and honestly:

- **The dynamic claim is certified UNBOUNDED through its SET-PROJECTION
  inductive invariant** `IndInv_P5`. Its load-bearing conjunct is the **state
  fact** "no committed nullifier (`onPending \cup onCompleted`) has an account key
  in the publisher namespace". This is preserved by every `OnNext` action:
  `Admit` only adds nullifiers drawn from `Nullifiers` (whose account keys are the
  account namespace, disjoint from `Publishers` **by construction**, Sec. 1.2 —
  the publisher `Pkₚ` is the node's `op`-family identity, a hardened sibling that
  is neither the SPEND-branch `Pkᵢ` nor the address `H(Pk0)`); `Confirm`/`Reorg`
  move nullifiers between/out of the zones; `PublisherSign` touches no nullifier.
  The step `[P3]` uses an assignment-form init `IndInvInit` that **assigns** every
  Onchain variable, drawing each set from its powerset and `Gen`-constructing the
  sequence (capacity ≤ 4). Because `IndInv_P5` never reads the chain and the set
  effects of `OnNext` do not depend on the chain's value, the step is a faithful
  statement about the **set projection**; the `Gen` capacity bounds only the
  bookkeeping witness, never the conclusion. `[P4]` closes it:
  `IndInv_P5 => ObservableGuarantee` (the disjointness the dynamic claim reduces
  to), a pure length-0 implication.
- **The full history-quantified forms** `INV_P5` (`[P1]`) and the structural
  projection fact (`[P5]`) are certified **bounded** (length 6 = finality depth
  K).

No additional strengthening conjunct beyond the disjointness premise + the type
facts was needed; all checks passed on the first design.

## Modelling decisions

- **Builds on the existing Onchain module, unchanged.** P05 adds no new state or
  actions — it is purely an observational projection plus invariants over the P02
  machine. This keeps the privacy and double-spend results over **one** model.
- **`P5ConstInit`.** Account identity key = 0 (`CanonicalEmptyAccount(0,0)` →
  `owner = current_pubkey = 0`), `Publishers = 1..2` (disjoint from `{0}`),
  `BundleLocators = 1..2`. The disjointness is the construction the dynamic claim
  rests on; the negative control deletes it. The argument is uniform in the
  universe sizes (every conjunct is per-inscription / per-nullifier local).
- **No `apalache.cfg`.** The proof is several runs with different
  `--init`/`--inv`/`--length` combinations; [`verify.sh`](./verify.sh) is the
  canonical runner.
- **EXTENDS staging.** Apalache resolves `EXTENDS` only from the spec file's own
  directory; `verify.sh` stages `Foundations.tla`, `Assumptions.tla`,
  `Onchain.tla` and `property.tla` in a `mktemp` scratch dir, runs there, and
  removes the scratch dir + all `_apalache-out` on exit. The module files are
  never duplicated into this committed directory, so they cannot drift from
  `formal/module/*`.

## Vacuity probe and negative control (the model earns its keep)

**(V) Reachability / vacuity probe — the dynamic invariant is asserted over a
POPULATED set.** A throwaway `probe.tla` EXTENDS `property` and asserts
`NoAccountKeysEverOnChain == AccountKeysOnChain = {}`:

```
apalache-mc check --cinit=P5ConstInit --init=OnInit --next=OnNext \
  --inv=NoAccountKeysEverOnChain --length=3 probe.tla
```

yields **Error** (exit 12): the reachable space **does** contain admitted
inscriptions whose committed nullifiers carry account identity keys (non-empty
`AccountKeysOnChain`). So `PublisherOnlyLink` asserts the publisher/account-key
disjointness over a **non-empty** account-key set — it is not vacuously satisfied
by an empty chain. The probe and its `_apalache-out` were discarded.

**(NC) Negative control — the publisher/account namespace separation is
load-bearing.** A `/tmp` copy of `property.tla` (module `propertyNC`) adds a const
init that builds the smoke nullifiers over an account whose identity key
**collides** with a publisher key:

```
NCCoinId(i) == MkCoinId(CanonicalEmptyAccount(1, 1), MkAssetId(...), i)
NCConstInit == Nullifiers = { MkNullifier(0, NCCoinId(i)) : i \in 1..3 }
            /\ Publishers = 1..2 /\ BundleLocators = 1..2
```

i.e. `owner = current_pubkey = 1` and `1 \in Publishers` — the §1.2
publisher/account namespace separation is **deleted**. Run:

```
apalache-mc check --cinit=NCConstInit --init=OnInit --next=OnNext \
  --inv=INV_P5 --length=3 propertyNC.tla
```

Outcome: **Error** — `PublisherOnlyLink` (state invariant 0) violated at
**State 2**:

```
State0  empty chain
State1  PublisherSign            -- publisher pk=1 authorises the batch
State2  Admit  publisherPk |-> 1 -- inscription admitted; its committed nullifier
                                    carries owner |-> 1, currentPk |-> 1;
                                    publisherPk (1) == an account identity key (1)
                                    => PublisherOnlyLink violated
```

A chain observer reading the publisher field would, under the collapsed
namespace, read an account key — exactly the linkage `PublisherOnlyLink` rules
out. With the separation present (committed `P5ConstInit`: account key 0,
publishers {1,2}), all six `verify.sh` checks return NoError. The committed
`module/Onchain.tla` and `property.tla` are unchanged; the `/tmp` copy and its
`_apalache-out` were discarded.

**Honest-failure budget.** The brief mandated reporting a blocker on three honest
failures. There were **zero** honest failures: typecheck, all six positive checks,
the vacuity probe (expected Error), and the negative control (expected Error) all
behaved as designed on the first run. No blocker.

## Cross-check vs Pass-3 (Phase-4 input)

| P5 half | Pass-3 label | Apalache verdict (this cert) | Reconciliation |
|---|---|---|---|
| **On-chain unlinkability** | **HIGH** | **VERIFIED** (observable composition surface): `PublisherOnlyLink` unbounded set-projection + `NoMemberStructureOnChain` structural | **confirmed AND STRENGTHENED post-#40** — the chain surface is strictly narrower than the one Pass-3 graded (k_j and per-record nf's left the chain); the only new on-chain identity (publisher pubkey) is proven disjoint from every account identity |
| **End-to-end network-layer privacy** | **MEDIUM** | **OUT OF SCOPE** | operational hygiene (publisher funding/§3.8, NIP-44/NIP-59 fingerprinting, relay/Tor, long-run intersection); depends on user behaviour the spec calls out but cannot enforce; not a state property of the on-chain machine |

The on-chain half is confirmed at the on-chain state-machine level: the §3.5
claim the audit grades HIGH ("the publisher identity is the only on-chain link")
is machine-checked, and the post-#40 redesign removes the one accepted on-chain
leak Pass-3 recorded (`k_j`). The network half is **not over-claimed**: it is
explicitly out of this certificate's scope and remains MEDIUM, contingent on
operational hygiene, exactly as Pass-3 and the spec state. Full reconciliation
across all properties is deferred to Phase 4.

**Oracle/baseline provenance.** The Pass-3 P5 prose was written against a pre-#40
snapshot; the baseline here (`ed7fdece`, spec-v1.1) is post-#40 and post-#47. The
*claim* (on-chain hides amount/asset/parties/graph; unlinkability rests on
A3/BIP-32-PRF/A2) is unchanged and, on the post-#40 surface, strictly stronger —
so the audit remains a valid oracle, with the delta paragraph above as the
explicit reconciliation note. `docs#47` keeps the on-chain footprint a single
opaque 32-byte `bundle_locator`; its new preimage (member_root over the ordered
members) lives off-chain, so a chain observer still sees only the opaque locator
and the privacy verdict is unchanged/strengthened (see Modelling decisions).

## Scope / what is deliberately NOT modelled

- **The cryptographic unlinkability itself** — A3 (root/nf preimage-resistance),
  BIP-32-PRF (rotating-key unlinkability), A2 (nk-secrecy) — is **axiom**, not
  re-derived. The model's set-representation of roots is the A16/A3 boundary; on
  the wire those sets are hidden digests.
- **End-to-end / network-layer privacy** (publisher funding/UTXO exposure §3.8;
  NIP-44/NIP-59 cross-protocol fingerprinting §4.7; relay choice; Tor; long-run
  intersection attacks against small anonymity sets) — Pass-3 MEDIUM, operational,
  out of scope.
- **The `bundle_locator` content-address linkage analysis** — post-`docs#47` the
  locator is `Hc("BatchBundle", prev_root ‖ new_root ‖ u32-be(m) ‖ member_root)`
  (previously `Hc("BatchBundle", serialize(BatchBundle))`), where `member_root` is
  a binary Poseidon tree over the ordered members. It is preimage-bound under A3;
  it is carried in `ChainView` as an opaque scalar and is not asserted to leak or
  hide beyond what A3 gives (it is the digest, not its preimage). An on-chain
  observer still sees only the opaque 32-byte locator — the member_root and its
  ordered preimage live off-chain inside the `BatchBundle` — so the privacy
  verdict is unchanged/strengthened. (The order-binding the new preimage gives is
  the load-bearing fact checked, separately, in
  `property/P02_NoDoubleSpend/member_root.tla`, an integrity property, not a
  privacy leak.)
- **The off-chain bundle layer** (SpendRecord/k_j/AggregateBatchProof confidentiality
  toward authorised vs unauthorised bundle readers) is a transport/access concern
  (P06 client-side validation, P08 transport conf/auth, P10 capability discipline),
  not the chain-only observer this property bounds.
