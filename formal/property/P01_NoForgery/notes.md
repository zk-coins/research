# P01 — No-Forgery — notes

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

Phase-0/1 deliverable: No-Forgery — a coin can be credited only as the proven
output of a Sec. 2.1-compliant transition that was SIGNED by the account that
created it — over the per-account compliance-predicate state machine
`PrInit`/`PrNext` in [`module/Proofs.tla`](../../module/Proofs.tla). The property
module `property.tla` EXTENDS `Proofs` (which EXTENDS `Foundations` +
`Assumptions`); no change is made to the machine itself.

## Two-tier result (read this first)

The package is deliberately **two-tier**, because the No-Forgery claim has a
structural half that is genuinely unbounded-provable and a signature-oracle half
that is not (the oracle grows without bound — see "Why TIER 1 is
`prAuthorised`-free" below):

- **TIER 1 — `INV_Provenance` — UNBOUNDED.** Every credited coin was the output
  of its HOLDER's own Sec. 2.1-compliant transition: `cid.prevAsh.owner =
  AddressOf(holder)`. The coin id structurally embeds its creating prior account
  state (`MkCoinId`'s `prevAsh`); only a `C`-valid `MintStep`/`SendStep` of an
  account `a` ever produces a coin whose `prevAsh.owner` is `a`'s address. Proven
  unbounded by the standard 3-check inductive argument `[2]+[3]+[4]`. This
  invariant reads only `prChSet` + the coin structure (never `prAuthorised`), so
  the induction is **sound for the genuinely unbounded reachable state space**.

- **TIER 2 — `INV_NoForgery` — BOUNDED safety + reduction.** The full
  signature-level statement: every credited coin is a *signed* output under the
  key current in its creating account state (`<<cid.prevAsh.currentPk, cid>> ∈
  SignedOutputs`). Proven by bounded safety check `[5]` (length 6). Its unbounded
  extension reduces to **TIER 1** (the coin was its holder's own compliant
  output) plus the model's **honest-oracle lockstep**: `MintStep`/`SendStep` grow
  `prAuthorised` in step with `prChSet`, signing under the account's own current
  key — so every coin TIER 1 places in `prChSet` has, by construction, the
  matching signature in `prAuthorised`. The negative control shows this lockstep
  is load-bearing.

P01 is one of the two HARD composition properties (Proofs + Onchain). The
**Proofs-machine half** — the half that actually forbids forgery before any
record reaches a publisher — is proven here (TIER 1 unbounded). The **Onchain
admission half** (admission cannot launder a forged coin onto the chain) is
covered by P02 and is cited, honestly scoped, under "Composition / scope" below.

## Why TIER 1 is `prAuthorised`-free (and TIER 2 is bounded)

A maxima probe over the real `PrNext` (recorded below) establishes two facts:

- `|prChSet[a]| ≤ 1` for every account in every reachable state (`ChBoundLE1`,
  length 8, NoError) — the per-account coin-history is bounded.
- `|prAuthorised|` is **unbounded**: `AuthBoundLE4` is VIOLATED at length 8,
  because every `SendStep` adds a fresh signature. The signature oracle grows
  without bound in the number of transitions.

Consequence for the inductive method: Apalache's inductive-step `--init`
generates the symbolic pre-state with `apalache.Gen`, a value of **bounded** size.
An invariant whose truth ENUMERATES `prAuthorised` (e.g. the existential
`∃ sig ∈ prAuthorised: …`, or `SignedOutputs ∋ …`) can only be checked on
pre-states with `|prAuthorised| ≤` the `Gen` budget — which does **not** cover all
reachable states, since `|prAuthorised|` is unbounded. So an unbounded inductive
proof of the *signature-level* statement is not available by this method without
an additional (unbounded-set) abstraction. We therefore:

1. project the unbounded claim onto the `prAuthorised`-free structural invariant
   `INV_Provenance` and prove THAT unbounded (TIER 1, sound: its state is the
   bounded `prChSet` + coin structure); and
2. prove the full `INV_NoForgery` bounded (TIER 2), and reduce its unbounded
   extension to TIER 1 + the honest-oracle lockstep, argued below and
   stress-tested by the negative control.

This is the same honesty discipline P02 applied to its unbounded `onAdmittedChain`
sequence (project the induction onto the variables the safety property actually
needs; document what is carried only as a bounded witness).

## Property statement (M4 ground truth — Pass-3 P1, HIGH for the spec design)

Quoted from the Pass-3 audit (`audit/2026-06-06.03.md`, branch
`origin/audit/spec-2026-06-06-03`), section "P1 · No-Forgery (mints excluded;
covered by P7)":

> **Statement.** A coin `c` with `c.recipient = R`, `c.amount = v`,
> `c.asset_id = a` can exist only as the proven output of a §2.1-compliant
> transition signed by some account's `skᵢ`. A PPT adversary without `skᵢ` for
> that account, and without breaking A1, A5, A7, cannot cause an honest receiver
> to credit `c`.
>
> **Game.** A wins if there exists a coin `c` that an honest receiver credits,
> but `c` was not produced by a valid §2.1 transition.
>
> **Verdict.** Sound under A1, A3, A5, A6, A7. **Confidence: HIGH** for the spec
> design.

## Spec sections formalised (baseline docs@b6972b8, post-docs#40)

- **Proofs §2.1 clause 2** — input authenticity: `txn_sig` MUST be valid under
  `txn_pubkey = prev_account_state.current_pubkey` over the transition message
  `input_nullifiers_root ‖ output_coins_root`. This is `Proofs.Clause2_Inputs`:
  `PrSigValid` over the A7 oracle `prAuthorised`, keyed on
  `PrMsgTag(NullifierSet(w), OutputIds(w))`.
- **Proofs §2.1 clauses 5/6/9** — output coins and the `output_coins_root`:
  every output id is `MkCoinId(prev_account_state, asset, idx)` (clause 5); the
  `ocr` is exactly that set (clauses 6/9). So the SIGNED message commits to the
  very coins the transition outputs.
- **Proofs §2.1 clause 7** — `new_account_state.owner` unchanged; with `PrInit`'s
  canonical empty account this pins `owner = AddressOf(account)`.
- **Foundations §1.4** — `coin.identifier = Hc("Coin", prev_account_state_hash ‖
  asset_id ‖ coin_index)`: the coin id STRUCTURALLY EMBEDS its creating prior
  account state (`MkCoinId`'s `prevAsh`), so a coin carries the identity of the
  account state that produced it — provenance is recovered from existing state,
  with **no ghost ledger**.
- **On-chain §2.4 / §3.6** — the publisher path: a spend takes effect only once
  its `SpendRecord` is in a `BatchBundle` whose `BatchInscription` is admitted
  (cited for the composition half; see scope).

## How the model realises the claim

In `Proofs.tla` the A7 oracle `prAuthorised` grows ONLY when an account's own
current key signs its own transition message: `MintStep` and `SendStep` each add
exactly `<<prev.currentPk, PrMsgTag(NullifierSet(w), OutputIds(w))>>`. A forged
authorisation is never present, and signatures are never removed (monotone
growth). Every coin id that enters an account's coin-history `prChSet` is an
`OutId(prev, t, k)` whose `prevAsh = prev` (the creating prev state, clause 5)
and which lies in that transition's `OutputIds = ocr` (the signed message).

Hence in every reachable state, every held coin traces back to an honest
signature, over a message whose output-coin set contains THAT coin, under the
key `cid.prevAsh.currentPk` that was current in the coin's creating account
state — exactly No-Forgery: no coin exists that was not the signed output of a
compliant transition of the account that created it. TIER 1 machine-checks the
structural half of this (creating account = holder) unbounded; TIER 2 + the
reduction above carry it to the signature level.

### Why no ghost provenance ledger was needed

The task flagged a possible ghost provenance ledger (like P03's `prMinted`). It
proved unnecessary: `Foundations.MkCoinId` already embeds `prevAsh` (the full
creating account state) into every coin id. The structural provenance
(creating-account-state, and via its `owner`/`currentPk` the creating account and
key) is therefore **derivable from the existing `prChSet` + coin structure** —
exactly what TIER 1 reads. No `prVars` extension was made; this is also what keeps
TIER 1 `prAuthorised`-free and thus soundly unbounded.

## Formalised invariants and inductive design

**TIER 1 (unbounded core):**

```
INV_Provenance ==
  \A acct \in Accounts : \A cid \in prChSet[acct] :
     cid.prevAsh.owner = AddressOf(acct)
```

Every credited coin's creating account state is owned by its holder — i.e. the
coin was the output of the holder's OWN compliant transition. `MintStep`/
`SendStep` build each output id as `OutId(prState[acct], …)`, whose
`prevAsh.owner = prState[acct].owner = AddressOf(acct)` (clause 7 owner-
invariance); no other account or adversary action introduces such a coin.
`prAuthorised`-free ⇒ bounded state ⇒ soundly unbounded.

**TIER 2 (full signature-level statement, bounded):**

```
\* the (signerKey, coin) relation honest signatures attest, built once:
SignedOutputs == UNION { { <<sig[1], cid>> : cid \in sig[2].ocr } : sig \in prAuthorised }

INV_NoForgery ==
  \A acct \in Accounts : \A cid \in prChSet[acct] :
     << cid.prevAsh.currentPk, cid >> \in SignedOutputs
```

`SignedOutputs` is the flat set of `(signerKey, coinId)` pairs every honest
signature in `prAuthorised` attests. `INV_NoForgery`: every credited coin is a
*signed* output under the key current in its creating account state
(`cid.prevAsh.currentPk`; clause 2 `txn_pubkey = prev.current_pubkey`). The flat
`UNION` form is logically identical to the existential
`∃ sig ∈ prAuthorised: cid ∈ sig[2].ocr ∧ sig[1] = k` but cheaper for the SMT
backend; it is checked BOUNDED because it reads the unbounded `prAuthorised`.

**Inductive strengthening (TIER 1).** `INV_Provenance` alone is not inductive: a
fresh account must still be canonical for its first output to embed the right
owner, and a transitioned account must keep its owner pinned. The SAME two local
strengthenings P07 uses close it:

- **S1 — owner pinned.** `prState[a].owner = AddressOf(a)` for every account
  (PrInit + clause 7 owner-invariance).
- **S2 — fresh = canonical.** `sendCounter = 0 ⇒ current_pubkey = AddressOf(a) ∧
  balances empty ∧ coin-history empty`. Pins a fresh account (so its first output
  embeds the right owner) and keeps the empty-history base case true.

```
IndInv == PrTypeOK
          /\ \A a \in Accounts : OwnerPinned(a) /\ FreshIsCanonical(a)   \* S1, S2
          /\ INV_Provenance
```

`IndInv` is closed under `PrNext` (inductive step `[3]`).

**Reduction of TIER 2 to TIER 1 + honest oracle (the unbounded extension).** Fix
any reachable state and any `cid ∈ prChSet[acct]`. By TIER 1, `cid` was the output
of a `C`-valid `MintStep`/`SendStep` of `acct` (its `prevAsh.owner =
AddressOf(acct)`). Every such step in `Proofs.tla` executes, atomically with
adding `cid` to `prChSet`, `prAuthorised' = prAuthorised ∪ {<<prev.currentPk,
PrMsgTag(NullifierSet, OutputIds)>>}` with `cid ∈ OutputIds` and
`prev.currentPk = cid.prevAsh.currentPk` (the creating state's key, clause 5/9).
Signatures are never removed (monotone). Hence `<<cid.prevAsh.currentPk, cid>> ∈
SignedOutputs` in that and every later state — which is `INV_NoForgery`. The step
is the model's *honest-oracle lockstep*; the negative control (below) breaks it
and makes `INV_NoForgery` fail, demonstrating the lockstep is load-bearing rather
than vacuous. This reduction is a hand proof over the model's two actions (each
adds ≤ 1 coin and the matching signature); the bounded check `[5]` machine-checks
it to length 6.

### Decisions / modelling notes

- **`IndInvInit` via `Gen`.** The inductive-step `--init` predicate must ASSIGN
  every variable. An explicit set-of-functions carrier for `prState` makes
  Apalache try to expand a set of functions. The supported idiom (same family as
  P02's `Gen(4)` and P07's `Gen(3)/Gen(6)`) is to generate each variable with
  `Gen` and pin it with the `IndInv` body, which includes `PrTypeOK` (domains =
  `Accounts`, per-account `WfAccountState`, the `prChSet` / `prAuthorised`
  element shapes). `IndInvInit` is therefore logically equivalent to `IndInv`.
- **Constant instance.** `ConstInit == PrConstInit`: `Accounts = {1,2}`, one v1
  asset family (`AssetNameHash = 100`, `AssetDecimals = 8`). The inductive
  argument is **per-account local** (every `IndInv` conjunct quantifies one
  account, every action touches a single account), so a two-account universe
  certifies the general result; a three-account confirmation is noted below.
- **No `apalache.cfg`.** The unbounded proof is several runs with different
  `--init`/`--inv`/`--length` combinations a single TLC-style config cannot
  express; `ConstInit` is consumed via `--cinit`. `./verify.sh` is the canonical
  reproducible runner; it stages the four modules into a temp dir (Apalache
  resolves EXTENDS from the spec's own directory) so only `property.tla` is
  committed here.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary:

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 0 | vacuity probe | `--init=PrInit     --next=PrNext --inv=NoCoinsEver     --length=3` | **Error (violated, expected)** |
| 1 | bounded sanity | `--init=PrInit     --next=PrNext --inv=IndInv         --length=6` | NoError |
| 2 | inductive base (T1) | `--init=PrInit     --next=PrNext --inv=IndInv         --length=0` | NoError |
| 3 | inductive step (T1) | `--init=IndInvInit --next=PrNext --inv=IndInv         --length=1` | NoError |
| 4 | implication (T1) | `--init=IndInvInit --next=PrNext --inv=INV_Provenance --length=0` | NoError |
| 5 | TIER-2 safety | `--init=PrInit     --next=PrNext --inv=INV_NoForgery   --length=6` | NoError |

Checks **2 + 3 + 4** together are the **unbounded** proof of TIER 1
(`INV_Provenance`); check **5** is the bounded TIER-2 safety result. All runs use
`--cinit=ConstInit`. The TIER-1 step `[3]` is the expensive run (~2 min solo,
longer under concurrent load); the others are seconds.

**Uniformity in |Accounts|.** The base [2] and implication [4] checks were
re-run with a `--cinit` fixing `Accounts = {1,2,3}`; both report NoError. The
inductive argument is per-account local (each `IndInv`/`INV_Provenance` conjunct
quantifies a single account, and every action touches one account), so the step
result is uniform in the number of accounts; the committed `ConstInit` fixes
`{1,2}` for the default run, which is where the step [3] is checked.

## Vacuity probe + reachable-maxima probe

**Non-vacuity.** Both invariants quantify over `cid ∈ prChSet[acct]`, trivially
true if no account holds a coin. Check **[0]** verifies the model actually CREDITS
coins: `NoCoinsEver` (no account ever holds a coin) is **VIOLATED at depth 1** — a
`MintStep` credits the first coin —

```
apalache-mc check --cinit=ConstInit --init=PrInit --next=PrNext --inv=NoCoinsEver --length=3 property.tla
=> The outcome is: Error  (state invariant violated at State 1)
```

so the `NoError` verdicts are statements about real credited coins, not vacuous
quantifications.

**Maxima probe (justifies the two-tier split).** Over the real `PrNext`:

```
apalache-mc check ... --inv=ChBoundLE1   --length=8   => NoError   (|prChSet[a]| <= 1 always)
apalache-mc check ... --inv=AuthBoundLE4 --length=8   => Error     (|prAuthorised| exceeds 4: unbounded)
```

`|prChSet[a]|` is bounded but `|prAuthorised|` grows without bound — which is why
TIER 1 (`prAuthorised`-free) is soundly unbounded and TIER 2 (reads
`prAuthorised`) is given as a bounded check plus the reduction to TIER 1.

## Negative control (the honest-signing oracle is load-bearing)

In a `/tmp` copy of the four modules, `Proofs.PrNext` was extended with an
adversary action `AdvForgeStep(a, victim)` that credits a coin into account `a`'s
coin-history WITHOUT a matching honest signature — it grows `prChSet[a]` with a
coin id built over the VICTIM account's prev state (so `cid.prevAsh.currentPk =`
the victim's key) while `prAuthorised` is **not** extended. This is exactly the
"grow `prChSet` for a coin the creating key never signed" forgery the honest
oracle forbids (equivalently: the adversary credits a coin under a key whose
signature is absent from the oracle). Running

```
apalache-mc check --cinit=ConstInit --init=PrInit --next=PrNext --inv=INV_NoForgery --length=2 property.tla
```

returns a counterexample at **State 1** (`The outcome is: Error`, exit 12):

```
State0:  prAuthorised = {},  prChSet = (1 |-> {}, 2 |-> {})
State1:  AdvForgeStep(a=1, victim=2)
         prAuthorised = {}                              (oracle NOT grown — the forgery)
         prChSet[1]   = { [ asset |-> [creator |-> 2, ...], idx |-> 0,
                            prevAsh |-> [ owner |-> 2, currentPk |-> 2, ... ] ] }
         => account 1 credits a coin created under key 2 with NO signature in
            prAuthorised => INV_NoForgery violated (no honest signature exists
            whose ocr contains the coin under key 2).
