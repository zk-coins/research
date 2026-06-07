# P10 — Capability Discipline — notes

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
JVM             : Temurin OpenJDK 17.0.19
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so a
divergent result on a future version is attributable.

## What this is

Phase-2 property deliverable: the Sec. 5 capability-gated pull endpoint
(`module/Access.tla`, prefix `Ac`) verified **unbounded** by an inductive
invariant. The property module `property.tla` EXTENDS `Access`, takes its release
machine (`AcInit`/`AcNext`/`AcTypeOK`/`AcConstInit`, vars `acVars`) and the three
dynamically machine-checked Sec. 5 release-discipline invariants it exposes (the
fourth attack class, spend escalation, is structural — see the M4 fidelity fix
section), and closes the inductive 3-check pattern over them. Because Apalache resolves `EXTENDS` only from the spec's own directory,
[`verify.sh`](./verify.sh) stages `property.tla` together with its module
dependencies (`Foundations.tla`, `Assumptions.tla`, `Access.tla`) from
`formal/module/` into a scratch directory at run time and checks there — the
module files are never duplicated into this committed directory, so they cannot
drift from `formal/module/*` (same convention as `module/verify-modules.sh` and
the other property runners).

## Property statement (M4 ground-truth)

- **Prose spec sections formalised:** Sec. 5.1 (capability-gated pull: exactly two
  authorisations; challenge→proof with server-issued nonce + expiry, consumed
  once; `chan_bind` host-binding / proof-forwarding defence), Sec. 5.1(b) + Sec.
  5.2 (view grant: release **only** within scope; grant must be unexpired and
  unrevoked; forward-only revocation), Sec. 5.2/5.3/5.4/5.8 (view capabilities are
  read-only and never confer spend authority; bearer secrets `zkview`/`zkavk` are
  not node authorisations, Sec. 5.1 para 2). Baseline `zk-coins/docs@b6972b8`.
- **Pass-3 Sec. 4 P10 statement (the oracle), quoted verbatim:**
  > "A presented capability releases at most the data its scope authorizes; no
  > capability widens spend authority; bearer capabilities (`zkview`, `zkavk`)
  > decrypt only what their key allows; `OwnershipProof` and `GrantProof` cannot
  > be replayed against a different node."

  > "A wins if it can cause a node to release Private data beyond a presented
  > capability's scope, or replay a captured `OwnershipProof` against a different
  > node, or escalate a view capability into a spend."

  Pass-3 verdict: **Sound under A7, A9. Confidence: HIGH.**
- **Formalised invariant:** `INV_P10` is the conjunction of the **three**
  dynamically machine-checked Sec. 5 release-discipline invariants
  `module/Access.tla` exposes. The fourth Pass-3 attack class, spend escalation,
  is a **structural** by-construction property and is intentionally **not** a
  conjunct of `INV_P10` (see the "M4 fidelity fix" section below).

  | Pass-3 P10 attack class | Access invariant | Status | Content |
  |---|---|---|---|
  | scope evasion (Sec. 5.1 normative) | `AcNoReleaseWithoutCapability` | dynamic, in `INV_P10` | every released record exists in the store and is labelled with its own subject |
  | scope evasion (Sec. 5.1(b) check 4) | `AcScopeRespected` | dynamic, in `INV_P10` | every released record belongs to the subject it was released for |
  | replay against a different node (A14, `chan_bind`) | `AcNoReplayAcrossHosts` | dynamic, in `INV_P10` | every release is bound to `ServingHost`; the requester's *presented* chan_bind is carried through to the audit `host`, so the gate is load-bearing |
  | spend escalation from a view capability | *(none)* | **structural, not dynamically exercised** | release write set is `{acConsumed, acReleased}`; no action grows the signing oracle except honest `Sign`; VIEW/SPEND separation is the A9 axiom |

## Modelling decisions

- **Builds on the existing Access module, unchanged.** P10 is exactly the safety
  envelope `module/Access.tla` was written to carry; the property module adds no
  new state or actions. It only (a) names `INV_P10` as the conjunction, (b)
  packages `IndInv_P10` and its assignment-form `IndInvInit_P10`, and (c)
  re-exports the constant world as `P10ConstInit == AcConstInit`. This keeps the
  proof faithful to the Phase-1 module and avoids a divergent second model.
