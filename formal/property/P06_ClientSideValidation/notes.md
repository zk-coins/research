# P06 -- Client-Side Validation (no third-party trust)

Phase-2 deliverable of the zkCoins 100% Logical Verification Initiative. This is
a **composition** property: the receiver-side decision rule of Spec §2.3.3
(receive steps 2-6) placed on top of the full on-chain machine
`module/Onchain.tla`, and proven **UNBOUNDED** with Apalache via an inductive
invariant over the composed machine.

## Toolchain

- Apalache **0.58.0** (SMT backend Z3 **4.14.1.0**), `apalache-mc` on PATH.
- Host: Apple Silicon (arm64), macOS (Darwin 25.5.0).
- Date: 2026-06-07.
- Spec baseline: `zk-coins/docs@ed7fdece` (spec-v1.1 = `b6972b8` + `docs#46`/`#47`/`#48`). `docs#46` is the deployment-topology PR (5 containers, optional external bitcoind/relay as a documented A13 trust trade-off); it is verification-neutral and changes no model — P06's at-least-one-honest-node receive gate is unaffected.

## Spec sections grounded

- **§2.3.3 Receive** (steps 1-6): the trustless-receive decision rule. The
  receiver "credits a coin only after independent verification" and "MUST NOT
  credit a coin on the sender's or any third party's assertion". The two
  load-bearing trustless checks are step 2 (recursive re-verification) and step 5
  (global nullifier non-membership against the on-chain-anchored accumulator);
  step 4 ties the credit to a `completed` BatchInscription.
- **§3.10 Transaction states**: receivers SHALL act only on `completed`
  (admitted under §3.5+§3.6 AND >= 6 confirmations); a `pending` or `failed`
  inscription MUST be treated as not anchored. `completed` is absolute under the
  <= 5-block reorg bound (A12).
- **§3.7 / §3.9**: the live nullifier accumulator at `NAV(tip)`, finality at 6
  confirmations.

## Pass-3 ground truth (audit/2026-06-06.03.md, "### P6 · Client-Side Validation")

> **Statement.** A receiver crediting a coin depends only on (a) the Bitcoin
> chain it itself reads, (b) the bundle it received, (c) its own derivable keys.
> No node, courier, sender, or third party can cause an honest receiver --
> running §2.3.3 correctly -- to credit a coin that fails any of §2.3.3 steps
> 2-6.
>
> **Game.** A wins if it can cause an honest receiver -- running §2.3.3 correctly
> -- to credit a coin that is not produced by a valid transition admitted on
> Bitcoin.
>
> Attack-class enumeration: subverting step 2 requires breaking A1; step 3
> requires breaking A3; step 4 requires bypassing admission (rejected by P1) or
> persuading the receiver that >= 6 confirmations exist when they don't (subverts
> A13 -- the receiver's own Bitcoin view); step 5 requires breaking A3 or
> persuading the receiver's chain view (A13); step 6 is a local check; a
> compromised delivering node can withhold (liveness) but cannot forge; a
> compromised relay set is liveness, not safety.
>
> **Verdict.** Sound under A1, A3, A12, A13. **Confidence: HIGH** for the
> protocol property; the spec correctly identifies that operator-network-level
> eclipse is an inherited Bitcoin assumption (A13) the spec cannot improve over.

## Receiver-layer design

