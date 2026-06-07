# P07 — Issuance Authenticity (v1) — notes

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
JVM             : Temurin OpenJDK 17.0.19
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Each certificate re-states the Apalache + Z3 version it was produced under, so a
divergent result on a future toolchain is attributable.

## What this is

Phase-0/1 deliverable: the §6.5 v1 mint discipline — as already modelled by the
compliance predicate `C` and the issuance/spend state machine in
[`module/Proofs.tla`](../../module/Proofs.tla) — proven to enforce **issuance
authenticity UNBOUNDED** via an inductive invariant. The property module
`property.tla` EXTENDS `Proofs` (which EXTENDS `Foundations` + `Assumptions`) and
adds the invariant `INV_P7`, its inductive strengthening `IndInv`, and the
assignment-form `IndInvInit`. No change is made to the machine itself.

## Property statement (M4 ground truth — Pass-3 P7, HIGH for v1)

Quoted from the Pass-3 audit (`audit/2026-06-06.03.md`, branch
`origin/audit/spec-2026-06-06-03`), section "P7 · Issuance Authenticity (v1)":

> **Statement.** A coin claiming asset `a` can be admitted as a v1-issuance
> output only by a transition signed by the creator account of `a` (the account
> whose `Pk₀` satisfies `Hc("AssetId", genesis_tag ‖ Pk₀ ‖ H(name) ‖ decimals ‖
> 1) == a`).
>
> **Game.** A wins if a coin with asset `a` is admitted via the v1 mint clauses
> but the signing account is not the creator account.
>
> **Verdict.** Sound under A1, A3, A6, A7. **Confidence: HIGH** for v1.

## Spec sections formalised (baseline docs@b6972b8, post-docs#40)

- **Architecture §6.5** — v1 issuance terms and the mint clauses (a)–(d):
  `issuance_version == 1` (a); `H(creator_pubkey) == prev_account_state.owner`
  (b); the `asset_id` derivation
  `asset_id == Hc("AssetId", … creator_pubkey ‖ name_hash ‖ decimals ‖ version)`
  (c); `terms_hash == Hc("IssuanceTerms", asset_id ‖ version)` (d). These are
  `module/Proofs.tla`'s `MintV1Clauses`, gated into `Clause3_Balance` when an
  issuance is present.
- **Proofs §2.1 clause 3** — per-asset balance conservation invokes the §6.5
  clauses; **clause 2** binds `txn_sig` to `prev_account_state.current_pubkey`
  via the A7 oracle (`PrSigValid` / `prAuthorised`); **clause 7** keeps
  `new_account_state.owner` unchanged.
- **Proofs §2.3.1 / §2.2** — InitialProof vs AccountUpdateProof; the canonical
  empty account (owner = `H(Pk₀)`, current_pubkey = `Pk₀`, send_counter = 0).
  In the model, `MintStep` is the InitialProof issuance (the only minting
  action); `SendStep` is an AccountUpdateProof that never mints.

## How the model realises the claim

In `Proofs.tla` the account index `a` IS its own `Pk₀` and owner: `PrInit`
seeds `CanonicalEmptyAccount(a, a)` and `AddressOf(a) = a` (Foundations,
A5/A6 preimage binding). The creator account of an asset `x` is therefore the
account `a` with `a = x.creator`.

- `MintStep(a, amount)` is gated on `prev.sendCounter = 0` (an InitialProof) and
  builds `asset = AssetOf(prev.current_pubkey)` with `creator_pubkey =
  prev.current_pubkey`, signing under `prev.current_pubkey` — the only way the
  A7 oracle `prAuthorised` ever grows (an account signing its **own**
  transition). On a fresh account, `current_pubkey = owner = a`, so the asset
  minted by account `a` has `creator = a`.
- `SendStep` has `hasIssuance = FALSE` and re-emits an asset the account already
  holds, so it introduces no new creator.

Hence in every reachable state, account `a` holds only assets created by `a` —
which is exactly issuance authenticity: an asset's coins exist only in the
balances/coin-history of its single creator account.

## Formalised invariant and inductive design

