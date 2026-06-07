-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P09 -- Recovery Completeness (the LIVENESS-flavoured property).          *)
(*                                                                         *)
(* Phase-2 deliverable of the zkCoins 100% Logical Verification Initiative. *)
(* P9 has two halves, and the Pass-3 audit grades them differently:        *)
(*                                                                         *)
(*   CORRECTNESS (Pass-3: HIGH).  The emergency recovery path (spec Sec.    *)
(*     4.5 steps 1-5) never FALSE-ACCEPTS and never FALSE-REJECTS:          *)
(*       - false-accept impossible: every returned candidate bundle is      *)
(*         independently verified against Bitcoin (Sec. 4.5 step 4); a      *)
(*         node "can only WITHHOLD, never forge"; a forged candidate fails  *)
(*         its recursive per-account proof / AggregateBatchProof check and  *)
(*         MUST be discarded.                                               *)
(*       - false-reject impossible AS SAFETY: a correctly-delivered bundle  *)
(*         verifies under Sec. 4.5; the ONLY failure mode is UNAVAILABILITY *)
(*         (no replica returns it) -- which is liveness, not safety.        *)
(*     This half is a SAFETY property and is the UNBOUNDED certificate      *)
(*     below (3-check inductive invariant): INV_P9_safety.                  *)
(*                                                                         *)
(*   LIVENESS (Pass-3: MEDIUM).  Availability of a past bundle depends on   *)
(*     k-replication on independent operators AND at least one reachable    *)
(*     honest replica being queried (Sec. 4.6). The spec is EXPLICIT that   *)
(*     this is "availability, not safety": if every replica is lost, or all *)
(*     queried nodes collude to withhold, the owner is stuck. We treat the  *)
(*     genuine temporal statement honestly -- see the LIVENESS section near  *)
(*     the bottom of this module and notes.md for the scope decision.       *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P9: HIGH correctness / MEDIUM liveness): *)
(*   INV_P9_safety, the SAFETY half, is the conjunction of:                 *)
(*     (i)   NO FALSE-ACCEPT -- the recovered set contains no forged or     *)
(*           otherwise unverifiable bundle. Every member passed the Sec.    *)
(*           4.5 step-4 gate (recursive proof verifies against Bitcoin via  *)
(*           the A1 KnowledgeSound oracle, AND it is one the wallet's own   *)
(*           seed-derived keys can read).                                   *)
(*     (ii)  OWN-KEY DISCIPLINE -- every recovered bundle decrypts only with *)
(*           the wallet's own seed-derived K_tx keys (A8-A11 CanDecrypt);   *)
(*           recovery never credits a coin addressed to someone else.       *)
(*     (iii) MONOTONE/SOUND ACCUMULATOR -- the recovered set never contains  *)
(*           a candidate the gate rejected; rejection is permanent for that *)
(*           candidate (a discarded forgery is never silently re-admitted). *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (baseline docs@b6972b8, post-docs#40):     *)
(*   - Sec. 4.5 step 1 -- re-derive keys from seed (ivk/dk/ovk/op/nk/spend) *)
(*     => the wallet's own decryption capability is exactly its key-holder  *)
(*     membership (A8-A11). Modelled by WalletKtxHolders below.             *)
(*   - Sec. 4.5 step 3 -- pull candidate bundles from the untrusted blob    *)
(*     cache: cooperating nodes return matching bundles; "the network here  *)
(*     is an untrusted blob cache". Modelled by Recover querying replicas;  *)
(*     an adversarial node MAY inject a forged candidate.                   *)
(*   - Sec. 4.5 step 4 -- "For every returned bundle, the node MUST         *)
(*     independently verify the recursive per-account proof ... A bundle    *)
(*     failing any check MUST be discarded. A node can only WITHHOLD, never *)
(*     forge." Modelled by the AcceptsBundle gate.                          *)
(*   - Sec. 4.6 -- replication factor k (default 3, MUST NOT be < 2) on     *)
(*     INDEPENDENT operators; the normative safety invariant "Custody       *)
(*     safety MUST NOT depend on availability. ... Availability is a        *)
(*     liveness property, never a safety property."                         *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly; inherited from         *)
(* module/Transport.tla and module/Assumptions.tla):                        *)
(*   - The recursive per-account proof + output_coins_root inclusion +      *)
(*     completed-anchoring + nullifier-non-membership chain of Sec. 4.5     *)
(*     step 4 is the A1 KnowledgeSound oracle: a candidate's recorded       *)
(*     bVerifies bit is its "proof accepts" outcome, and KnowledgeSound     *)
(*     lifts proofAccepts => statementHolds. A forged bundle has            *)
(*     bVerifies = FALSE (it cannot make the Bitcoin-anchored statement     *)
(*     true), so the gate discards it.                                      *)
(*   - "decrypts with the wallet's own keys" is the A8-A11 CanDecrypt       *)
(*     oracle over the per-bundle K_tx holder set. A real own-bundle's      *)
(*     K_tx holder set includes the wallet's seed-derived id; a forged      *)
(*     candidate's does not (the adversary cannot encrypt under the         *)
(*     wallet's K_tx -- the confidentiality direction of A8-A11).           *)
(*   - Replica reachability / collusion is non-deterministic: any subset of *)
(*     the bundle's holder set may be reachable on a given Recover, and an   *)
(*     adversarial node may add a forged candidate to the returned set.     *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (recorded in notes.md):                    *)
(*   - REACHABILITY PROBE (vacuity): recovery actually recovers something   *)
(*     -- the negation `recovered = {}` is violated, so the gate is not     *)
(*     vacuously empty.                                                     *)
(*   - NEGATIVE CONTROL: drop the verify gate (bVerifies conjunct) from     *)
(*     AcceptsBundle -> a forged candidate is admitted -> false-accept is   *)
(*     reachable -> INV_P9_safety fails.                                    *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Transport

(***************************************************************************)
(* RECOVERY-LAYER CONSTANTS. The bundle universe and the wallet identity.   *)
(***************************************************************************)
CONSTANT
  \* The wallet's own seed-derived recovery id (Sec. 4.5 step 1). It is the
  \* party in a bundle's K_tx holder set iff the wallet can decrypt that
  \* bundle. Distinct from Eve / the recipient op key.
  \* @type: Int;
  WalletId,
  \* The universe of candidate bundle ids the recovery procedure may meet:
  \* genuine own-bundles (replicated per Sec. 4.6) and adversary forgeries
  \* (injected by a node at Sec. 4.5 step 3). Finite.
  \* @type: Set(Int);
  Bundles,
  \* The genuine, wallet-owned bundles (a subset of Bundles) that were really
  \* delivered to / received by this account before the loss event. Their
  \* recursive proofs verify against Bitcoin AND they decrypt with WalletId.
  \* @type: Set(Int);
  RealBundles,
  \* ADDRESSED FORGERIES (a subset of Bundles disjoint from RealBundles): the
  \* genuine Sec. 4.5 step-4 threat. A node returns a candidate that LOOKS
  \* addressed to the wallet -- it IS in the wallet's K_tx holder set, so the
  \* wallet CAN decrypt it -- but its recursive per-account proof against
  \* Bitcoin does NOT verify (a node can only withhold, never forge). The
  \* decrypt check alone would let it through; only the verify gate discards
  \* it. This class is what makes the verify gate load-bearing (negative
  \* control below) -- without an addressed forgery, the own-key check would
  \* mask the verify check.
  \* @type: Set(Int);
  AddressedForgeries

(***************************************************************************)
(* Faithfulness ASSUMEs. RealBundles is a genuine subset of the universe,   *)
(* the universe is non-empty, and the two adversary-controlled classes are  *)
(* disjoint from the genuine ones (a real bundle is never a forgery).       *)
(***************************************************************************)
ASSUME RealBundlesSubset == RealBundles \subseteq Bundles
ASSUME ForgeriesSubset   == AddressedForgeries \subseteq Bundles
ASSUME ForgeriesDisjoint == AddressedForgeries \cap RealBundles = {}
ASSUME BundlesNonEmpty   == Bundles # {}

(***************************************************************************)
(* PER-BUNDLE ORACLES (constant predicates over the instance).             *)
(*                                                                         *)
(* bVerifies(b): the Sec. 4.5 step-4 outcome -- does b's recursive          *)
(*   per-account proof verify against Bitcoin? Exactly the genuine          *)
(*   own-bundles do (a node can only withhold, never forge). This is the    *)
(*   "proofAccepts" fed to the A1 KnowledgeSound oracle. An addressed        *)
(*   forgery does NOT verify (bVerifies = FALSE) even though the wallet can  *)
(*   decrypt it.                                                            *)
(*                                                                         *)
(* bStmtHolds(b): the statement the proof attests actually holds -- b is a  *)
(*   real bundle the seed-controlled account did receive. By A1             *)
(*   KnowledgeSound, bVerifies(b) => bStmtHolds(b); here they coincide      *)
(*   (RealBundles), which is the faithful instance.                         *)
(*                                                                         *)
(* bKtxHolders(b): the K_tx holder set of b. A real own-bundle AND an        *)
(*   addressed forgery both include WalletId (both look addressed to the     *)
(*   wallet, Sec. 4.5 step 1); an unaddressed forgery does not. So the       *)
(*   decrypt check cannot, by itself, distinguish a real bundle from an      *)
(*   addressed forgery -- only the verify gate can.                         *)
(***************************************************************************)
\* @type: (Int) => Bool;
bVerifies(b) == b \in RealBundles
\* @type: (Int) => Bool;
bStmtHolds(b) == b \in RealBundles
\* @type: (Int) => Set(Int);
bKtxHolders(b) ==
  IF b \in (RealBundles \union AddressedForgeries) THEN { WalletId } ELSE {}

(***************************************************************************)
(* THE SEC. 4.5 STEP-4 GATE. The node accepts a returned candidate b iff    *)
(*   (i)  its recursive proof verifies against Bitcoin (A1 KnowledgeSound   *)
(*        lifts this to: the attested statement holds), AND                 *)
(*   (ii) it decrypts with the wallet's OWN seed-derived K_tx keys          *)
(*        (A8-A11 CanDecrypt over bKtxHolders(b)).                          *)
(* A candidate failing either check MUST be discarded (Sec. 4.5 step 4).    *)
(***************************************************************************)
\* @type: (Int) => Bool;
AcceptsBundle(b) ==
  /\ KnowledgeSound(bVerifies(b), bStmtHolds(b))   \* A1: proof verifies => statement holds
  /\ bVerifies(b)                                  \* (i)  Sec. 4.5 step-4 verify gate
  /\ CanDecrypt(bKtxHolders(b), WalletId)          \* (ii) own-key discipline (A8-A11)

(***************************************************************************)
(* RECOVERY STATE (layered on top of the Transport state).                 *)
(*   recPhase   : "recovering" while pulling, "done" once finished.         *)
(*   recovered  : the accepted-bundle accumulator built by Sec. 4.5 step 4. *)
(***************************************************************************)
VARIABLES
  \* @type: Str;
  recPhase,
  \* @type: Set(Int);
  recovered

\* @type: <<Str, Set(Int)>>;
recVars == << recPhase, recovered >>

(***************************************************************************)
(* The full system = Transport state + recovery state. Init starts a        *)
(* recovering wallet (post seed re-derivation, Sec. 4.5 step 1) with an      *)
(* empty accumulator, atop the Transport initial state.                     *)
(***************************************************************************)
\* @type: () => Bool;
Init ==
  /\ TrInit
  /\ recPhase = "recovering"
  /\ recovered = {}

(***************************************************************************)
(* QueryReturns: the set of candidate bundle ids an adversarial network     *)
(* MAY return on a pull (Sec. 4.5 step 3) -- ANY subset of the universe:    *)
(* it may withhold real bundles (return a subset of RealBundles) and/or     *)
(* inject forgeries (any non-real ids). The gate decides what is admitted.  *)
(* This is the untrusted-blob-cache adversary at full strength.             *)
(***************************************************************************)

(***************************************************************************)
(* Recover (Sec. 4.5 steps 3-4). Pull a non-deterministic candidate set Q   *)
(* from the untrusted network, run the step-4 gate over it, and add ONLY    *)
(* the accepted candidates to the accumulator. Forged / non-own candidates  *)
(* are discarded by AcceptsBundle. Modelled to add at least the accepted    *)
(* members of one queried subset per step (more pulls = more steps).        *)
(***************************************************************************)
\* @type: () => Bool;
Recover ==
  /\ recPhase = "recovering"
  /\ \E Q \in SUBSET Bundles :
       recovered' = recovered \union { b \in Q : AcceptsBundle(b) }
  /\ UNCHANGED << recPhase >>
  /\ UNCHANGED trVars

(***************************************************************************)
(* Finish: the wallet stops the emergency pull (Sec. 4.5 step 5 rebuild      *)
(* begins). The accumulator is frozen; no further candidate is admitted.    *)
(***************************************************************************)
\* @type: () => Bool;
Finish ==
  /\ recPhase = "recovering"
  /\ recPhase' = "done"
  /\ UNCHANGED << recovered >>
  /\ UNCHANGED trVars

(***************************************************************************)
(* Next. The recovery actions interleave with the underlying Transport       *)
(* actions (the bundle-delivery layer keeps running during recovery).        *)
(***************************************************************************)
\* @type: () => Bool;
Next ==
  \/ Recover
  \/ Finish
  \/ (TrNext /\ UNCHANGED recVars)

Spec == Init /\ [][Next]_<<trVars, recVars>>

(***************************************************************************)
(* THE SAFETY PROPERTY (the unbounded certificate). Pass-3 P9 CORRECTNESS    *)
(* half, HIGH. Three conjuncts:                                            *)
(*   (i)   NO FALSE-ACCEPT: every recovered bundle passed the step-4 gate.   *)
(*   (ii)  OWN-KEY DISCIPLINE: every recovered bundle decrypts with WalletId.*)
(*   (iii) SOUND ACCUMULATOR: recovered contains only genuine own-bundles    *)
(*         (RealBundles) -- equivalently, no forged/unverifiable candidate.  *)
(* (iii) implies (i) and (ii) given the oracle definitions, but we state all *)
(* three explicitly to mirror the audit's attack-class enumeration.         *)
(***************************************************************************)
\* @type: () => Bool;
INV_P9_safety ==
  /\ \A b \in recovered : AcceptsBundle(b)                   \* (i)  no false-accept
  /\ \A b \in recovered : CanDecrypt(bKtxHolders(b), WalletId) \* (ii) own-key discipline
  /\ recovered \subseteq RealBundles                          \* (iii) sound accumulator

(***************************************************************************)
(* ENABLEDNESS SURROGATE for the LIVENESS half (honestly weaker than full    *)
(* temporal liveness; see the LIVENESS section + notes.md). For any genuine  *)
(* own-bundle b that is held by >= 1 queried honest replica, the Recover     *)
(* action is ENABLED to bring it in: there exists a query set whose gate     *)
(* output contains b. This is a SAFETY (state) predicate -- "recovery is     *)
(* always able to make progress on a held real bundle" -- NOT a proof that   *)
(* it eventually does (that needs fairness; see ConditionalLiveness).        *)
(***************************************************************************)
\* @type: () => Bool;
RecoverEnabledForHeld ==
  (recPhase = "recovering") =>
    \A b \in RealBundles :
      \E Q \in SUBSET Bundles :
        b \in { c \in Q : AcceptsBundle(c) }

(***************************************************************************)
(* INDUCTIVE INVARIANT. INV_P9_safety conjoined with the finite structural   *)
(* facts (TrTypeOK from Transport + recovery-layer typing). The recovery     *)
(* conjuncts are inductive on their own: Recover only ever unions in         *)
(* gate-accepted candidates (which are exactly RealBundles by the oracle      *)
(* definitions), and Finish/TrNext leave `recovered` unchanged; so           *)
(* recovered \subseteq RealBundles is preserved, and (i)/(ii) follow because  *)
(* every member of RealBundles satisfies AcceptsBundle and CanDecrypt.       *)
(***************************************************************************)
\* @type: () => Bool;
RecTypeOK ==
  /\ recPhase \in { "recovering", "done" }
  /\ recovered \subseteq Bundles

\* @type: () => Bool;
IndInv ==
  /\ TrTypeOK
  /\ RecTypeOK
  /\ INV_P9_safety

(***************************************************************************)
(* Assignment-form restatement of IndInv, used as the --init predicate of    *)
(* the inductive-step check (Apalache requires every variable ASSIGNED in an *)
(* init predicate, not merely constrained). Each variable is bound by an     *)
(* `\in` over its finite type domain, then IndInv is asserted as a state      *)
(* constraint. Logically equivalent to IndInv. The Transport variables reuse  *)
(* P08's assignment form (the only delivery event the machine publishes has   *)
(* the fixed opaque handles; trAuthorised ranges over the recipient-op pairs).*)
(***************************************************************************)
\* @type: () => Set(Int);
NonceU == 0 .. 3

\* @type: () => Bool;
IndInvInit ==
  /\ trPhase \in { "published", "dropped" }
  /\ \E n \in NonceU :
       trDelivery = MkDeliveryEvent(DetectTag, Epk, BlobId, BlobLocators, n)
  /\ trAttemptNonce \in NonceU
  /\ trAckOk \in BOOLEAN
  /\ trReplicas \in SUBSET Holders
  /\ trSenderHasCopy \in BOOLEAN
  /\ trAuthorised \in SUBSET ({ RecipientOpPk } \X { AckMsgTag(m) : m \in NonceU })
  /\ recPhase \in { "recovering", "done" }
  /\ recovered \in SUBSET Bundles
  /\ IndInv

(***************************************************************************)
(* LIVENESS half -- the genuine conditional-liveness temporal property,      *)
(* attempted honestly with Apalache's --temporal support (see verify.sh      *)
(* check [L] and notes.md for the outcome and the scope decision).           *)
(*                                                                         *)
(* ConditionalLiveness: under weak fairness of Recover, if the wallet is     *)
(* recovering and a genuine own-bundle is reachable (held by >= 1 queried     *)
(* honest replica -- modelled by the gate being able to admit it), then it   *)
(* is EVENTUALLY recovered. This is exactly the audit's MEDIUM-liveness       *)
(* statement: availability-conditional on a reachable honest replica.        *)
(*                                                                         *)
(* It is deliberately CONDITIONAL: it says nothing when every replica is     *)
(* lost or all queried nodes collude (the audit's "if all collude, the user  *)
(* is stuck") -- those executions simply never satisfy the fairness premise. *)
(***************************************************************************)
\* @type: () => Bool;
EventuallyRecoveredAll ==
  <>[]( \A b \in RealBundles : b \in recovered )

\* Weak fairness on Recover: if Recover stays enabled it is eventually taken.
\* @type: () => Bool;
ConditionalLiveness ==
  WF_<<trVars, recVars>>(Recover) => EventuallyRecoveredAll

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Reuses the Transport smoke       *)
(* instance and pins the recovery universe: WalletId distinct from Eve and   *)
(* the recipient op key; two genuine own-bundles {1,2}; one ADDRESSED        *)
(* forgery {8} (decryptable by the wallet but its proof fails -- the step-4  *)
(* threat); one UNADDRESSED forgery {9} (the wallet cannot even decrypt it). *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit ==
  /\ TrConstInit
  /\ WalletId = 30
  /\ Bundles = { 1, 2, 8, 9 }
  /\ RealBundles = { 1, 2 }
  /\ AddressedForgeries = { 8 }

=============================================================================