- **Inductive invariant.** `IndInv_P10 == AcTypeOK /\ INV_P10`. `AcTypeOK` is
  carried because the inductive-step check supplies the pre-state symbolically via
  `--init=IndInvInit_P10`; without the type constraint the SMT solver could place
  arbitrary, ill-typed values into the six variables and spuriously break a safety
  conjunct. With `AcTypeOK` pinning the per-state record domains, every conjunct of
  `INV_P10` is a closed predicate over `acReleased` and `Records`, and every action
  either leaves `acReleased` unchanged or extends it **only** with entries the
  release actions construct to satisfy all three conjuncts: `rec \in Records` and
  `rec.subject = subject` by the set-comprehension filter, and `host |-> presented`
  where `presented = ServingHost` is forced by the admit predicate's
  `ChanBindMatches(presented, ServingHost)` guard (the requester may *present* a
  ForeignHost binding, but then the action is disabled). So `INV_P10` is preserved.
  No further strengthening was required.
- **Assignment-form `--init` for the step.** Apalache requires every variable to be
  *assigned* in an init predicate. `IndInvInit_P10` restates `AcTypeOK` in
  `x \in SUBSET S` / `x \in 0..MaxTime` assignment shapes and adds `INV_P10` as a
  constraint over the assigned state; it is logically equivalent to `IndInv_P10`
  (`x \in SUBSET S ⟺ x \subseteq S`).
- **`--next` on every check.** Unlike P02 (whose transition operator happens to be
  named `Next`, the Apalache default), this module's transition is `AcNext`, so
  every run — including the length-0 base and implication checks — passes
  `--next=AcNext` (Apalache's `ConfigurationPass` requires a resolvable transition
  predicate even at length 0).
- **Constant world (`AcConstInit`).** Two hosts (so the cross-host /
  proof-forwarding case is reachable), two subjects, two public keys, three
  records over two assets and two timestamps, `MaxTime = 3`. The release discipline
  is per-request local, so this small world exercises every action and guard.
- **Adversarial chan_bind presentation.** The release actions
  (`ReleaseByOwnership`, `ReleaseByGrant`) let the requester PRESENT a chan_bind
  for some host `h \in {ServingHost, ForeignHost}` — modelling a proof captured by
  or bound to a foreign node (the Sec. 5.1 proof-forwarding / MITM case). The
  presented binding is carried THROUGH to the audit entry's `host` field
  (`host |-> op.chanBind` / `gp.chanBind`), so the cross-host case is genuinely
  REACHABLE and `ChanBindMatches(presented, ServingHost)` is the load-bearing gate
  that prevents a ForeignHost-bound release. (Before the M4 fix the actions
  hardcoded `host |-> ServingHost`, which made `AcNoReplayAcrossHosts` vacuous; see
  below.)
- **Abstractions inherited from `Access.tla` (stated there, summarised here):**
  signatures via the `SigValid` A7 oracle grown only by honest `Sign` actions;
  `H(Pk0)==subject` via the injective `AddressOf` map (A5/A6); `chan_bind` as host
  equality `ChanBindMatches` (A14); scope as an asset-set × time-window;
  ownership = the universal `FullScope`; time as an abstract monotone clock
  `acNow`. Bearer caps (`zkview`/`zkavk`) are modelled as **never** causing a node
  release (Sec. 5.1 para 2); spend non-escalation is recorded as a structural
  property, not a dynamic invariant (see below).

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary (all
wall-clock < 2 s each on the host above; runner: [`verify.sh`](./verify.sh)):

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=AcInit --next=AcNext --inv=IndInv_P10 --length=6` | NoError |
| 2 | inductive base | `--init=AcInit --next=AcNext --inv=IndInv_P10 --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit_P10 --next=AcNext --inv=IndInv_P10 --length=1` | NoError |
| 4 | implication | `--init=IndInvInit_P10 --next=AcNext --inv=INV_P10 --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded proof. All runs use
`--cinit=P10ConstInit` (= `Access.AcConstInit`).

