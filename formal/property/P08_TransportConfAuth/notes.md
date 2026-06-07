# P08 — Transport Confidentiality + Authentication — notes

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so
a divergent result on a future version is attributable.

## What this is

Phase-2 deliverable: the encrypted bundle-delivery layer (spec Sec. 4),
formalised in [`module/Transport.tla`](../../module/Transport.tla), proven
**unbounded** by an inductive invariant. `property.tla` EXTENDS `Transport`
(which EXTENDS `Foundations` and `Assumptions`) and defines the composite
property `INV_P8`, the inductive invariant `IndInv`, its assignment-form
`IndInvInit`, and the `ConstInit` alias.

## Property statement (M4 ground-truth)

- **Prose spec sections formalised:** Sec. 4.1 (roles and transport — the relay
  is trusted only for availability/metadata, never correctness), Sec. 4.2
  (bundle delivery; the NIP-44/NIP-59 envelopes; the normative ACK + retry rule
  with the per-attempt `ack_nonce`; the sender-retention rule), Sec. 4.6 (the
  replication factor `k`, default 3, MUST NOT be < 2; the normative safety
  invariant "custody safety MUST NOT depend on availability"). Baseline
  `docs@b6972b8` (post-`docs#40`).

- **Pass-3 §P8 statement (the oracle), quoted:**
  > "The off-chain delivery channel reveals to a relay (or a passive
  > eavesdropper) only that an opaque, gift-wrapped, NIP-44-encrypted event was
  > stored at some time; the recipient receives a bundle if and only if a valid
  > sender produced it; ACKs cannot be forged."
  >
  > Game (confidentiality): "A relay-controlling adversary distinguishes the
  > content of two delivery events with the same outer envelope."
  > Game (authentication): "An adversary produces a bundle that the recipient's
  > §4.5 verification accepts as valid."
  >
  > Verdict: "Sound under A8, A9, A10, A11. Confidence: HIGH with minor F17
  > (LOW) on ACK freshness wording."

- **F17 and its fix.** Pass-3 flagged sub-finding **F17 (LOW)**: the audited
  spec snapshot's ACK was *content-addressed but not freshness-bound* —
  > "an ACK valid once is valid forever for that (detect_tag, blob_id) pair … A
  > relay that captured one ACK and reuses it on a later, NEW delivery … would
  > falsely tell the sender it can drop."

  F17 has since been **FIXED** in the spec: the delivery event now carries an
  `ack_nonce` ("32 random bytes, sender-chosen … Fresh per retry") that the
  recipient echoes and signs, and the sender verifies "(i) the `op` signature …
  **and** (ii) that the echoed `ack_nonce` matches the nonce the sender chose
  for this delivery attempt" (Sec. 4.2, `docs#36`, folded into `b6972b8`).
  **The Transport module models the FIXED form** — `AckAccepts(a)` requires
  both the A7 op-signature and `a.ackNonce = trAttemptNonce`. So this property
  confirms P8 at HIGH *and* demonstrates that the fix closes the F17 LOW
  (negative control (a) shows the LOW returns if the fix is reverted).

- **Formalised invariant:** `INV_P8 == TrAvailabilityNotSafety /\
  TrAckFreshness /\ TrSenderRetainsUntilSafe` — the three named invariants of
  `module/Transport.tla` for confidentiality (i), ACK integrity+freshness (ii),
  and sender-retention safety (iii).

## INV / IndInv design and strengthenings

- **Confidentiality (i) — `TrAvailabilityNotSafety`.** `~CanReadDelivery(Eve)
  /\ ~CanReadBundle(Eve)`, where `CanDecrypt(keyHolders, who) == who \in
  keyHolders` is the A8–A11 oracle. Eve (the relay/eavesdropper) is in neither
  `IvkHolders` nor `KtxHolders`, so it decrypts nothing. This is a *constant*
  predicate over the holder sets, hence preserved by every action — but it is
  load-bearing as the modelled content of Sec. 4.6's "availability is never
  safety": even after the sender drops its copy (worst availability case), no
  non-holder can read the delivery or the bundle.

- **ACK integrity + freshness (ii) — `TrAckFreshness`.** `trAckOk =>
  <<RecipientOpPk, AckMsgTag(trAttemptNonce)>> \in trAuthorised`. This is the
  genuinely inductive conjunct. `Ack` sets `trAckOk` only via `AckAccepts`,
  whose conjunct (ii) `a.ackNonce = trAttemptNonce` binds the accepted ACK to
  the current attempt, and whose conjunct (i) `SigValid` (A7 EUF-CMA) requires
  the recipient to have signed `AckMsgTag(a.ackNonce)`. `Retry` advances the
  nonce only while `trAckOk = FALSE`, so freshness is vacuous immediately after
  a retry and re-established only by a fresh `Ack`.

