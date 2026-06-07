# P03 — Per-Asset Balance Conservation — notes

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
JVM             : Temurin OpenJDK 17.0.19
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so
a divergent result on a future version is attributable.

## What this is

The Phase-1 P3 deliverable: spec Sec. 2.1 clause 3 ("Per-asset balance
conservation") formalised over the per-account compliance state machine
[`module/Proofs.tla`](../../module/Proofs.tla) and proven **unbounded** by an
inductive invariant. Unlike the P02 Phase-0 smoke test, this property is proven
directly against the harmonised Proofs machine (the one whose predicate `C`
encodes the nine normative clauses).

## Property statement (M4 ground-truth)

- **Prose spec sections formalised:** Proofs **Sec. 2.1 clause 3** — for every
  asset `a` appearing in inputs or outputs, `In(a) + Mint(a) ≥ Out(a)`; all
  amounts range-checked so no sum wraps the field; the difference is retained as
  a change coin — *"funds are conserved, never created except by an explicit,
  predicate-checked Mint(a)"*. Architecture **Sec. 6.5** v1 mint clauses (a)–(d)
  (hooked into clause 3 when an issuance is present). Sec. **6.6** capability
  table row 3 — the prose target *"No inflation of others' assets — for every
  asset_id, outputs never exceed inputs plus an explicit, creator-bound Mint;
  supply is auditable by every receiver"*. Baseline `docs@b6972b8` (post
  `docs#40`).

- **Pass-3 §4 P3 statement (the oracle), quoted verbatim:**

  > **Statement.** For every asset `a`, the total credited supply across all
  > honest receivers equals the total `Mint(a)` produced by valid issuance
  > transitions, minus any retained-by-issuer change.
  >
  > **Verdict.** Sound under A1, A3, A6, A7 **plus** the explicit v1 model where
  > supply is creator-bound, not protocol-bound. **Confidence: HIGH for the
  > design as stated.** The reader must understand that v1 deliberately omits
  > protocol-enforced supply caps (§6.5 names this; future versions will
  > reintroduce them). If "supply conservation" is the wrong frame and "supply
  > discipline" is the right one, the protocol delivers exactly the latter.

  The audit explicitly enumerates *"v1 has no protocol-level cap (§6.5). A
  creator can mint any amount any number of times. **By design**."* — the
  **creator-bound-supply framing**. P3 is therefore the *no-inflation*
  inequality, **not** a supply ceiling.

- **Formalised invariant:** `Conservation == \A a \in AssetCarrier :
  prSupply[a] <= prMinted[a]` — live supply of an asset never exceeds the total
  ever minted for it.

## Modelling decisions

- **Route — a P3-local state-machine wrapper that reuses `C`.**
  `module/Proofs.tla` already carries per-account, per-asset balances and admits
  a transition only when the full predicate `C(...)` holds, so clause 3 is
  enforced on every step by construction. What it does *not* carry is the
  running total of minted supply that conservation quantifies against — that
  total is genuinely **history-dependent** and cannot be recovered from
  `prState`/`prChSet`: a coin's value is private witness data (Sec. 2.1 clause 9,
  amounts stay in the witness) and `prChSet` stores coin **ids**, not amounts.
  A property module may not redefine `PrNext`'s assignments, so `property.tla`
  defines its **own** thin machine that (i) reuses every Proofs datatype,
  helper, and `C` verbatim, (ii) drives the SAME two C-gated actions
  (`P3MintStep` ≙ `Proofs.MintStep`, `P3SendStep` ≙ `Proofs.SendStep`) with the
  SAME `prState`/`prChSet`/`prAuthorised` updates, and (iii) adds two **ghost**
  ledgers.