**Uniformity in the world size.** Checks 2/3/4 were re-run against a larger
constant world (`Pubkeys = Subjects = {1,2,3}`, `MaxTime = 4`, four records over
two assets/three timestamps); all three report NoError. The inductive argument is
per-request local, so the result is uniform in the world size; the committed
`P10ConstInit` fixes the small world for a fast default run.

## Strengthening log

- **Attempt 0 (`IndInv_P10 == AcTypeOK /\ INV_P10`): CLOSED.** The base, step and
  implication checks all returned NoError. No conjunct had to be added to make the
  invariant inductive. The reason it is inductive without strengthening: the three
  safety conjuncts quantify only over `acReleased`, and the only actions that grow
  `acReleased` (`ReleaseByOwnership`, `ReleaseByGrant`) build each new entry to
  satisfy all three conjuncts — the record is drawn from `Records` and its
  `subject` equals the release `subject` by the set-comprehension filter, and the
  `host` (= the presented chan_bind) is forced equal to `ServingHost` by the admit
  predicate's `ChanBindMatches` guard, which must hold for the action to fire.
  `AcTypeOK` is the only carried strengthening, and it is needed solely to type the
  symbolic pre-state of the step (see "Modelling decisions"). No second or third attempt was
  necessary.

## M4 fidelity fix — what was vacuous, why, and the fix

A Phase-2 fidelity review proved two of the original four P10 invariants vacuous.
Both are now corrected. This section is the audit record.

### (1) `AcNoReplayAcrossHosts` was vacuously true — FIXED

**Defect.** The original `ReleaseByOwnership` / `ReleaseByGrant` hardcoded
`chanBind |-> ServingHost` in the constructed proof AND `host |-> ServingHost` in
the released audit record. A ForeignHost-bound proof therefore never reached a
release attempt, and `\A e \in acReleased : e.host = ServingHost` held trivially —
deleting *all* the `chan_bind` conjuncts still returned NoError. The header's
negative-control claim ("delete `ChanBindMatches` → counterexample") was FALSE.

**Fix (faithful to Sec. 5.1).** The requester now PRESENTS a chan_bind for some
host `h \in {ServingHost, ForeignHost}` (modelling a proof captured by / bound to
a foreign node — the proof-forwarding / MITM attack of Sec. 5.1). The release
actions carry that presented binding through to the audit record
(`host |-> op.chanBind` / `gp.chanBind`). The admit predicates' existing
`ChanBindMatches(presented, ServingHost)` and challenge-side `ch.chanBind =
presented` are now the ONLY thing preventing a ForeignHost-bound proof from
releasing — i.e. genuinely load-bearing. All other behaviour is unchanged; Access
still typechecks, the `verify-modules.sh` gate is all green, and `verify.sh`
returns 4/4 NoError.

### (2) `AcNoSpendEscalation` was a tautology — REMOVED, re-scoped as structural

**Defect.** The conjunct read `\A e \in acReleased : \A pk \in Pubkeys :
CanDecrypt({pk},pk) => e.rec \in Records`. But `CanDecrypt({pk},pk) == pk \in {pk}
== TRUE` and `e.rec \in Records` holds for every audit entry by `AcTypeOK`, so the
implication reduced to `e.rec \in Records` — it asserted nothing about spend
authority. The named property (a view capability never confers spend authority)
was never tested.

**Fix (STRUCTURAL-HONEST route, the pattern accepted for P08's structural
conjunct).** Rather than ship another tautology, `AcNoSpendEscalation` is dropped
from the machine-checked `INV_P10` and documented as a **structural,
by-construction** property — clearly labelled "structural, not dynamically
exercised" in `module/Access.tla`, this file, and `certificate.txt`. The honest
grounds: the release actions' write set is `{acConsumed, acReleased}`; no action
in `AcNext` writes the signing oracle `acAuthorised` except the honest `Sign`
action (there is no spend-granting action in the Access machine at all), so a
release can never confer spend authority; the VIEW/SPEND key separation is a
Foundations/Assumptions-level axiom (A9, hardened BIP-32 derivation). A *dynamic*
formulation was considered (a ghost `acSpendAuthorised` set the invariant could
watch) but would be trivially monotone-empty — grown by no action — i.e. another
vacuous claim, so the structural route was chosen.