The shared modules deliberately have **no** Receive action -- receive-side credit
is a client decision (§2.3.3), not an on-chain transition. `module/Onchain.tla`
says so explicitly ("it is a receive-side classification, modelled in the receive
properties"). P06 is that property.

- `property.tla` **EXTENDS Onchain**, so the receiver reads the REAL
  `onPending` / `onCompleted` / `Acc` the on-chain machine maintains. This is the
  modelling of A13: there is one true chain view, and the receiver reads it.
- New variable `credited`: a set of **ghost** records
  `{ cnf, anchorNfs, proofAttests, anchorCompleted, nfWasNonMember }`. The three
  bits record what was **true at credit time** -- this is what makes INV_P6 a
  real claim about the gate rather than a tautology over the present state.
- New variable `offered`: the adversary's offer pool of arbitrary candidate
  bundles (`{ ocnf, oAnchorNfs, oProofAccepts }` -- any nf, any claimed creating
  batch, any claimed proof bit). None of it is trusted.
- `AdversaryOffer` (UNCHECKED): a malicious node/courier/sender offers an
  arbitrary forged / unanchored / already-spent candidate into `offered`. It
  never credits and never touches the chain.
- `Receive` (the §2.3.3 gate): takes a candidate from `offered` and credits it
  ONLY IF all three checks pass against the receiver's OWN chain view:
  - **step 2** `Step2_ProofVerifies(oProofAccepts)` -- proof accepts =>
    statement holds, via the A1 `KnowledgeSound` oracle (`Assumptions.tla`). No
    party can forge acceptance of a false statement.
  - **step 4** `Step4_AnchorCompleted(oAnchorNfs)` -- `anchorNfs # {} /\
    anchorNfs \subseteq onCompleted`: the coin's creating batch is admitted AND
    >= 6 conf (§3.10 `completed`). A batch only in `onPending` fails.
  - **step 5** `Step5_NfNonMember(ocnf)` -- `cnf \notin Acc` (= `onPending \cup
    onCompleted`): the coin's own nullifier is unspent at the live tip (§3.7).
  - steps 3 and 6 are local in-receiver self-checks (Pass-3: "local checks");
    step 3 is folded into the step-2 statement (the proof attests the coin sits
    under `output_coins_root`) and step 6 checks the receiver's own address, so
    neither admits third-party influence.

`INV_P6 == CreditedChecksHeld /\ CreditedAnchored`:
- `CreditedChecksHeld` -- every credited entry's three bits are TRUE;
- `CreditedAnchored` -- every credited entry's `anchorNfs` is a non-empty subset
  of `onCompleted`. This is the load-bearing anti-vacuity conjunct, tying the
  ghost record to the receiver's real chain view: a credit cannot exist for a
  coin whose creating batch never reached `completed`.

## Unbounded proof and the inductive argument

The unbounded result is `[P2]+[P3]+[P4]`:

| check | statement | length |
|---|---|---|
| [P2] base | `P6Init => IndInv_P6` | 0 |
| [P3] step | `IndInv_P6 /\ P6Next => IndInv_P6'` | 1 |
| [P4] impl | `IndInv_P6 => INV_P6` | 0 |

`P6Next == OnNext \/ Receive \/ AdversaryOffer`.

`IndInv_P6` strengthens `INV_P6` with structural type facts (receiver records and
Onchain set variables) plus the disjoint-zones fact and `onDoubled = {}`
inherited from the on-chain machine. It does **not** reference the
`onAdmittedChain` sequence; the step init `IndInvInit` assigns the chain an
arbitrary bounded value via `apalache.Gen` (capacity <= 4) -- the **Seq
projection** argument of P02. The receiver gate reads `onCompleted` / `Acc` (the
set projection), never the chain history, so the Gen capacity bounds only the
bookkeeping witness, never the safety conclusion.

**The load-bearing argument is monotonicity of `onCompleted`.** The only INV_P6
conjunct an `OnNext` step could break is `CreditedAnchored` (it reads
`onCompleted`), because `OnNext` leaves `credited` unchanged. But `onCompleted`
only **grows**: `Confirm` sets `onCompleted' = onCompleted \cup M`;
`Admit` / `PublisherSign` leave it; `Reorg` leaves `onCompleted` **untouched**
(§3.10 / A12 -- `completed` is absolute, never reverts under the <= 5-block
bound). A subset of `onCompleted` stays a subset of any superset, so
`e.anchorNfs \subseteq onCompleted` is preserved. `Receive` only adds an entry
whose bits are the gate results (all TRUE) and whose `anchorNfs` is a non-empty
subset of `onCompleted` at that instant; `AdversaryOffer` leaves `credited` and
the chain unchanged. Hence `IndInv_P6` is inductive under the full `P6Next`.

No honest failures were encountered; no inductive-invariant strengthening beyond
the type facts + disjoint-zones was needed. The 3-honest-failures stop rule was
not triggered.

## Vacuity guard -- credits actually happen ([P1])

`CreditsNeverHappen == credited = {}` is checked expecting a **counterexample**.
Apalache returns Error (exit 12) at length 6 (NoError at length <= 5 -- a credit
needs PublisherSign, Admit, Confirm, AdversaryOffer, Receive = 5 steps after
init). The 6-state witness:

```
State0 P6Init           empty
State1 PublisherSign    publisher authorises a batch_message
State2 Admit  {nf}      nf enters onPending (admitted, < 6 conf)
State3 Confirm {nf}     nf crosses 6-conf finality -> onCompleted
State4 AdversaryOffer   candidate {ocnf=nf, oAnchorNfs={nf}, oProofAccepts=TRUE}
State5 Receive          all three checks pass -> credited gains one entry
```

So INV_P6 is not vacuously true on an empty `credited`, and the gate is
satisfiable.

## Negative controls -- each gate check is load-bearing

Each control deletes ONE conjunct from the `Receive` gate in a scratch copy
(named `property.tla` so SANY's module-name-matches-filename rule is satisfied),
then re-checks `INV_P6` at length 6. Both yield a counterexample (Error, exit 12).

- **NC-A -- drop the anchor-completed check** (`/\ completed`). Counterexample:
  a credited entry with `anchorCompleted |-> FALSE` while `onCompleted = {}` and
  `onPending = {}` -- a coin whose creating batch was never admitted (a
  pending/unanchored coin) is credited. Skolem witness:
  `\E e \in credited: ~(e.anchorCompleted = TRUE)`.
- **NC-B -- drop the proof-verifies check** (`/\ attests`). Counterexample:
  a credited entry with `proofAttests |-> FALSE` -- a coin whose recursive proof
  does not attest its statement is credited. Skolem witness:
  `\E e \in credited: ~(e.proofAttests = TRUE)`.

Both scratch copies were discarded; the committed `property.tla` is unchanged.
(The step-5 non-membership check is exercised structurally by `Step5_NfNonMember`
and by INV_P6's reliance on the live `Acc`; the two mandated controls -- anchor
and proof -- are the ones recorded here.)

## Cross-check vs Pass-3 (HIGH)

Pass-3 rates P6 **HIGH** for the protocol property, sound under A1, A3, A12, A13.
The Apalache model composes exactly those:
- **A1** -- `KnowledgeSound` in step 2 (proof acceptance entails its statement).
- **A3** -- structural in `Foundations.tla` (every nullifier/identifier is its
  structured pre-image; the receiver's `cnf` and `anchorNfs` are honest digests).
- **A12** -- `onCompleted` is reorg-stable in `Onchain.tla` (`Reorg` never
  touches it); this is the monotonicity the inductive proof leans on.
- **A13** -- the receiver reads the on-chain machine's single true view
  (`onCompleted` / `Acc`); modelled as an assumption, not re-proven.
The model's verdict matches Pass-3: under those four axioms, no third party can
make an honest receiver credit an unbacked coin.

## Scope (honest)

- **A13 eclipse is an assumption, not a theorem.** The whole property reads the
  on-chain machine's chain view as the receiver's own true view. An attacker who
  could rewrite that view (operator-network-level eclipse) is the inherited
  Bitcoin assumption Pass-3 records the spec "cannot improve over". Out of frame.
- **Bundle data-availability** (transport withhold / replication factor k=3,
  §4.6) is a liveness concern (P08), not safety. Out of frame.
- **mint-verified** (non-anchored mints, §3.10) substitutes direct InitialProof
  re-verification for the anchor check; this property models the anchored receive
  (steps 2/4/5). The mint path reduces to step 2 alone. Out of frame.
- `module/Onchain.tla` was **not** modified; the receiver layer lives entirely in
  `property.tla`.

## Reproduce

```
./verify.sh
```

Stages `Foundations.tla` + `Assumptions.tla` + `Onchain.tla` alongside
`property.tla` in a scratch dir (Apalache resolves EXTENDS from the spec's own
directory), runs `[P0t]`/`[P0]`/`[P1]`/`[P2]`/`[P3]`/`[P4]`, and removes
`_apalache-out`. Exit status = number of unexpected outcomes (0 on success).
```
```