```

With the honest oracle intact (no `AdvForgeStep`), every credited coin has its
matching `<<currentPk, PrMsgTag(…, OutputIds)>>` signature, the counterexample
disappears, and checks [0]–[5] all report their expected outcomes — confirming the
model can SEE a forgery, so the verified verdict is meaningful and the
honest-oracle lockstep that TIER 2's reduction relies on is load-bearing. The
committed `property.tla` / `module/Proofs.tla` keep the honest A7 oracle intact;
the `/tmp` copy and its `_apalache-out` were discarded.

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 P1 label **HIGH** (for the spec design); Apalache verdict **VERIFIED —
TIER 1 (structural provenance) unbounded, TIER 2 (signature-level) bounded +
reduced** ⇒ **confirmed** at the compliance-predicate level for the Proofs-machine
half.

| Property | Pass-3 | TIER 1 structural | TIER 2 signature-level |
|---|---|---|---|
| P1 No-Forgery (Proofs-machine half) | HIGH | **verified (unbounded)** | verified (bounded len 6) + reduction to TIER 1 |

The attack classes the audit's enumeration leans on map to the clauses the
negative control shows load-bearing:

- *Forgery of the `SpendRecord` signature* (needs breaking A7) — defeated by
  clause 2's `PrSigValid` under `current_pubkey` (the honest `prAuthorised`
  oracle), the exact conjunct the negative control removes.
- *Recomputation of `coin.identifier` for a forged coin* (faking
  `creating_prev_ash`) — `coin.identifier` STRUCTURALLY embeds `prevAsh`
  (`MkCoinId`), so a different creating state is a different coin id; clause 2(c)
  recomputes it and a mismatch is a Poseidon collision (A3).
- *Substitution of a different `Pkᵢ` in clause 2* — `txn_pubkey =
  prev.current_pubkey` (clause 2) composed with clause 7's owner-invariance
  (S1) and S2 forces the signing key to be the creating account's own key.

Full reconciliation is deferred to Phase 4.

## Composition / scope (what stays at the A1/A5/A7 oracle level)

P01 is a HARD composition property; this package proves the **Proofs-machine
half unbounded** and documents the Onchain half honestly:

- **Onchain admission half (covered by P02).** "Admission cannot launder a
  forgery onto the chain" is enforced by `Onchain.Admit`'s aggregate-proof
  conjunct **`[AGG]` (§3.3 / A15, `AggSoundValid(cand.memberValidities)` with
  `memberValidities ≠ {}`)** — every member `SpendRecord` verifies under its own
  per-account recursive proof — together with the **`[SIG]`** publisher-signature
  conjunct and the **`[GATE]`** first-spend-wins conjunct that P02 proves
  load-bearing and unbounded over the concrete `BatchInscription` machine. A
  forged coin would have to enter a member `SpendRecord` whose per-account proof
  fails `C` (forbidden here, P01) or pass `[AGG]` with an invalid member
  validity (forbidden by A15). At the abstract level `[AGG]` is the
  Assumptions-oracle bound `AggSoundValid`; the composed Both* machine claim is
  therefore the conjunction of THIS P01 (no compliant transition produces a
  forged coin) and P02 (no admission step launders a coin past the gate), not a
  single new monolithic invariant — stated here as the composition, machine-
  checked on each half.
- **Direct forgery of the validity proof / Fiat-Shamir misuse** — needs breaking
  A1 (Plonky2 knowledge soundness); axiom (`Assumptions`), not re-proven.
- **`H(Pk₀) == owner` preimage / asset-id and coin-id collisions** — A5/A6
  preimage binding and A3 collision resistance; modelled at the `AddressOf` /
  structured-digest level (Foundations digest abstraction), not re-proven.
- **Sign-to-contract nonce malleability** — A5/A7 (BIP-340 EUF-CMA); the model
  carries `txn_sig` validity as the A7 oracle outcome, not the curve arithmetic.
- **Mints** are excluded from P1 by the audit and covered by **P07** (issuance
  authenticity); the present invariant covers the send/credit path (a forged
  *non-mint* coin) and, via the same `prAuthorised`/`OutputIds` discipline, the
  mint output coins as well — no coin of any origin enters `prChSet` without its
  honest signature.