```
INV_P7 == \A a \in Accounts :
            /\ \A x   \in DOMAIN prState[a].balances : x.creator       = AddressOf(a)
            /\ \A cid \in prChSet[a]                  : cid.asset.creator = AddressOf(a)
```

`INV_P7` alone is **not** inductive: `MintStep` mints
`AssetOf(prev.current_pubkey)`, so "creator = a" survives a step only if a
mintable account still has `current_pubkey = a`. Two strengthenings close it:

- **S1 — owner pinned.** `prState[a].owner = AddressOf(a)` for every account.
  Established by `PrInit` and preserved by clause 7 (`new_account_state.owner`
  unchanged). Needed because clause (b) ties `AddressOf(creator_pubkey)` to
  `prev.owner`.
- **S2 — fresh = canonical.** `sendCounter = 0  ⇒  current_pubkey = a  ∧
  balances empty  ∧  coin-history empty`. This is the fact `MintStep` relies on
  to mint `a`'s OWN asset (`current_pubkey = a`), AND the fact that makes a
  second mint impossible: after any transition `sendCounter > 0`, so `MintStep`
  is disabled and no further asset is introduced.

```
IndInv == PrTypeOK
          /\ \A a \in Accounts : OwnerPinned(a) /\ FreshIsCanonical(a)   \* S1, S2
          /\ INV_P7
```

`IndInv` (= `PrTypeOK ∧ S1 ∧ S2 ∧ INV_P7`) is closed under `PrNext`; this is
the inductive step `[3]`.

### Decisions / modelling notes