- **Why two ghosts (and why not the account balances).** In the Proofs machine
  a mint *outputs* the whole minted amount as a coin (In=0, Mint=Out), so the
  retained `balances` difference is 0 and the asset's value lives in the
  coin-history coins, not in `balances`. A balances-only invariant
  (`sum balances ≤ minted`) would therefore be **vacuously true** (held balance
  is identically 0 in the closed self-send world) — it would not be falsifiable
  by an inflation attack and so would not "earn its keep". The faithful conserved
  quantity is **live coin value**, which is exactly `prSupply`:
    - `prSupply[a]` — sum of amounts of unspent coins of `a` across all accounts;
    - `prMinted[a]` — cumulative `Mint(a)` over admitted v1 issuances.
  A mint raises **both** by the issued amount; a self-conserving send
  (In(a)=Out(a)) leaves both unchanged. The ghosts are observational — they never
  gate a transition — so the reachable `prState` behaviour is identical to
  Proofs'. The negative control below shows the resulting invariant **is**
  falsifiable, confirming non-vacuity.

- **`Gen`-based inductive-step start state.** The natural assignment-form
  `prState \in [Accounts -> AcctStateCarrier]` makes Apalache try to *expand a
  set of functions* (`balances` is itself a function inside the record set) and
  it aborts: *"Trying to expand a set of functions. This will blow up the
  solver."* The sanctioned Apalache idiom for an inductive-invariant start state
  is to GENERATE each variable with `Apalache!Gen(k)` (a fresh symbolic value
  whose collection sizes are bounded by `k`) and then CONSTRAIN it with the exact
  typing predicate. `IndInvInit` does this: `prState = Gen(2)` … then `PrTypeOK
  /\ MintedTypeOK /\ Structural /\ Conservation`. It is logically equivalent to
  `IndInv` over the assigned variables, without the function-set expansion.
  (The `Gen` bound only sizes the generated skeleton; the conjoined `PrTypeOK`
  pins the domains to `Accounts` / `AssetCarrier` exactly, so the start state
  still ranges over all well-typed states.)

- **EXTENDS resolution / no committed module copies.** `property.tla` EXTENDS
  `module/Proofs.tla` (→ Foundations, Assumptions, Adversary). Apalache resolves
  `EXTENDS` from the spec's own directory, so [`verify.sh`](./verify.sh) stages
  those four modules + `property.tla` into a `mktemp -d` and runs there; the
  module sources stay single-copy under `formal/module/`. (Same pattern as the
  upgraded P02 runner.)

## Inductive invariant and strengthenings

`IndInv == PrTypeOK /\ MintedTypeOK /\ Structural /\ Conservation`.

Strengthening log (each conjunct beyond `Conservation` was forced by a concrete
Apalache counterexample — well under the 3-failed-strengthening stop rule):

1. **`Conservation` alone — NOT inductive.** The `Gen` start state admits states
   `PrTypeOK` permits but reachability forbids; preservation fails.
2. **+ `PrTypeOK` + `MintedTypeOK` — still NOT inductive (counterexample 1).**
   The step check found a `send_counter = 0` account with a Gen'd
   `current_pubkey = 0` (`∉ Accounts`). A `MintStep` there mints
   `AssetOf(0)` = an asset whose **creator is outside `Accounts`**, so the output
   coin's asset escapes `AssetCarrier` (breaks `PrTypeOK'` on `prChSet`) and the
   ghost `EXCEPT` adds an out-of-carrier ledger key (breaks `MintedTypeOK'`).
   Violated invariant in the trace: the `prChSet` asset-in-carrier conjunct of
   `PrTypeOK`.
3. **+ `Structural` — inductive (closes the proof).** `Structural` carries the
   reachability fact `PrTypeOK` does not: `owner = a` always (Sec. 2.1 clause 7
   never changes `owner`; `PrInit` sets it), and `send_counter = 0 ⇒
   current_pubkey = a`. In the real machine a `MintStep` can ONLY fire from
   `send_counter = 0` (the InitialProof gate), where `current_pubkey = a ∈
   Accounts`, so `AssetOf(current_pubkey) ∈ AssetCarrier` and every ghost update
   stays in-carrier. With `Structural` the inductive step reports NoError.

`MintedTypeOK` additionally pins both ledgers `≥ 0` so the inequality cannot be
vacuously rescued by a negative right-hand side, and pins their DOMAIN to
`AssetCarrier` so a mint cannot silently extend a ledger.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary
(runner: [`verify.sh`](./verify.sh); the inductive step is the heavy run, the
others are ~2–3 s on the host above):

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=P3Init --next=P3Next --inv=IndInv --length=6` | NoError |
| 2 | inductive base | `--init=P3Init --next=P3Next --inv=IndInv --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=P3Next --inv=IndInv --length=1` | NoError |
| 4 | implication | `--init=IndInvInit --next=P3Next --inv=Conservation --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded proof. All runs use
`--cinit=ConstInit` (Accounts = {1,2}, one v1 asset family).