The certificate headline is therefore: **P10 = NoReleaseWithoutCapability +
ScopeRespected + NoReplayAcrossHosts (machine-verified), with spend-escalation
structural.**

## Negative control (the chan_bind gate is load-bearing) — REAL violation

To show the proof is meaningful rather than vacuous, the load-bearing chan_bind
guard was disabled in a throwaway copy of `Access.tla` (`/tmp`, not committed).
Removing BOTH `ChanBindMatches(., ServingHost)` conjuncts — from `OwnershipAdmits`
and `GrantAdmits` — and running

```
apalache-mc check --cinit=P10ConstInit --init=AcInit --next=AcNext --inv=INV_P10 --length=4 property.tla
```

returns `The outcome is: Error` with `AcNoReplayAcrossHosts` (INV_P10's third
conjunct) VIOLATED at **State 3**:

```
State2: acIssued = { [chanBind |-> 20, expiry |-> 1, nonce |-> 1, subject |-> 1] }
        (IssueChallenge bound to host 20 = ForeignHost)
State3: acReleased grows with TWO entries, each host |-> 20 (ForeignHost)
        => AcNoReplayAcrossHosts violated: e.host (20) != ServingHost (10)
```

i.e. without the gate, a proof presenting a ForeignHost (20) binding releases at
that foreign host — a genuine cross-host replay (a proof bound to host X accepted
at host Y), exactly the Pass-3 P10 "replay against a different node" win. With the
gate present, all four `verify.sh` checks return NoError. This is now a REAL
violation: it depends on the M4 fix that carries the presented binding through to
the audit record (previously the actions hardcoded `host |-> ServingHost`, which
made both the control and the invariant vacuous).

## Cross-check vs Pass-3 (Phase-4 input)

| Property | Pass-3 label | Apalache verdict | Reconciliation |
|---|---|---|---|
| P10 Capability Discipline | **HIGH** (sound under A7, A9) | **VERIFIED (unbounded)** | **confirmed** at the release-machine level |

The Apalache proof confirms the **release-discipline** half of Pass-3 P10 (scope
respected, no cross-host replay, no release without a valid in-scope capability) as
a machine-checked inductive invariant; the spend-escalation class is the structural
by-construction property described above (not a dynamic invariant). The two
assumptions Pass-3 conditions on map to model abstractions: A7 (EUF-CMA) is the
`SigValid` oracle grown only by honest `Sign`; A9 (BIP-32 PRF, "view keys cannot
derive SPEND") backs the structural spend-non-escalation argument — a release never
grows the signing oracle, and the VIEW/SPEND key separation is the A9 axiom. Full
reconciliation is deferred to Phase 4.

## Scope / what is deliberately NOT modelled

This property owns the **node's release decision** (Sec. 5.1): three dynamically
machine-checked safety claims plus the structural spend-non-escalation property.
The following Sec. 5 material is intentionally out of scope here (rendered in other
modules / later phases), and none of it affects the inductive invariant proven:

- the **bearer-side** cryptographic guarantees — that a `zkview` `K_tx` decrypts
  exactly one coin and a `zkavk` reads the whole history but nothing more (Sec.
  5.3/5.8) — are *client-side* decryption properties over already-public
  ciphertext, not node-release properties; this model treats them only as
  structurally orthogonal to node release (a bearer secret carries no
  ownership/grant capability, so the release predicate is FALSE for it), per
  Sec. 5.1 para 2;
- the **balance attestation circuit** (Sec. 5.7) — a self-contained proof, lives
  in `module/Proofs.tla`;
- the **explorer presentation layer** and Public-mode projection (Sec. 5.5);
- **shareable confirmation-link transport** and the link-secret carrying rules
  (Sec. 5.6), and **Bech32m HRP discrimination** across `zk`/`zkgrant`/`zkview`/
  `zkavk` (Sec. 5.2/5.4 encoding);
- **constant-time `chal` comparison** (Sec. 5.1) — a side-channel (timing)
  property, not a functional state property;
- the spend-key derivation hardening itself (A9 / BIP-32), assumed as an axiom
  rather than re-derived.
