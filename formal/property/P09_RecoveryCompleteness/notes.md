# P09 — Recovery Completeness — notes

P09 is the **liveness-flavoured** property: it has a CORRECTNESS (safety) half
and an AVAILABILITY (liveness) half, and the Pass-3 audit grades them
differently — **HIGH for correctness, MEDIUM for liveness**. This package
mirrors that split: the safety half is the unbounded inductive certificate; the
liveness half is handled honestly with an explicitly-weaker surrogate, because
Apalache 0.58.0 cannot encode the fairness the genuine temporal property needs.

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so
a divergent result on a future version is attributable.

## What this is

Phase-2 deliverable: the emergency network-reconstruction recovery path (spec
Sec. 4.5 steps 1–5, under the Sec. 4.6 replication discipline), formalised as a
recovery layer **on top of** [`module/Transport.tla`](../../module/Transport.tla).
`property.tla` EXTENDS `Transport` (which EXTENDS `Foundations` and
`Assumptions`) and defines the safety property `INV_P9_safety`, the inductive
invariant `IndInv`, its assignment-form `IndInvInit`, the liveness surrogate
`RecoverEnabledForHeld`, the genuine temporal property `ConditionalLiveness`,
and the `ConstInit` alias.

## Property statement (M4 ground-truth)

- **Prose spec sections formalised:** Sec. 4.5 (recovery; the fully
  deterministic, trustless fallback — step 1 re-derive keys from seed, step 3
  pull candidate bundles from the untrusted blob cache, step 4 independently
  verify every returned bundle against Bitcoin and discard any that fails,
  step 5 rebuild `AccountState`), Sec. 4.6 (data availability — replication
  factor `k`, default 3, MUST NOT be < 2, on **independent** operators; the
  normative safety invariant "Custody safety **MUST NOT** depend on
  availability. … Availability is a liveness property, never a safety
  property"). Baseline `docs@b6972b8` (post-`docs#40`).

- **Pass-3 §P9 statement (the oracle), quoted verbatim:**
  > **Statement.** From seed + Bitcoin + the §4.6 replicated bundles, a wallet
  > rebuilds its spendable state without trusting any node.
  >
  > **Game.** A wins if the recovery procedure (§4.5) terminates accepting a
  > coin the seed-controlled account did not actually receive, or rejecting a
  > coin it did.
  >
  > *False accept.* §4.5 step 4 mandates independent verification of every
  > returned bundle against Bitcoin. A node returning a forged bundle fails
  > this check.
  > *False reject.* A bundle correctly delivered will verify under §4.5; the
  > only failure mode is **unavailability** (no replica returns it). Liveness,
  > not safety. Replication `k ≥ 2` (default 3) on independent operators makes
  > this an availability-not-safety problem.
  > *Selective censorship by the network.* Multiple independent nodes; if all
  > collude, the user is stuck. … Spec is honest about this being availability,
  > not safety.
  >
  > **Verdict.** Sound for the **stated** trust model. **Confidence: HIGH for
  > correctness**, **MEDIUM for liveness** (depends on `k` and operator
  > independence, which the spec is explicit about).

- **The correctness/liveness split (the whole point of this package).** The
  audit explicitly separates two failure modes. *False-accept* is a SAFETY
  property (the step-4 verify gate makes it impossible) → certified unbounded
  here. *False-reject* is, by the audit's own words, "**Liveness, not safety**"
  — the only way a correctly-delivered bundle is not recovered is
  **unavailability**, which depends on `k`-replication and a reachable honest
  replica. The MEDIUM grade attaches to exactly this availability dependence.

- **Formalised safety invariant:** `INV_P9_safety == (\A b \in recovered :
  AcceptsBundle(b)) /\ (\A b \in recovered : CanDecrypt(bKtxHolders(b),
  WalletId)) /\ (recovered \subseteq RealBundles)` — no false-accept, own-key
  discipline, sound accumulator.

## Recovery-layer design

The recovery layer models a wallet executing the Sec. 4.5 emergency path after
total local-data loss, querying an **untrusted** network (Sec. 4.5 step 3 calls
it "an untrusted blob cache"):

- **Bundle universe split into three classes** (the adversary model):
  - `RealBundles` — genuine own-bundles really received before the loss event:
    their recursive proofs verify against Bitcoin AND they decrypt with the
    wallet's seed-derived keys.
  - `AddressedForgeries` — the genuine Sec. 4.5 step-4 threat: a node returns a
    candidate that *looks* addressed to the wallet (it IS in the wallet's K_tx
    holder set, so the wallet CAN decrypt it) **but its recursive proof does
    NOT verify** (a node "can only withhold, never forge"). This class is what
    makes the verify gate load-bearing independently of the decrypt check —
    without it, the own-key check would mask a missing verify check.
  - unaddressed forgeries — neither verify nor decrypt (the trivially-rejected
    case).
- **Oracles (constant predicates):** `bVerifies(b) == b \in RealBundles` (the
  step-4 proof outcome, fed to the A1 `KnowledgeSound` oracle);
  `bStmtHolds(b) == b \in RealBundles` (so `KnowledgeSound(bVerifies, bStmtHolds)`
  holds — the faithful instance); `bKtxHolders(b)` includes `WalletId` for both
  real bundles and addressed forgeries, `{}` otherwise (A8–A11 `CanDecrypt`).
- **`AcceptsBundle(b)` — the Sec. 4.5 step-4 gate:**
  `KnowledgeSound(bVerifies(b), bStmtHolds(b)) /\ bVerifies(b) /\
  CanDecrypt(bKtxHolders(b), WalletId)`.
- **`Recover` (steps 3–4):** picks a **non-deterministic** candidate set
  `Q \in SUBSET Bundles` — the untrusted network at full strength: it may
  withhold any real bundles and/or inject any forgeries — and unions ONLY the
  gate-accepted members `{b \in Q : AcceptsBundle(b)}` into the accumulator
  `recovered`. `Finish` freezes the accumulator (step 5 begins). Transport
  actions interleave (`TrNext /\ UNCHANGED recVars`).

## INV / IndInv design and strengthenings

- **No-false-accept + own-key discipline + sound accumulator.** All three
  conjuncts reduce to `recovered \subseteq RealBundles`, which is **inductive on
  its own**: `Recover` only unions in `{b \in Q : AcceptsBundle(b)}`, and
  `AcceptsBundle(b) => bVerifies(b) => b \in RealBundles`; `Finish` and
  `TrNext` leave `recovered` unchanged. Conjuncts (i)/(ii) then follow because
  every member of `RealBundles` satisfies both `AcceptsBundle` and
  `CanDecrypt(., WalletId)`. We state all three explicitly to mirror the audit's
  attack-class enumeration (false-accept; own-key; censorship/soundness).
- **Inductive invariant.** `IndInv == TrTypeOK /\ RecTypeOK /\ INV_P9_safety`.
  `TrTypeOK` supplies the finite Transport state-bounding facts (phase domain,
  `trReplicas \subseteq Holders`, the A7 oracle structure); `RecTypeOK` the
  recovery ones (`recPhase \in {recovering,done}`, `recovered \subseteq
  Bundles`). **No additional strengthening conjunct was needed** — all checks
  passed on the first design with no honest failure.
- **`IndInvInit` (assignment form).** Apalache requires every variable
  *assigned* in an `--init` predicate. `IndInvInit` assigns each Transport
  variable from its finite type domain (reusing P08's form — `trDelivery` via
  `MkDeliveryEvent`, `trAuthorised` from `SUBSET ({RecipientOpPk} \X
  {AckMsgTag(m) : m \in NonceU})`) plus `recPhase` and `recovered`, then asserts
  `IndInv`. It is logically equivalent to `IndInv`.
- **Finite nonce universe `NonceU = 0..3`.** Inherited from the Transport layer
  (Retry advances an unbounded nonce); the post-state invariant places no bound
  on the nonce, and the recovery conjuncts do not reference it, so the step is
  uniform in the nonce universe exactly as in P08.

## Modelling decisions

- **No `apalache.cfg`.** The proof is several runs with different
  `--init`/`--inv`/`--length`/`--temporal` combinations, which a single
  TLC-style config cannot express; the constant is pinned in-module
  (`ConstInit == TrConstInit /\ …`, consumed via `--cinit`).
  [`verify.sh`](./verify.sh) is the canonical runner.
- **EXTENDS staging.** Apalache resolves `EXTENDS` only from the spec file's own
  directory. `verify.sh` stages `Foundations.tla`, `Assumptions.tla`,
  `Transport.tla` and `property.tla` in a `mktemp` scratch dir and runs there
  (same pattern as `module/verify-modules.sh`). The scratch dir and all
  `_apalache-out` are removed on exit.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary
(all wall-clock < 3 s each on the host above; runner: [`verify.sh`](./verify.sh)):

### SAFETY half — UNBOUNDED inductive certificate

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=Init --next=Next --inv=IndInv --length=8` | NoError |
| 2 | inductive base | `--init=Init --next=Next --inv=IndInv --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=Next --inv=IndInv --length=1` | NoError |
| 4 | implication | `--init=IndInvInit --next=Next --inv=INV_P9_safety --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded safety proof. All runs use
`--cinit=ConstInit`.

### LIVENESS half — NOT part of the unbounded certificate

| # | Check | Command shape | Outcome |
|---|---|---|---|
| E | enabledness surrogate | `--init=IndInvInit --next=Next --inv=RecoverEnabledForHeld --length=0` | NoError (safety stand-in) |
| L | genuine temporal liveness | `--init=Init --next=Next --temporal=ConditionalLiveness --length=8` | **Unsupported** — `NotImplementedError: Handling fairness is not supported yet` |

### Uniformity confirmation

Checks 2/3/4 were re-run at a larger instance — `Holders={1,2,3,4}`,
`Bundles={1,2,3,7,8,9}`, `RealBundles={1,2,3}`, `AddressedForgeries={7,8}`
(via a local `LargeConstInit`) — all three report **NoError**. The inductive
argument is local (`recovered` grows only by gate-accepted real bundles), so the
result is uniform in the instance sizes; the committed `ConstInit` fixes a fast
default run.

## The liveness-handling decision (honest scope)

The genuine conditional-liveness property is
```
ConditionalLiveness == WF_vars(Recover) => <>[]( \A b \in RealBundles : b \in recovered )
```
i.e. under weak fairness of `Recover`, every genuine own-bundle is eventually
recovered. This is exactly the audit's MEDIUM-liveness statement: availability
conditional on a reachable honest replica being queried; it deliberately says
nothing when every replica is lost or all queried nodes collude (those
executions never satisfy the fairness premise — the audit's "if all collude,
the user is stuck").

**We tried the genuine temporal property and Apalache 0.58.0 cannot check it.**
The temporal encoder throws:
```
scala.NotImplementedError: Handling fairness is not supported yet!
  at ...TableauEncoder.encodeSyntaxTreeInPredicates(TableauEncoder.scala:358)
```
(verify.sh reports this AS EXPECTED.) Apalache's `--temporal` support exists but
does not yet encode `WF_`/`SF_` fairness, which conditional liveness requires.

**Confirmation that the property genuinely needs fairness** (so the surrogate is
not hiding a vacuous result): we also ran the fairness-FREE form `<>[](all
recovered)` with `--temporal` (this IS encodable). It returns a
**counterexample** — without fairness the untrusted network can withhold forever
(a pure stutter/withholding trace), so the bundle is never recovered. That
matches the audit precisely: liveness is genuinely availability-conditional, not
a safety property, and not part of this certificate.

**What the certificate carries instead — the enabledness surrogate.**
`RecoverEnabledForHeld` is a SAFETY (state) invariant: while recovering, for
every genuine own-bundle `b` there exists a query set `Q` whose gate output
contains `b` — i.e. the `Recover` action is always **able** to bring a held real
bundle in. It is **honestly weaker** than temporal liveness: it certifies
"recovery can always make progress on a held real bundle" (no held real bundle
is ever permanently un-admittable by the gate), NOT "it eventually does" (which
needs the fairness Apalache cannot encode). Full temporal liveness is therefore
**out of this certificate's scope**, matching Pass-3's MEDIUM-liveness label. We
do not over-claim: the liveness half remains MEDIUM, contingent on `k`,
operator independence, and a reachable honest replica — exactly as the spec and
the audit state.

## Vacuity probe and negative control (the model earns its keep)

**(V) Reachability / vacuity probe.** Asserting "recovered stays empty" as an
invariant over the reachable space (a small `probe.tla` that EXTENDS `property`
and defines `RecoveredStaysEmpty == recovered = {}`):
```
apalache-mc check --cinit=ConstInit --init=Init --next=Next \
  --inv=RecoveredStaysEmpty --length=4 probe.tla
```
yields **Error** at State 1 (`recovered = {1}` / `{2}`). Recovery actually
recovers something, so `INV_P9_safety` is not vacuously satisfied by an empty
accumulator.

**(NC) Negative control — the verify gate is load-bearing.** Delete the
`bVerifies(b)` conjunct (the Sec. 4.5 step-4 verify gate) from `AcceptsBundle`
in a `/tmp` copy of `property.tla` and run
```
apalache-mc check --cinit=ConstInit --init=Init --next=Next \
  --inv=INV_P9_safety --length=4 property.tla
```
Outcome: **Error** — state invariant 3 (`recovered \subseteq RealBundles`)
violated at State 1:
```
State0: recovered = {},  recPhase = "recovering"
State1: recovered = {8}, recPhase = "recovering"   (Recover admits ADDRESSED forgery 8)
        => recovered \not\subseteq RealBundles      [false-accept]
```
The addressed forgery 8 is decryptable by the wallet but its proof does not
verify; with the verify gate removed, the own-key check alone admits it — a
genuine false-accept, exactly the attack §4.5 step 4 rules out. With the verify
gate present (committed model), 8 fails `bVerifies` and is discarded, so the
false-accept is impossible; the unaddressed forgery 9 is rejected by BOTH gates.
This is why the negative control needs an *addressed* forgery: a forgery the
wallet cannot decrypt would be blocked by the own-key check even with the verify
gate gone, masking the gate's role. The committed `Transport.tla` and
`property.tla` are unchanged; the `/tmp` copy and its `_apalache-out` were
discarded.

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 label: **HIGH for correctness, MEDIUM for liveness.** This certificate
mirrors the split exactly:

| P9 half | Pass-3 | Apalache verdict (this cert) |
|---|---|---|
| Correctness — no false-accept; no false-reject-as-safety | **HIGH** | **VERIFIED — unbounded** (inductive, [2]+[3]+[4]); confirmed at HIGH |
| Liveness — availability of a past bundle | **MEDIUM** | surrogate-only: enabledness [E] certified; full temporal liveness OUT of scope (Apalache 0.58.0 has no fairness support) |

The correctness half is confirmed at the recovery state-machine level: the
step-4 gate the audit names ("a node can only withhold, never forge") is
machine-checked — no forged/unverifiable bundle ever enters `recovered`, and
recovery only credits the wallet's own keys. The liveness half is **not
over-claimed**: the certificate is explicit that availability is conditional on
a reachable honest replica and that the genuine temporal statement is beyond
Apalache 0.58.0's fairness support — the MEDIUM caveat Pass-3 records. Full
reconciliation across all properties is deferred to Phase 4.

**Oracle/baseline provenance.** The Pass-3 P9 prose was written against the
develop snapshot; the baseline here (`b6972b8`) carries the same Sec. 4.5/4.6
recovery + replication design (the self-delivery rule of §4.2 that step 5 relies
on is present). The *claim* (correctness from chain + verifying primitives,
availability from replication) is unchanged, so the audit remains a valid
oracle.

## Scope / what is deliberately NOT modelled

- **The byte-level recursive per-account proof / `AggregateBatchProof` /
  `output_coins_root` inclusion / nullifier-non-membership chain** of Sec. 4.5
  step 4 is the **A1 `KnowledgeSound` oracle**: a candidate's `bVerifies` bit is
  its "proof accepts" outcome, lifted to "statement holds". The full on-chain
  admission machinery is covered by P02 (`module/Onchain.tla`); here it is the
  step-4 acceptance predicate.
- **NIP-44/NIP-59 byte-level encryption** of bundles is the A8–A11 `CanDecrypt`
  oracle over the per-bundle K_tx holder set (own-key discipline), as in P08.
- **The Sec. 4.5 step-5 `AccountState`/balances rebuild** (coin-history SMT,
  `current_pubkey`, `send_counter`) is downstream of acceptance; what P9
  certifies is that the *input* to step 5 contains only genuine, own,
  verified bundles. The arithmetic of balance reconstruction is P03's domain.
- **Replica reachability / `k`-replication dynamics and operator independence**
  are abstracted to the non-deterministic candidate set `Q` in `Recover` (any
  subset of `Bundles`) — the strongest adversary for the safety claim. The
  *quantitative* durability that `k = 3` buys (surviving the loss of any two
  replicas) is the liveness half, which is MEDIUM and out of the unbounded
  certificate per the decision above.
- **Backoff/timing** of the pull schedule is liveness, not modelled.
```