- **Sender-retention (iii) — `TrSenderRetainsUntilSafe`.** `~trSenderHasCopy =>
  (trAckOk /\ Cardinality(trReplicas) >= K)`. `Drop` is the only action that
  clears `trSenderHasCopy`, and it is guarded by `trAckOk /\ |trReplicas| >= K`;
  every action is guarded by `trPhase = "published"`, so once `Drop` moves the
  phase to `"dropped"` the state is frozen and retention cannot be re-falsified.

- **Inductive invariant.** `IndInv == TrTypeOK /\ INV_P8`. `TrTypeOK` supplies
  the finite state-bounding facts the SMT step needs (phase domain `{published,
  dropped}`, `trReplicas \subseteq Holders`, and the A7 structural fact that
  `trAuthorised` only ever holds the recipient's `op` key). **No additional
  strengthening conjunct was needed** — the three sub-invariants are each
  preserved under the phase guards, and the only coupling (freshness ↔ current
  nonce) is enforced by the action guards rather than by a separate invariant.
  All checks passed on the first design with no honest failure.

- **`IndInvInit` (assignment form).** Apalache requires every variable to be
  *assigned* in an `--init` predicate; a bare implication/membership is not an
  assignment. `IndInvInit` assigns each variable from its finite type domain
  (`trDelivery` reconstructed via `MkDeliveryEvent`, `trAuthorised` from
  `SUBSET ({RecipientOpPk} \X {AckMsgTag(m) : m \in NonceU})`), then asserts
  `IndInv`. It is logically equivalent to `IndInv`.

- **Finite nonce universe `NonceU = 0..3` (uniformity).** Transport's nonce is
  unbounded (`Retry` does `trAttemptNonce + 1`), so the carrier is infinite and
  Apalache cannot map over `Int`. The attempt nonce and the authorised ack tags
  are coupled *only by equality*, so the inductive step is uniform in the nonce
  universe: a finite `NonceU` containing the attempt nonce, an earlier (stale)
  nonce, and a fresh-retry successor certifies the general result. Crucially the
  *post-state* invariant `IndInv` places **no** bound on the nonce, so a `Retry`
  stepping to a successor outside `NonceU` is still checked. Confirmed by
  re-running the three inductive checks at `NonceU = 0..6` with `Holders =
  {1,2,3,4}` (all NoError; see "Uniformity" below).

## Modelling decisions

- **No `apalache.cfg`.** The unbounded proof is four runs with different
  `--init`/`--inv`/`--length` combinations, which a single TLC-style config
  cannot express; the constant is pinned in-module (`ConstInit == TrConstInit`,
  consumed via `--cinit`). [`verify.sh`](./verify.sh) is the canonical runner.

- **EXTENDS staging.** Apalache resolves `EXTENDS` only from the spec file's own
  directory. To keep the public property directory free of duplicated module
  files, `verify.sh` stages `Foundations.tla`, `Assumptions.tla`,
  `Transport.tla` and `property.tla` in a `mktemp` scratch dir and runs there
  (the same pattern as `module/verify-modules.sh`'s composition smoke). The
  scratch dir and all `_apalache-out` are removed on exit.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary
(all wall-clock < 3 s each on the host above; runner: [`verify.sh`](./verify.sh)):

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=TrInit --next=TrNext --inv=IndInv --length=10` | NoError |
| 2 | inductive base | `--init=TrInit --next=TrNext --inv=IndInv --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=TrNext --inv=IndInv --length=1` | NoError |
| 4 | implication | `--init=IndInvInit --next=TrNext --inv=INV_P8 --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded proof. All runs use
`--cinit=ConstInit` (TrConstInit). Note `--next=TrNext` is passed on every run,
including the length-0 base/implication checks: with no `--next`, Apalache
defaults to looking for an operator literally named `Next`, which this model
does not define (the transition is `TrNext`).

### Uniformity confirmation

Checks 2/3/4 were re-run at a larger instance — `Holders = {1,2,3,4}` (via a
local `LargeConstInit` with the same `K=3`, `Eve=99`, holder sets) and
`NonceU = 0..6` — all three report **NoError**. The inductive argument is local
and coupled only by equality, so the result is uniform in the instance sizes;
the committed `ConstInit` (`Holders = {1,2,3}`) and `NonceU = 0..3` fix a fast
default run.

## Negative controls (the model earns its keep)

Two controls, each on a `/tmp` copy of `Transport.tla`, both run against the
reachable state space (`--init=TrInit --next=TrNext --inv=INV_P8 --length=6`):

**(a) Replayed-ACK acceptance — drop the freshness conjunct.** Removing
`a.ackNonce = trAttemptNonce` (check (ii)) from `AckAccepts` yields **Error**,
state invariant 2 (`TrAckFreshness`) violated at State 4:

```
State0: nonce=0, ackOk=F, authorised={}
State1: nonce=1, ackOk=F, authorised={}              (Retry)
State2: nonce=1, ackOk=F, authorised={<<10,1001>>}   (RecipientSigns @ nonce 1)
State3: nonce=2, ackOk=F, authorised={<<10,1001>>}   (Retry)
State4: nonce=2, ackOk=T, authorised={<<10,1001>>}   (Ack accepts STALE ack)
        => trAckOk /\ ~(<<10, 1000+nonce>> \in authorised)   [TrAckFreshness]
```

This is exactly the pre-F17-fix replay: the recipient only ever signed nonce 1,
the attempt has advanced to nonce 2, yet without the freshness check the sender
accepts the captured ACK and would drop early.

**(b) Early-drop with no ACK — drop the retention guard.** Removing
`trAckOk = TRUE` from the `Drop` guard yields **Error**, state invariant 3
(`TrSenderRetainsUntilSafe`) violated at State 3:

```
State0: phase=published, ackOk=F, replicas={1},     hasCopy=T
State1: phase=published, ackOk=F, replicas={1,2},   hasCopy=T  (Replicate)
State2: phase=published, ackOk=F, replicas={1,2,3}, hasCopy=T  (Replicate)
State3: phase=dropped,   ackOk=F, replicas={1,2,3}, hasCopy=F  (Drop, no ACK)
        => ~hasCopy /\ (~ackOk \/ |replicas| < 3)   [TrSenderRetainsUntilSafe]
```

Both confirm the NoError verdict is meaningful: the model *can* exhibit both an
ACK replay and an unsafe early drop, and the two guards are what rule them out.

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 label **HIGH** with sub-finding **F17 (LOW)**; Apalache verdict
**verified** ⇒ **confirmed** at the transport state-machine level. The F17 LOW
is **resolved** by the spec's `ack_nonce` binding, which the model implements:
`TrAckFreshness` is an inductive invariant (no replayed ACK is ever accepted),
and negative control (a) shows the LOW would return if the binding were removed.
Full reconciliation across all properties is deferred to Phase 4.

**Oracle/baseline provenance.** The Pass-3 audit's P8 prose was written against
the pre-fix snapshot (ACK "not nonce-bound"); the baseline here (`b6972b8`)
carries the fix. The *claim* (confidentiality + unforgeable, freshness-bound
ACKs + retention-until-safe) is unchanged across the fix — only the freshness
enforcement was added — so the audit remains a valid oracle; this note records
the wording delta for any reader cross-referencing the audit text.

## Scope / what is deliberately NOT modelled

- **NIP-44 v2 encryption and NIP-59 gift-wrap byte-level (Sec. 4.2).** Their
  only logical content here is "who can read the plaintext", captured by the
  **A8–A11 oracle `CanDecrypt`** over the per-object key-holder set (ivk for the
  delivery payload, K_tx for the bundle). The relay/eavesdropper is absent from
  every holder set, so it decrypts nothing. The byte-format IND-CCA / gift-wrap
  unlinkability arguments are the axioms A10/A11 themselves, not re-derived.
- **The BIP-340 ACK signature** is the A7 EUF-CMA oracle (`SigValid` over
  `trAuthorised`); curve arithmetic is not modelled.
- **The content-addressed blob store** (`blob_id = H(ciphertext)`) is an opaque
  `Int` handle under the Foundations digest abstraction (A5).
- **The backoff/retry schedule** (30 s … 1 h) is liveness, abstracted to a
  non-deterministic `Retry` that just refreshes the nonce; the safety claims do
  not depend on timing.
- **Detection-scan addressing** (`detect_tag`, `epk`, Sec. 4.4) is out of scope;
  only addressing-by-IVPK matters to delivery here.
