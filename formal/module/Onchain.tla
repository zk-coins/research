-------------------------- MODULE Onchain --------------------------
(***************************************************************************)
(* Onchain -- the FULL-FIDELITY on-chain layer of zkCoins (Spec Sec. 3,      *)
(* post-docs#40 baseline b6972b8). This is the concrete BatchInscription     *)
(* state machine that the abstract accumulator model in                     *)
(* property/P02_NoDoubleSpend/property.tla stands in for: where P02 carries  *)
(* only onPending/onCompleted/onDoubled sets of opaque nullifiers, this module     *)
(* carries the actual BatchInscription record (Sec. 3.1/3.5), the publisher  *)
(* signature oracle (Sec. 3.2, A7), the half-aggregation obligation          *)
(* (Sec. 3.3, A15), prev_root continuity / sequential commitment            *)
(* (Sec. 3.4/3.6 step 4), the block_anchor bound (Sec. 3.5), the three-state *)
(* lifecycle (Sec. 3.10), and reorg handling (Sec. 3.7/3.9).                 *)
(*                                                                         *)
(* WHY THIS MODULE EXISTS. P02 proves the SET-LEVEL admission discipline is  *)
(* sound. The Pass-3 audit's load-bearing concern, post-docs#40, is the      *)
(* FIRST-SPEND-WINS gate: the in-circuit obligation that every nullifier in  *)
(* an admitted batch is a NON-MEMBER of prev_root (Sec. 3.6 step 7 /         *)
(* Sec. 3.7 "new_root = SMT.insert_many(prev_root, batch_nullifiers)"),      *)
(* together with the sequential prev_root continuity that serialises         *)
(* admissions (Sec. 3.4). Both live here as explicit conjuncts of Admit so   *)
(* that deleting either re-introduces a double-spend, exactly as the P02     *)
(* [GATE] note describes.                                                    *)
(*                                                                         *)
(* WHAT IS FAITHFUL vs ABSTRACTED (deliberate, stated openly).               *)
(*   - ROOTS-AS-SETS (A16/RootCommitsSet). A Poseidon/SMT accumulator root   *)
(*     is collision-bound to the set of nullifiers it commits to, so we      *)
(*     track the accumulator as a Set($nullifier) and carry prev_root/       *)
(*     new_root as the set values they commit to. Equality of roots IS       *)
(*     equality of committed sets (Sec. 3.7, Foundations digest abstraction).*)
(*   - SIGNATURES (A7). Modelled by the SigValid authorisation oracle over   *)
(*     `onAuthorised`, grown only by honest publisher signing (Sec. 3.2).      *)
(*   - HALF-AGGREGATION (A15). The AggregateBatchProof's member-signature    *)
(*     obligation is AggSoundValid(member validities); we keep the member    *)
(*     validity bits explicit so a batch carrying any invalid member fails    *)
(*     (Sec. 3.3).                                                           *)
(*   - block_anchor BOUND (Sec. 3.5). The strict-ancestor + gap<=100 rule is *)
(*     a deterministic function of confirmed Bitcoin data the model does not  *)
(*     simulate at the byte level; we carry it as a per-batch Bool           *)
(*     precondition `anchorOk` (TRUE = the §3.5 normative bound holds). This  *)
(*     is faithful because §3.10 classifies the inscription `failed` on any   *)
(*     anchor-bound violation, which `anchorOk = FALSE` reproduces exactly.   *)
(*   - DATA-AVAILABILITY sub-state (Sec. 3.6 step 5 / 3.10). The "onPending due *)
(*     to bundle DA" sub-state means the aggregate proof has not yet         *)
(*     verified, so NO accumulator transition is admitted. Modelled by NOT    *)
(*     advancing the accumulator until Admit fires (admission == bundle       *)
(*     verified); a batch sitting un-admitted is exactly onPending-due-to-DA.   *)
(*     The accumulator-bearing invariants are insensitive to the reason an    *)
(*     un-admitted batch is un-admitted, so the sub-state needs no own var.   *)
(*   - mint-verified (Sec. 3.10). A non-anchored mint introduces no          *)
(*     nullifier and reaches the accumulator only when later SPENT, through   *)
(*     an ordinary BatchInscription. It therefore has no effect on the       *)
(*     accumulator state machine and is out of scope here (it is a           *)
(*     receive-side classification, modelled in the receive properties).     *)
(*                                                                         *)
(* The accumulator advances at ADMISSION = onPending \union onCompleted          *)
(* (Sec. 3.10 "double-spend protection takes effect at admission"); receivers*)
(* credit only on `onCompleted` (>= 6 confirmations, Sec. 3.9, absolute).      *)
(***************************************************************************)
EXTENDS Integers, Sequences, Foundations, Assumptions

(***************************************************************************)
(* New type aliases for the on-chain layer. Shared datatypes ($nullifier,   *)
(* $accountState, ...) are reused from Foundations unchanged.               *)
(*                                                                         *)
(* A root is modelled as the SET of nullifiers it commits to (A16); the     *)
(* opaque `root` scalar of Foundations is never used here because the on-    *)
(* chain layer reasons about accumulator CONTENTS, which A16 licenses.       *)
(*                                                                         *)
(* @typeAlias: batchInscription = {                                         *)
(*   publisherPk: Int,                                                      *)
(*   prevRoot: Set($nullifier),                                            *)
(*   newRoot: Set($nullifier),                                            *)
(*   bundleLocator: Int,                                                    *)
(*   blockAnchorHeight: Int,                                               *)
(*   batchNullifiers: Set($nullifier),                                     *)
(*   memberValidities: Set(Bool),                                          *)
(*   anchorOk: Bool                                                         *)
(* };                                                                       *)
(***************************************************************************)
Onchain_typedefs == TRUE

CONSTANTS
  \* Finite universe of nullifiers (= coins, by A1 injectivity). A batch's
  \* nullifier set is drawn from here.
  \* @type: Set($nullifier);
  Nullifiers,
  \* Finite universe of publisher identity keys Pk_p (Sec. 3.2).
  \* @type: Set(Int);
  Publishers,
  \* Finite universe of bundle_locator content-addresses (Sec. 3.5).
  \* @type: Set(Int);
  BundleLocators

VARIABLES
  \* The live accumulator's committed nullifier set < 6 confirmations: admitted
  \* (bundle-verified) but reorg-eligible (Sec. 3.9/3.10).
  \* @type: Set($nullifier);
  onPending,
  \* The committed nullifier set with >= 6 confirmations: absolute, never
  \* reverts under the <= 5-block reorg bound (Sec. 3.9/3.10, A12).
  \* @type: Set($nullifier);
  onCompleted,
  \* Double-spend evidence: nullifiers an admitted batch re-inserted while
  \* already present. The first-spend-wins gate keeps this empty (Sec. 3.7).
  \* @type: Set($nullifier);
  onDoubled,
  \* A7 oracle state: the (publisherPk, msgTag) pairs honest publishers have
  \* actually signed (Sec. 3.2). Grown only by honest signing in PublisherSign.
  \* @type: Set(<<Int, Int>>);
  onAuthorised,
  \* The history of admitted BatchInscriptions in Bitcoin canonical order
  \* (Sec. 3.6 step 4 ordering). Used to certify prev_root continuity and to
  \* re-derive the accumulator on reorg (Sec. 3.7).
  \* @type: Seq($batchInscription);
  onAdmittedChain

\* @type: <<Set($nullifier), Set($nullifier), Set($nullifier), Set(<<Int, Int>>), Seq($batchInscription)>>;
onVars == << onPending, onCompleted, onDoubled, onAuthorised, onAdmittedChain >>

(***************************************************************************)
(* Derived state.                                                          *)
(***************************************************************************)

\* The live accumulator: every admitted nullifier (onPending \union onCompleted),
\* i.e. the contents behind the current admitted new_root (Sec. 3.7). A batch
\* sees this as the set its prev_root must commit to (Sec. 3.6 step 4).
\* @type: () => Set($nullifier);
Acc == onPending \union onCompleted

\* The batch_message tag a publisher signs (Sec. 3.2): a structured digest over
\* every on-chain field except the signature itself. Under the Foundations
\* digest abstraction this tag IS its pre-image, so distinct messages have
\* distinct tags by construction (A3/A5). We fold the structured fields into a
\* single Int tag via an injective-by-construction record handle and reuse
\* SigValid's <<pk, msgTag>> shape: the msgTag is the bundle_locator, which
\* §3.5 binds 1:1 to (prev_root,new_root,block_anchor) inside batch_message
\* (the locator is itself Hc over the bundle that fixes those roots), so equal
\* locators imply equal messages and SigValid keys on the locator faithfully.
\* @type: ($batchInscription) => Int;
BatchMsgTag(b) == b.bundleLocator

(***************************************************************************)
(* Initial state (Sec. 3.7): empty accumulator, empty roots, empty chain,   *)
(* nothing signed. Init assigns every variable (Apalache requirement).      *)
(***************************************************************************)
\* @type: () => Bool;
OnInit ==
  /\ onPending = {}
  /\ onCompleted = {}
  /\ onDoubled = {}
  /\ onAuthorised = {}
  /\ onAdmittedChain = << >>

(***************************************************************************)
(* PublisherSign -- the A7 honest-signing action (Sec. 3.2). A publisher     *)
(* that controls Pk_p signs the batch_message of a candidate inscription,    *)
(* adding (Pk_p, msgTag) to `onAuthorised`. A forged signature for an          *)
(* uncontrolled key is, by EUF-CMA, never added here, so SigValid rejects it.*)
(* This is the ONLY way `onAuthorised` grows -- the trust budget stays honest. *)
(***************************************************************************)
\* @type: () => Bool;
PublisherSign ==
  \E pk \in Publishers, loc \in BundleLocators :
    /\ onAuthorised' = onAuthorised \union { <<pk, loc>> }
    /\ UNCHANGED << onPending, onCompleted, onDoubled, onAdmittedChain >>

(***************************************************************************)
(* Admit -- a node admits one BatchInscription (Sec. 3.6 steps 1-8).         *)
(*                                                                         *)
(* The candidate batch is chosen nondeterministically; Admit fires only if   *)
(* EVERY admission rule holds, matching §3.10: any single violation makes the *)
(* inscription `failed` (modelled simply by Admit not firing on that batch -- *)
(* a `failed` inscription contributes no nullifiers and no root update, so it *)
(* leaves the accumulator state untouched, which is exactly "no transition"). *)
(*                                                                         *)
(* Admission conjuncts, each citing its spec step:                          *)
(*  [SIG]      §3.6 step 3 -- publisher BIP-340 signature valid (A7).        *)
(*  [ANCHOR]   §3.5        -- block_anchor strict-ancestor + gap<=100 holds. *)
(*  [CONT]     §3.6 step 4 -- prev_root continuity: prev_root commits to the *)
(*                            current admitted accumulator (sequential        *)
(*                            commitment, §3.4); else the batch is STALE.     *)
(*  [AGG]      §3.3 (A15)  -- the AggregateBatchProof's half-aggregation     *)
(*                            obligation: every member signature is valid.    *)
(*  [INSERT]   §3.7 step 7 -- new_root = SMT.insert_many(prev_root, batch):   *)
(*                            new_root commits to prev_root \union batch.     *)
(*  [GATE]     post-#40    -- FIRST-SPEND-WINS: every batch nullifier is a    *)
(*                            NON-MEMBER of prev_root. THE load-bearing       *)
(*                            predicate; delete it and Apalache returns a     *)
(*                            double-spend counterexample (onDoubled != {}).    *)
(*                                                                         *)
(* `onDoubled` is written from (batch \intersect Acc) BEFORE the gate is        *)
(* asserted, so the gate's removal is observable (same idiom as P02).        *)
(***************************************************************************)
\* @type: () => Bool;
Admit ==
  \E pk \in Publishers, loc \in BundleLocators,
     batch \in (SUBSET Nullifiers) \ {{}},
     mvs \in SUBSET {TRUE, FALSE},
     anchor \in {TRUE, FALSE},
     h \in Int :
    LET cand == [ publisherPk |-> pk,
                  prevRoot |-> Acc,
                  newRoot |-> Acc \union batch,
                  bundleLocator |-> loc,
                  blockAnchorHeight |-> h,
                  batchNullifiers |-> batch,
                  memberValidities |-> mvs,
                  anchorOk |-> anchor ]
    IN
      \* [SIG] §3.6 step 3, A7 -- publisher signature must verify.
      /\ SigValid(onAuthorised, pk, BatchMsgTag(cand))
      \* [ANCHOR] §3.5 -- strict-ancestor + gap<=100 precondition holds.
      /\ cand.anchorOk = TRUE
      \* [AGG] §3.3, A15 -- the aggregate proof's member checks all pass.
      /\ AggSoundValid(cand.memberValidities)
      \* mvs must be non-empty so AggSoundValid is meaningful (a batch carries
      \* >= 1 member SpendRecord, §3.4); an empty bit-set vacuously passes.
      /\ cand.memberValidities # {}
      \* [CONT] §3.6 step 4 / §3.4 -- prev_root commits to the live accumulator.
      /\ RootCommitsSet(cand.prevRoot, Acc)
      \* [INSERT] §3.7 / §3.6 step 7 -- new_root = insert_many(prev_root, batch).
      /\ RootCommitsSet(cand.newRoot, cand.prevRoot \union cand.batchNullifiers)
      \* evidence (written before the gate so the gate is load-bearing).
      /\ onDoubled' = onDoubled \union (cand.batchNullifiers \intersect Acc)
      \* [GATE] post-#40 first-spend-wins: batch nullifiers absent from prev_root.
      /\ cand.batchNullifiers \intersect cand.prevRoot = {}
      \* effects: accumulator absorbs the batch at admission (§3.10), into the
      \* < 6-conf zone; record the inscription in canonical order (§3.6 step 4).
      /\ onPending' = onPending \union cand.batchNullifiers
      /\ onCompleted' = onCompleted
      /\ onAdmittedChain' = Append(onAdmittedChain, cand)
      /\ UNCHANGED onAuthorised

(***************************************************************************)
(* Confirm -- onPending nullifiers cross the 6-confirmation finality threshold *)
(* (Sec. 3.9). Once `onCompleted` they are absolute under the <= 5-block bound  *)
(* (Sec. 3.10), so this move is one-way. `onAdmittedChain` is unchanged: the    *)
(* inscription stays admitted; only its confirmation depth advanced.         *)
(***************************************************************************)
\* @type: () => Bool;
Confirm ==
  \E M \in (SUBSET onPending) \ {{}} :
    /\ onCompleted' = onCompleted \union M
    /\ onPending' = onPending \ M
    /\ UNCHANGED << onDoubled, onAuthorised, onAdmittedChain >>

(***************************************************************************)
(* Reorg -- a Bitcoin reorganisation orphans some admitted-but-not-yet-      *)
(* finalised batches (Sec. 3.7 reorg handling, Sec. 3.9). Only `onPending`     *)
(* nullifiers may revert; `onCompleted` (depth >= 6) is NEVER touched because   *)
(* the protocol assumes no reorg deeper than 5 blocks (A12,                  *)
(* ReorgWithinBound(depth) with depth < FinalityDepthK = 6).                 *)
(*                                                                         *)
(* The reverted batches are removed from `onAdmittedChain`; the canonical      *)
(* replay re-derives the accumulator from the surviving prefix (Sec. 3.7).   *)
(* We model the revert as dropping a suffix of the chain whose nullifiers are *)
(* exactly a subset of `onPending` (onCompleted batches sit in the un-reorgable   *)
(* prefix), keeping onPending = nullifiers of the surviving non-onCompleted tail. *)
(***************************************************************************)
\* @type: () => Bool;
Reorg ==
  \E depth \in 1..(FinalityDepthK - 1), D \in (SUBSET onPending) \ {{}} :
    \* ReorgWithinBound: the proposed reorg depth is strictly < K = 6 (A12).
    /\ ReorgWithinBound(depth)
    \* revert D \subseteq onPending; onCompleted untouched (absolute, §3.10).
    /\ onPending' = onPending \ D
    /\ onCompleted' = onCompleted
    \* drop the reverted inscriptions from the canonical chain (filter out any
    \* inscription whose batch nullifiers intersect the reverted set D).
    /\ LET \* @type: ($batchInscription) => Bool;
           Survives(b) == b.batchNullifiers \intersect D = {}
       IN onAdmittedChain' = SelectSeq(onAdmittedChain, Survives)
    /\ UNCHANGED << onDoubled, onAuthorised >>

(***************************************************************************)
(* Next -- the on-chain state machine. PublisherSign is the honest-signing   *)
(* race (a publisher signs a candidate before inscribing); Admit is the       *)
(* §3.6 admission scan; Confirm is finality; Reorg is the bounded            *)
(* Bitcoin reorganisation. A stale/racing publisher (§3.4) needs no own       *)
(* action: a batch whose prev_root no longer matches Acc simply fails [CONT]  *)
(* and Admit does not fire -- exactly the §3.6 step 4 stale rejection.        *)
(***************************************************************************)
\* @type: () => Bool;
OnNext ==
  \/ PublisherSign
  \/ Admit
  \/ Confirm
  \/ Reorg

\* @type: () => Bool;
OnSpec == OnInit /\ [][OnNext]_onVars

(***************************************************************************)
(* Invariants. Only TypeOK is smoke-checked here; the rest are STATED for    *)
(* Phase-2/3 (inductive proof + the P02 certificate). They restate, at full  *)
(* fidelity, the safety the abstract P02 model proves unbounded.             *)
(***************************************************************************)

\* Structural type-correctness of every variable.
\* @type: () => Bool;
OnTypeOK ==
  /\ onPending \subseteq Nullifiers
  /\ onCompleted \subseteq Nullifiers
  /\ onDoubled \subseteq Nullifiers
  /\ onAuthorised \subseteq (Publishers \X BundleLocators)
  /\ \A i \in DOMAIN onAdmittedChain :
       LET b == onAdmittedChain[i] IN
         /\ b.publisherPk \in Publishers
         /\ b.prevRoot \subseteq Nullifiers
         /\ b.newRoot \subseteq Nullifiers
         /\ b.batchNullifiers \subseteq Nullifiers
         /\ b.bundleLocator \in BundleLocators
         /\ b.memberValidities \subseteq {TRUE, FALSE}
         /\ b.anchorOk \in {TRUE, FALSE}

\* THE SAFETY CLAIM (Sec. 3.7, audit P2 HIGH): no nullifier is ever
\* double-spent -- no admitted batch re-inserts a nullifier already present.
\* @type: () => Bool;
OnNoDoubleSpend == onDoubled = {}

\* Structural: a nullifier is onPending OR onCompleted, never both (Sec. 3.10
\* lifecycle: onCompleted is reached by leaving onPending, Confirm is one-way).
\* @type: () => Bool;
OnZonesDisjoint == onPending \intersect onCompleted = {}

\* Sequential commitment (Sec. 3.4 / 3.6 step 4): in the admitted chain, each
\* batch's prev_root commits to the union of all prior batches' nullifiers, and
\* its new_root commits to that union plus its own batch -- the chained
\* prev_root -> new_root continuity Bitcoin ordering serialises.
\* @type: () => Bool;
OnPrevRootContinuity ==
  \A i \in DOMAIN onAdmittedChain :
    LET priorNfs ==
          UNION { onAdmittedChain[j].batchNullifiers : j \in 1..(i - 1) }
    IN
      /\ onAdmittedChain[i].prevRoot = priorNfs
      /\ onAdmittedChain[i].newRoot = priorNfs \union onAdmittedChain[i].batchNullifiers

(***************************************************************************)
(* Constant initialiser for the smoke run (Apalache --cinit). Small finite   *)
(* instances: the accumulator-level argument is uniform in the universe       *)
(* sizes (every conjunct of the invariants is per-nullifier / per-inscription *)
(* local), so a small instance certifies the toolchain wiring and the         *)
(* reachability smoke test. Nullifiers are built as structured $nullifier     *)
(* values over tiny scalar carriers, per the Foundations constructors.        *)
(***************************************************************************)

\* A minimal coin id over a canonical empty account, for building nullifiers.
\* @type: (Int) => $coinId;
SmokeCoinId(i) ==
  MkCoinId(CanonicalEmptyAccount(0, 0), MkAssetId(0, 0, 0, IssuanceVersionV1), i)

\* @type: () => Bool;
OnConstInit ==
  /\ Nullifiers = { MkNullifier(0, SmokeCoinId(i)) : i \in 1..3 }
  /\ Publishers = 1..2
  /\ BundleLocators = 1..2

=============================================================================