- **`IndInvInit` via `Gen`.** The inductive-step `--init` predicate must ASSIGN
  every variable. An explicit set-of-functions carrier for `prState` makes
  Apalache try to expand a set of functions ("This will blow up the solver" —
  rewriter error). The supported idiom (same family as P02's `Gen(4)`) is to
  generate each variable with `Gen` (apalache.Gen — an unconstrained symbolic
  value of the variable's type) and pin it down with the `IndInv` body, which
  includes `PrTypeOK` (domains = `Accounts`, per-account `WfAccountState`, and
  the `prChSet` / `prAuthorised` element shapes). `IndInvInit` is therefore
  logically equivalent to `IndInv`: it admits exactly the states `IndInv`
  characterises. Size budgets (`Gen(3)`/`Gen(6)`) sit a few above the reachable
  maxima (one mint + one send per account over `|Accounts| = 2`).
- **Forward-reference ordering.** Apalache's SANY frontend rejected the carrier
  definitions when placed after `IndInvInit`; helper sets are defined before
  their first use. (TLA+ permits module-level forward references; Apalache here
  does not, for these positions.)
- **Constant instance.** `ConstInit == PrConstInit` reuses the Proofs smoke
  instance: `Accounts = {1, 2}`, one v1 asset family (`AssetNameHash = 100`,
  `AssetDecimals = 8`). The inductive argument is **per-account local** (every
  `IndInv` conjunct quantifies one account at a time and every action touches a
  single account), so a two-account universe certifies the general result; a
  three-account confirmation is noted below.
- **No `apalache.cfg`.** The unbounded proof is four runs with different
  `--init`/`--inv`/`--length` combinations a single TLC-style config cannot
  express; `ConstInit` is consumed via `--cinit`. `./verify.sh` is the canonical
  reproducible runner; it stages the four modules into a temp dir (Apalache
  resolves EXTENDS from the spec's own directory) so only `property.tla` is
  committed here.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary:

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=PrInit     --next=PrNext --inv=IndInv  --length=6` | NoError |
| 2 | inductive base | `--init=PrInit     --next=PrNext --inv=IndInv  --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=PrNext --inv=IndInv  --length=1` | NoError |
| 4 | implication    | `--init=IndInvInit --next=PrNext --inv=INV_P7  --length=0` | NoError |

Checks **2 + 3 + 4** together are the unbounded proof. All runs use
`--cinit=ConstInit`.

**Uniformity in |Accounts|.** The base [2] and implication [4] checks were
re-run with a `--cinit` fixing `Accounts = {1,2,3}`; both report NoError. The
inductive argument is per-account local (each `IndInv` conjunct quantifies a
single account, and every action touches one account), so the step result is
uniform in the number of accounts; the committed `ConstInit` fixes `{1,2}` for
a fast default run, which is where the step [3] is checked.

## Negative control (the §6.5 (b)/(c) clauses are load-bearing)

In a `/tmp` copy of the four modules, `MintV1Clauses` was weakened by dropping
conjunct **(b)** `AddressOf(creator_pubkey) == prev_account_state.owner`, and a
`MintForeignStep(a, creatorPk, amount)` action was added to `PrNext`: account
`a` performs a v1 InitialProof for `AssetOf(creatorPk)` — the asset of a
possibly different account `creatorPk` — signing under its OWN current key (no
signature forgery; the A7 oracle stays honest). With clause (b) present, the
mint forces `creator_pubkey = a` and is authentic; with (b) dropped, clauses
(a)/(c)/(d) are satisfiable for any `creatorPk`.

```
apalache-mc check --cinit=ConstInit --init=PrInit --next=PrNext --inv=INV_P7 --length=2 property.tla
```

returns a counterexample at **State 1**:

```
Accounts = {1, 2}
account 2 (owner = 2, currentPk = 2)  holds a coin whose asset.creator = 1
   => INV_P7 (CoinsAuthentic(2)) violated: a NON-creator minted account 1's asset
```

so the model can *see* an authenticity violation, and the `NoError` verdict with
the clauses intact is meaningful. (Dropping conjunct (c), the `asset_id`
derivation, yields the same class of violation: the witnessed `asset_id` is no
longer forced to commit to `creator_pubkey`, so a coin can claim a foreign
creator's `asset_id`.) The committed `property.tla` / `module/Proofs.tla` keep
all four clauses intact.

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 label **HIGH** (for v1); Apalache verdict **verified** ⇒ **confirmed** at
the compliance-predicate level. The two clauses the audit's attack-class
enumeration leans on are exactly the ones the negative control shows to be
load-bearing:

- *Fake `creator_pubkey` witness* — defeated by clause (b)
  `H(creator_pubkey) == owner` composed with clause 2's `txn_sig` under
  `current_pubkey` (A6 + A7).
- *Discrepancy between witnessed `creator_pubkey` (= Pk₀) and signed-under `Pkᵢ`*
  — clause 7's owner-invariance (S1 here) forces `creator_pubkey` to be the same
  Pk₀ that fixed the account at creation; S2 ties a fresh account's
  `current_pubkey` to that Pk₀.

Full reconciliation is deferred to Phase 4.

## Scope / what is deliberately NOT modelled here

- **Cross-version replay (v1 vs v2 `asset_id` distinctness).** The audit's third
  attack class — "Replay of a v1 mint as v2" — is **structural** in
  `Foundations.MkAssetId`: `asset_id` carries a `version` field, so a v2 mint of
  "the same" asset is a *different* `asset_id` value (distinct records under A3 /
  Poseidon collision resistance). The model fixes `version = IssuanceVersionV1`
  everywhere (`AssetOf`, `AssetCarrier`, the issuance records), so v1/v2
  non-confusion holds by construction of the digest and needs no separate
  invariant — it is the same fact the abstract digest encoding gives for free.
  When a v2 schema is added (single-circuit version-branch, §6.5 "Forward
  compatibility"), this half becomes a live check; today it is a structural
  guarantee, recorded here for completeness.
- **In-circuit SHA-256 preimage resistance (A6) for `H(creator_pubkey)`** is an
  axiom (Assumptions), not re-proven: clause (b) is modelled at the
  `AddressOf`-image level (`AddressOf(creator_pubkey) = owner`), faithful under
  A5/A6 injectivity of `H(Pk₀)`.
- **The publisher / on-chain layer** (BatchInscription, the global accumulator)
  is out of scope for P7 — authenticity is a per-account compliance-predicate
  property, enforced before a SpendRecord ever reaches a publisher (P2 covers
  the accumulator).