**Uniformity in the universe.** The inductive argument is per-asset,
per-account local: every conjunct of `IndInv` quantifies per asset / per
account, and each action touches exactly one account and (for a mint) one
asset, preserving the others' conjuncts pointwise — so the proof does not depend
on `|Accounts|` or the asset-family count. The committed `ConstInit` fixes two
accounts because the inductive step's SMT cost grows steeply with the universe
size (the step over 2 accounts is the heavy run; a 3-account step with raised
`Gen` bounds did not return within a practical budget and was not used as a
result). The per-account-local structure is the warrant for generality; the
2-account instance is the machine-checked witness.

## Negative control (clause 3 is load-bearing)

In a `/tmp` staging copy: the per-asset conservation conjunct of
`Proofs.Clause3_Balance` —

```
\A a \in AssetsTouched(w) : InAmount(w.inputs,a) + MintAmount(w,a)
                              >= OutAmount(w.templates,a)
```

— was **deleted**, and an **inflating send** added to the property machine: it
spends one held coin of `amount` but emits a change coin of `amount + extra`
(`extra > 0`) of the same asset (`Out(a) > In(a)`, `Mint(a) = 0`), with the
ghost `prSupply` truthfully raised by `extra`. Honestly such a transition is
rejected by `C`; with clause 3 deleted, `C` admits it. Running

```
apalache-mc check --cinit=ConstInit --init=P3Init --next=P3Next \
                  --inv=Conservation --length=4 property.tla
```

returns a counterexample (`State 2: state invariant violated`):

```
State0:  prSupply = 0,  prMinted = 0      (initial)
State1:  prSupply = 1,  prMinted = 1      (account 2 mints 1)
State2:  prSupply = 2,  prMinted = 1      (inflating send: spend 1, emit 2)
         => prSupply[a] <= prMinted[a] violated (2 > 1): asset created from nothing
```

So the model can *see* inflation, and the clause-3 conservation conjunct is
exactly what rules it out — a NoError verdict **with** clause 3 is meaningful.

## Cross-check vs Pass-3 (Phase-4 input)

| Pass-3 label | Apalache verdict | Reconciliation |
|---|---|---|
| **HIGH** (for the design as stated, creator-bound supply) | **VERIFIED (unbounded)** at the compliance-machine level | **CONFIRMED** |

The formalised invariant is the audit's frame *"no inflation of others'
assets"* (Sec. 6.6 row 3) — the inequality `prSupply ≤ prMinted` — **not** a
supply ceiling, which v1 deliberately omits (Sec. 6.5: *"supply discipline is a
creator's commitment, not a protocol guarantee"*). The audit's HIGH is
conditional on A1/A3/A6/A7 plus the explicit creator-bound model; this proof
discharges the clause-3 conservation bookkeeping over the machine, with those
axioms carried as the `Assumptions` oracles (A7 = the `prAuthorised` signing
oracle; A3/A16 = the structured-digest abstraction in `Foundations`). Full
reconciliation is deferred to Phase 4.

## Scope / what is deliberately NOT modelled

Matching the audit's own attack-class enumeration:

- **No protocol supply CAP** — v1 has none by design (Sec. 6.5); P3 is the
  no-inflation inequality, not a ceiling.
- **u128 field non-wrap** — the spec mandates the in-circuit range check; Pass-3
  flags the multi-limb 64-bit-field arithmetic as an *implementation-review
  item, not a spec defect*. Modelled here only as `U128Bound` non-wrap.
- **Creator equivocation / parallel mint histories** — publicly observable on
  Bitcoin, not protocol-prevented (Sec. 6.5); out of frame.
- **A7 signature unforgeability and A3/A16 collision/commitment** properties are
  carried as `Assumptions` oracles, not re-proven here (decision D3).
