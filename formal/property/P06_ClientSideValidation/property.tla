-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P06 -- Client-Side Validation (no third-party trust).                    *)
(*                                                                         *)
(* Phase-2 deliverable of the zkCoins 100% Logical Verification Initiative. *)
(* This is a COMPOSITION property: it places a receiver-side decision rule  *)
(* (the §2.3.3 receive checks, steps 2-6) ON TOP OF the full-fidelity        *)
(* on-chain state machine module/Onchain.tla, and proves -- UNBOUNDED, via  *)
(* an inductive invariant over the composed machine -- that an honest       *)
(* receiver running §2.3.3 NEVER credits a coin unless the protocol's own    *)
(* admission facts held at credit time.                                     *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P6, HIGH).                              *)
(*   A receiver crediting a coin depends only on (a) the Bitcoin chain it   *)
(*   itself reads, (b) the bundle it received, (c) its own derivable keys.  *)
(*   No node, courier, sender, or third party can cause an honest receiver  *)
(*   -- running §2.3.3 correctly -- to credit a coin that is NOT produced by *)
(*   a valid transition admitted on Bitcoin. Formally: every credited entry *)
(*   satisfies, AT CREDIT TIME, all three load-bearing §2.3.3 checks against *)
(*   the receiver's OWN view of the Onchain state:                          *)
(*     step 2  (recursive verify)        -- proof accepts => statement holds *)
(*                                          (A1 KnowledgeSound oracle);      *)
(*     step 4  (anchor in `completed`)    -- the coin's creating batch is    *)
(*                                          admitted AND >= 6 conf, i.e. its *)
(*                                          nullifiers are in the receiver's *)
(*                                          own onCompleted zone (§3.10);     *)
(*     step 5  (nf non-membership)        -- the coin's own nullifier is a   *)
(*                                          non-member of the live           *)
(*                                          accumulator Acc at credit time.  *)
(*                                                                         *)
(* WHY A RECEIVER LAYER IS BUILT HERE. The shared modules deliberately have  *)
(* NO Receive action: receive-side credit is a CLIENT decision (§2.3.3),     *)
(* not an on-chain transition, and module/Onchain.tla is explicit that the   *)
(* receive-side classification is "modelled in the receive properties".      *)
(* P06 is that property. It EXTENDS Onchain (so the receiver reads the REAL  *)
(* onPending/onCompleted/Acc the on-chain machine maintains) and adds one    *)
(* receiver variable `credited` plus a `Receive` gate and an adversarial     *)
(* `AdversaryOffer` action.                                                  *)
(*                                                                         *)
(* THE COMPOSED MACHINE.                                                     *)
(*   P6Next == OnNext \/ Receive \/ AdversaryOffer                          *)
(*   - OnNext          advances the receiver's OWN chain view (admit/confirm/ *)
(*                     reorg) exactly as Onchain defines it. The receiver    *)
(*     reads this view; nobody injects a false view (A13: the node runs its  *)
(*     own bitcoind, so its chain view is the true canonical chain -- the    *)
(*     eclipse case is the inherited Bitcoin assumption, out of frame).      *)
(*   - Receive        the §2.3.3 gate. It picks an ARBITRARY candidate coin  *)
(*                     (adversary-chosen attributes: any nf, any claimed      *)
(*     creating-batch, any proof bit) and credits it ONLY IF the three       *)
(*     checks pass against the receiver's own Onchain state. A ghost records *)
(*     what was TRUE at credit time, so INV_P6 is non-trivial.              *)
(*   - AdversaryOffer  the UNCHECKED adversary: it OFFERS arbitrary           *)
(*                     (forged / unanchored / already-spent) candidate       *)
(*     bundles into an offer pool with NO gate. The point of the property is *)
(*     that offering changes nothing the receiver credits -- only the gated  *)
(*     Receive may credit, and only when the checks hold. AdversaryOffer     *)
(*     therefore touches only `offered`, never `credited`.                   *)
(*                                                                         *)
(* INV_P6 (the safety property): every entry in `credited` satisfies its     *)
(* recorded proofAttests AND anchorCompleted AND nfWasNonMember bits, and    *)
(* those bits are the GENUINE facts the gate evaluated against the chain     *)
(* (anchorCompleted entries really have their anchor set inside onCompleted; *)
(* see CreditedConsistent). A credit can thus exist ONLY if a valid,         *)
(* on-Bitcoin-admitted, finalised, unspent transition backed it.            *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (vacuity + negative controls, notes.md):    *)
(*   (i)   reachability: a credit actually happens (the negation             *)
(*         "credited stays empty" is violated -- check [P1]).                *)
(*   (ii)  drop the anchor-completed check from Receive => INV_P6 fails: a   *)
(*         coin whose batch is only `pending` (in onPending, not onCompleted) *)
(*         gets credited (negative control NC-A).                            *)
(*   (iii) drop the proof-verifies check from Receive => INV_P6 fails: a coin *)
(*         whose recursive proof does NOT attest its statement gets credited *)
(*         (negative control NC-B).                                          *)
(*                                                                         *)
(* SCOPE (honest, stated openly).                                           *)
(*   - A13 eclipse is an ASSUMPTION, not a theorem: the receiver's chain     *)
(*     view IS the true canonical chain (Assumptions A13). Pass-3 itself     *)
(*     records that operator-network-level eclipse is an inherited Bitcoin   *)
(*     assumption the spec cannot improve over. We compose A13; we do not    *)
(*     re-prove Bitcoin.                                                     *)
(*   - Bundle DATA-AVAILABILITY (transport withhold/replication) is a        *)
(*     LIVENESS concern (P08, §4.6), not safety, and is out of frame here.   *)
(*   - The `mint-verified` path (non-anchored mints, §3.10) substitutes      *)
(*     direct InitialProof re-verification for the anchor check; this        *)
(*     property models the anchored receive (steps 2/4/5). The mint path's   *)
(*     safety reduces to step 2 alone and is out of frame.                   *)
(*   - Steps 3 (inclusion in ocr) and 6 (amount/asset sanity) are LOCAL      *)
(*     in-receiver checks (Pass-3: "local checks"); step 3 is folded into the *)
(*     step-2 statement (the proof attests the coin sits under output_coins_  *)
(*     root) and step 6 is a pure self-check on the receiver's own address,  *)
(*     so neither admits third-party influence. The load-bearing,            *)
(*     third-party-relevant checks are 2/4/5, modelled explicitly.           *)
(***************************************************************************)
EXTENDS Onchain, Apalache

(***************************************************************************)
(* Receiver-layer types.                                                    *)
(*                                                                         *)
(* A credited entry is a GHOST record of one §2.3.3 credit: the coin's own   *)
(* nullifier `cnf`, the nullifier set `anchorNfs` of the batch that created  *)
(* the coin (its on-chain anchor), and the three bits the gate evaluated --  *)
(* proofAttests (step 2), anchorCompleted (step 4), nfWasNonMember (step 5). *)
(* The bits record what was TRUE AT CREDIT TIME, so INV_P6 is a real claim   *)
(* about the gate, not a tautology over the present state.                   *)
(*                                                                         *)
(* @typeAlias: creditEntry = {                                              *)
(*   cnf: $nullifier,                                                       *)
(*   anchorNfs: Set($nullifier),                                            *)
(*   proofAttests: Bool,                                                    *)
(*   anchorCompleted: Bool,                                                  *)
(*   nfWasNonMember: Bool                                                    *)
(* };                                                                        *)
(*                                                                         *)
(* An offered candidate is what the adversary/courier/sender hands over: a   *)
(* coin nullifier, a CLAIMED creating-batch nullifier set, and a CLAIMED     *)
(* proof-acceptance bit. None of these are trusted -- the Receive gate       *)
(* re-derives the truth against the receiver's own chain view.               *)
(*                                                                         *)
(* @typeAlias: offerCand = {                                                *)
(*   ocnf: $nullifier,                                                      *)
(*   oAnchorNfs: Set($nullifier),                                           *)
(*   oProofAccepts: Bool                                                     *)
(* };                                                                        *)
(***************************************************************************)
P06_typedefs == TRUE

VARIABLES
  \* The receiver's credited coins (§2.3.3 final step). Each is a ghost record
  \* of one credit and the facts the gate evaluated. This is the variable the
  \* safety property INV_P6 constrains.
  \* @type: Set($creditEntry);
  credited,
  \* The adversary's offer pool: arbitrary candidate bundles handed to the
  \* receiver by any third party. UNCHECKED on entry; only the Receive gate
  \* decides whether any of these become a credit.
  \* @type: Set($offerCand);
  offered

\* @type: <<Set($creditEntry), Set($offerCand)>>;
rcvVars == << credited, offered >>

\* All on-chain variables of the EXTENDED Onchain machine (so Receive /
\* AdversaryOffer can leave the chain UNCHANGED, and OnNext can leave the
\* receiver layer UNCHANGED).
\* @type: <<Set($nullifier), Set($nullifier), Set($nullifier), Set(<<Int, Int>>), Seq($batchInscription)>>;
chainVars == onVars

(***************************************************************************)
(* The §2.3.3 receive checks, each as a predicate over the receiver's OWN    *)
(* view of the Onchain state. These are the decision rule the receiver runs; *)
(* they read onCompleted / Acc, the values the on-chain machine maintains.   *)
(***************************************************************************)

\* STEP 2 (recursive verify). A1 knowledge-soundness: if the proof accepts,
\* its statement holds. The receiver credits on `proofAccepts`; the SOUND
\* fact it may rely on is `statementHolds`. We model the candidate's proof
\* acceptance bit and require, via KnowledgeSound, that acceptance entails the
\* statement. The honest receiver accepts only a verifying proof, and A1 makes
\* "verifying" mean "statement true". (No party can forge acceptance of a
\* false statement -- that would break A1.)
\* @type: (Bool) => Bool;
Step2_ProofVerifies(proofAccepts) ==
  \* The receiver requires the proof to verify; KnowledgeSound guarantees the
  \* attested statement then holds. Encoded so that the gate fires only when
  \* acceptance is REAL (proofAccepts = TRUE) and -- by A1 -- sound.
  /\ proofAccepts = TRUE
  /\ KnowledgeSound(proofAccepts, proofAccepts)

\* STEP 4 (anchor in a `completed` SpendRecord). The coin's creating batch
\* must be admitted (§3.5+§3.6) AND have >= 6 confirmations (§3.9) -- i.e. its
\* nullifiers sit in the receiver's OWN onCompleted zone (§3.10). A non-empty
\* anchor that is a subset of onCompleted is exactly "completed". A batch only
\* in onPending (admitted but < 6 conf) FAILS this -- the receiver MUST treat a
\* `pending` inscription as not anchored.
\* @type: (Set($nullifier)) => Bool;
Step4_AnchorCompleted(anchorNfs) ==
  /\ anchorNfs # {}
  /\ anchorNfs \subseteq onCompleted

\* STEP 5 (nullifier non-membership). The coin's own nf must be a NON-member of
\* the live accumulator Acc = onPending \cup onCompleted (§3.7, NAV(tip)). The
\* receiver rebuilds Acc from its own chain view; nobody can fake non-membership
\* against a root the receiver knows from Bitcoin.
\* @type: ($nullifier) => Bool;
Step5_NfNonMember(cnf) == cnf \notin Acc

(***************************************************************************)
(* Initial state: nothing credited, nothing offered; chain starts as OnInit. *)
(***************************************************************************)
\* @type: () => Bool;
P6Init ==
  /\ OnInit
  /\ credited = {}
  /\ offered = {}

(***************************************************************************)
(* AdversaryOffer -- the UNCHECKED adversarial-delivery action. A third party *)
(* (malicious node / courier / sender) offers an ARBITRARY candidate bundle: *)
(* any coin nullifier, any CLAIMED creating-batch, any CLAIMED proof bit --   *)
(* including forged (proof claims to accept a false statement), unanchored    *)
(* (anchor not in onCompleted), or already-spent (nf in Acc) candidates. It   *)
(* only grows `offered`; it NEVER credits and NEVER touches the chain. The    *)
(* whole point of the property: offering arbitrary junk cannot move `credited`.*)
(***************************************************************************)
\* @type: () => Bool;
AdversaryOffer ==
  \E cnf \in Nullifiers, anchorNfs \in SUBSET Nullifiers, paccepts \in BOOLEAN :
    /\ offered' = offered \union
         { [ ocnf |-> cnf, oAnchorNfs |-> anchorNfs, oProofAccepts |-> paccepts ] }
    /\ UNCHANGED credited
    /\ UNCHANGED chainVars

(***************************************************************************)
(* Receive -- the §2.3.3 gate (steps 2-6). The receiver takes a candidate    *)
(* from the adversary's offer pool (so the candidate is adversary-CHOSEN,     *)
(* untrusted) and credits it ONLY IF all three load-bearing checks pass       *)
(* against its OWN chain view. The ghost entry records the genuine facts the  *)
(* gate evaluated.                                                            *)
(*                                                                         *)
(* Crucially the gate reads `cand.oProofAccepts`, `cand.oAnchorNfs`,          *)
(* `cand.ocnf` -- the candidate's CLAIMS -- but tests them against onCompleted *)
(* / Acc, the receiver's OWN state. A forged claim that does not match the    *)
(* chain simply fails the gate, so Receive does not fire on it.               *)
(***************************************************************************)
\* @type: () => Bool;
Receive ==
  \E cand \in offered :
    LET attests   == Step2_ProofVerifies(cand.oProofAccepts)
        completed == Step4_AnchorCompleted(cand.oAnchorNfs)
        unspent   == Step5_NfNonMember(cand.ocnf)
    IN
      \* GATE: all three §2.3.3 checks MUST pass (step 6 / step 3 are local
      \* self-checks, folded into the step-2 statement / the receiver address).
      /\ attests
      /\ completed
      /\ unspent
      \* Credit: record the coin and the GENUINE facts at credit time.
      /\ credited' = credited \union
           { [ cnf             |-> cand.ocnf,
               anchorNfs       |-> cand.oAnchorNfs,
               proofAttests    |-> attests,
               anchorCompleted |-> completed,
               nfWasNonMember  |-> unspent ] }
      /\ UNCHANGED offered
      /\ UNCHANGED chainVars

(***************************************************************************)
(* The composed transition relation: the on-chain machine, the §2.3.3 gate,  *)
(* and the unchecked adversary, interleaved.                                 *)
(***************************************************************************)
\* @type: () => Bool;
P6Next ==
  \/ /\ OnNext
     /\ UNCHANGED rcvVars
  \/ Receive
  \/ AdversaryOffer

\* @type: () => Bool;
P6Spec == P6Init /\ [][P6Next]_<<onVars, credited, offered>>

(***************************************************************************)
(* THE SAFETY PROPERTY INV_P6.                                             *)
(*                                                                         *)
(* Every credited entry satisfies its three recorded checks AND those bits  *)
(* are the GENUINE chain facts the gate evaluated. The non-triviality comes  *)
(* from CreditedConsistent: an entry whose `anchorCompleted` bit is TRUE     *)
(* really has a non-empty anchor that is a subset of onCompleted -- so a      *)
(* credit cannot exist for a coin whose creating batch never reached          *)
(* `completed` on the receiver's own chain. (anchorNfs \subseteq onCompleted  *)
(* is a CURRENT-state fact; under the model onCompleted only GROWS -- Confirm *)
(* adds, Reorg leaves it untouched, A12 -- so what was completed at credit    *)
(* stays completed, and the invariant is preserved by every action.)         *)
(***************************************************************************)

\* The recorded bits are all TRUE -- the gate did fire on a full pass.
\* @type: () => Bool;
CreditedChecksHeld ==
  \A e \in credited :
    /\ e.proofAttests = TRUE
    /\ e.anchorCompleted = TRUE
    /\ e.nfWasNonMember = TRUE

\* The recorded anchorCompleted bit is BACKED by the live chain: a credited
\* coin's anchor is a non-empty subset of onCompleted. This is the load-bearing
\* anti-vacuity conjunct -- it ties the ghost to the receiver's real view.
\* @type: () => Bool;
CreditedAnchored ==
  \A e \in credited :
    /\ e.anchorNfs # {}
    /\ e.anchorNfs \subseteq onCompleted

\* @type: () => Bool;
INV_P6 ==
  /\ CreditedChecksHeld
  /\ CreditedAnchored

(***************************************************************************)
(* INDUCTIVE INVARIANT for the UNBOUNDED proof.                            *)
(*                                                                         *)
(* IndInv_P6 strengthens INV_P6 with the structural type facts the SMT step  *)
(* needs to quantify over well-formed states (the receiver records and the   *)
(* Onchain set variables), plus -- crucially -- the DISJOINT-ZONES fact      *)
(* onPending \cap onCompleted = {} and onDoubled = {} carried over from the   *)
(* on-chain machine. These are not needed for INV_P6 itself but keep the      *)
(* composed state well-formed so the step is decidable and faithful.         *)
(*                                                                         *)
(* WHY IT IS INDUCTIVE.                                                      *)
(*   - Receive only ADDS an entry whose bits are exactly the gate results,    *)
(*     all TRUE (so CreditedChecksHeld holds), and whose anchorNfs is a       *)
(*     non-empty subset of onCompleted AT THAT INSTANT (so CreditedAnchored   *)
(*     holds for the new entry; existing entries are untouched and the chain  *)
(*     is UNCHANGED).                                                         *)
(*   - AdversaryOffer leaves `credited` and the chain unchanged, so both      *)
(*     conjuncts are trivially preserved.                                     *)
(*   - OnNext leaves `credited` unchanged; the only conjunct it could break   *)
(*     is CreditedAnchored (which reads onCompleted). But onCompleted only     *)
(*     GROWS: Confirm sets onCompleted' = onCompleted \cup M; Admit and        *)
(*     PublisherSign leave it; Reorg leaves onCompleted untouched (§3.10 A12,  *)
(*     completed is absolute). A subset of onCompleted stays a subset of a     *)
(*     superset, so e.anchorNfs \subseteq onCompleted is preserved. THIS is    *)
(*     the load-bearing monotonicity argument (notes.md).                     *)
(***************************************************************************)
\* @type: () => Bool;
IndInv_P6 ==
  /\ onPending \subseteq Nullifiers
  /\ onCompleted \subseteq Nullifiers
  /\ onDoubled \subseteq Nullifiers
  /\ onAuthorised \subseteq (Publishers \X BundleLocators)
  /\ onPending \intersect onCompleted = {}
  /\ \A e \in credited :
       /\ e.cnf \in Nullifiers
       /\ e.anchorNfs \subseteq Nullifiers
  /\ \A o \in offered :
       /\ o.ocnf \in Nullifiers
       /\ o.oAnchorNfs \subseteq Nullifiers
  /\ INV_P6

(***************************************************************************)
(* Assignment-form restatement of IndInv_P6, used as the --init predicate of *)
(* the inductive-STEP check. Apalache requires every variable to be ASSIGNED  *)
(* in an init predicate (a bare \subseteq / \A is a constraint, not an         *)
(* assignment). Each set variable is drawn from its powerset; `credited` and  *)
(* `offered` are drawn from the powerset of their well-formed entry domains;   *)
(* the chain sequence is assigned an arbitrary bounded value via apalache.Gen  *)
(* (its value is never read by IndInv_P6 nor by the receiver gate, exactly as  *)
(* in the P02 Seq-projection argument -- the receiver reads onCompleted/Acc,   *)
(* the SET projection, never the chain history). The IndInv_P6 body is then    *)
(* asserted, pinning the safety conjuncts.                                    *)
(*                                                                         *)
(* The entry domains are built so every drawn credited/offered record is       *)
(* structurally well-formed (cnf/anchorNfs over Nullifiers, bits Boolean);     *)
(* IndInv_P6 then constrains which of those records may actually appear.       *)
(***************************************************************************)
\* @type: () => Set($creditEntry);
CreditEntryDomain ==
  { [ cnf |-> n, anchorNfs |-> a,
      proofAttests |-> p, anchorCompleted |-> c, nfWasNonMember |-> u ] :
      n \in Nullifiers, a \in SUBSET Nullifiers,
      p \in BOOLEAN, c \in BOOLEAN, u \in BOOLEAN }

\* @type: () => Set($offerCand);
OfferCandDomain ==
  { [ ocnf |-> n, oAnchorNfs |-> a, oProofAccepts |-> p ] :
      n \in Nullifiers, a \in SUBSET Nullifiers, p \in BOOLEAN }

\* @type: () => Bool;
IndInvInit ==
  /\ onPending \in SUBSET Nullifiers
  /\ onCompleted \in SUBSET Nullifiers
  /\ onDoubled = {}
  /\ onAuthorised \in SUBSET (Publishers \X BundleLocators)
  /\ onPending \intersect onCompleted = {}
  /\ onAdmittedChain = Gen(4)
  /\ credited \in SUBSET CreditEntryDomain
  /\ offered \in SUBSET OfferCandDomain
  /\ INV_P6

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Reuses the small finite instance *)
(* fixed in module/Onchain.tla; the inductive argument is uniform in the      *)
(* universe sizes (every conjunct is per-nullifier / per-entry local).        *)
(***************************************************************************)
\* @type: () => Bool;
P6ConstInit == OnConstInit

(***************************************************************************)
(* VACUITY GUARD -- reachability probe (check [P1]).                        *)
(*                                                                         *)
(* CreditsNeverHappen asserts `credited` stays empty. If Apalache VIOLATES   *)
(* it (returns Error with a trace), a credit is genuinely reachable -- the   *)
(* gate is not vacuously unsatisfiable and INV_P6 is not vacuously true on an *)
(* empty `credited`. verify.sh runs this expecting a COUNTEREXAMPLE.         *)
(***************************************************************************)
\* @type: () => Bool;
CreditsNeverHappen == credited = {}

=============================================================================
