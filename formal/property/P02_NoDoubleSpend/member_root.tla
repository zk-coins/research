-------------------------- MODULE member_root --------------------------
(***************************************************************************)
(* P02 -- member_root ORDER-binding (spec-v1.1 / docs#47, On-chain §3.5/§3.6).*)
(*                                                                         *)
(* A NEW load-bearing invariant added for the spec-v1.1 baseline            *)
(* (docs@ed7fdece). docs#47 changed the on-chain bundle_locator from        *)
(*   Hc("BatchBundle", serialize(BatchBundle))                              *)
(* to                                                                       *)
(*   Hc("BatchBundle", prev_root || new_root || u32-be(m) || member_root)   *)
(* where member_root is a binary Poseidon hash tree over the ORDERED member  *)
(* SpendRecords (leaf Hc("BatchMember", serialize(SpendRecord_j)), node      *)
(* Hc("BatchMember/Node", left, right), padding leaf Hc("BatchMember",       *)
(* emptyset)). The spec states this "binds both the exact member set AND      *)
(* their order", and the scanner recomputes member_root from the ordered      *)
(* records and rejects a mismatch (§3.6 step 6).                            *)
(*                                                                         *)
(* THE CLAIM proven here (the genuinely NEW #47 guarantee, lifted from        *)
(* hand-argument to a machine-checked invariant): a publisher cannot reorder  *)
(* members or swap the member set under one proof/locator -- any two admitted *)
(* bundles that share a bundle_locator carry the SAME ordered member          *)
(* sequence. (No-double-spend itself stays in abstract.tla / property.tla;    *)
(* this file is specifically the ORDER+SET binding the new locator adds.)     *)
(*                                                                         *)
(* HASH MODELLING (the repo idiom -- a digest IS the structured value it       *)
(* commits to; equality of digest = equality of preimage; see                *)
(* module/Foundations.tla and module/Assumptions.tla RootCommitsSet).        *)
(*   - MemberRoot(seq) is the ORDER-SENSITIVE binary-tree fold over the       *)
(*     ordered leaves. Its collision-resistance (A3 Poseidon CR, A16 Merkle/  *)
(*     SMT CR lifting) is modelled as INJECTIVITY: MemberRoot(s1)=MemberRoot( *)
(*     s2) <=> s1 = s2 as SEQUENCES (not as sets). The structured value IS    *)
(*     the ordered sequence it folds.                                        *)
(*   - Locator(prev,new,m,mr) is the outer Hc, injective in all four fields   *)
(*     (A3). The structured value IS the 4-tuple.                            *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (negative control). Replace the              *)
(* order-sensitive MemberRoot with an order-INSENSITIVE SET-hash variant      *)
(* (member_root = a function of the member SET only) and re-run: two distinct *)
(* permutations of the same members then share a locator but differ as        *)
(* sequences, so Apalache returns a counterexample to LocatorBindsOrder. The  *)
(* commented `MemberRootSet` variant + the recorded run are in notes.md.      *)
(***************************************************************************)
EXTENDS Integers, Sequences, Apalache

CONSTANT
  \* Finite universe of member-id leaves (a member SpendRecord's leaf hash, by
  \* A3 the leaf IS the SpendRecord). Members within a bundle are distinct ids.
  \* @type: Set(Int);
  MemberIds,
  \* Finite universe of (prev_root, new_root) accumulator-transition pairs the
  \* locator also binds. Carried as opaque Int tags (A16: a root IS its set).
  \* @type: Set(Int);
  RootTags,
  \* Maximum member count m per admitted bundle (the u32-be(m) field). Keeps the
  \* admitted member sequences finite-capacity for the SMT encoding.
  \* @type: Int;
  MaxM

(***************************************************************************)
(* Bundle record. memberSeq is the ORDERED member-id leaf sequence; m is its  *)
(* length (the u32-be(m) field); prevTag/newTag are the two roots; locator is  *)
(* the outer Hc value computed from all four.                                 *)
(*                                                                         *)
(* @typeAlias: bundle = {                                                    *)
(*   prevTag: Int, newTag: Int, m: Int,                                     *)
(*   memberSeq: Seq(Int), locator: $loc                                     *)
(* };                                                                        *)
(* @typeAlias: loc = { prev: Int, new: Int, m: Int, mr: Seq(Int) };         *)
(***************************************************************************)
member_root_typedefs == TRUE

VARIABLES
  \* The set of admitted (scanner-accepted) bundles. A bundle is admitted only
  \* if its locator was recomputed from its ordered records (§3.6 step 6).
  \* @type: Set($bundle);
  admitted

\* @type: <<Set($bundle)>>;
vars == << admitted >>

(***************************************************************************)
(* MemberRoot -- the ORDER-SENSITIVE binary-tree fold over the ordered leaves.*)
(* Modelled (A3/A16) as the structured value that IS the ordered sequence:     *)
(* injective in the sequence, so MemberRoot(s1) = MemberRoot(s2) <=> s1 = s2. *)
(* @type: (Seq(Int)) => Seq(Int);                                            *)
(***************************************************************************)
MemberRoot(seq) == seq

(***************************************************************************)
(* Locator -- the outer Hc("BatchBundle", prev || new || u32-be(m) ||         *)
(* member_root), the structured 4-tuple value (injective in all four, A3).    *)
(* @type: (Int, Int, Int, Seq(Int)) => $loc;                                  *)
(***************************************************************************)
Locator(prev, new, m, mr) == [ prev |-> prev, new |-> new, m |-> m, mr |-> mr ]

(***************************************************************************)
(* Well-formed bundle: the locator equals the Hc recomputed from this         *)
(* bundle's own fields with the ORDER-SENSITIVE MemberRoot, m = Len(memberSeq) *)
(* (the §3.6-step-6 scanner check), member ids drawn from MemberIds, distinct  *)
(* (a member set has no repeated SpendRecord), and 1 <= m <= MaxM.            *)
(* @type: ($bundle) => Bool;                                                  *)
(***************************************************************************)
WellFormed(b) ==
  /\ b.prevTag \in RootTags
  /\ b.newTag \in RootTags
  /\ b.m = Len(b.memberSeq)
  /\ b.m >= 1 /\ b.m <= MaxM
  /\ \A i \in DOMAIN b.memberSeq : b.memberSeq[i] \in MemberIds
  /\ \A i, j \in DOMAIN b.memberSeq : i # j => b.memberSeq[i] # b.memberSeq[j]
  /\ b.locator = Locator(b.prevTag, b.newTag, b.m, MemberRoot(b.memberSeq))

(***************************************************************************)
(* Init / Next. Admit one well-formed bundle per step (the §3.6 scan).        *)
(***************************************************************************)
\* @type: () => Bool;
Init == admitted = {}

\* Admit one bundle. The publisher freely chooses the two roots and the ORDERED
\* member sequence; the scanner derives m = Len(memberSeq) and recomputes the
\* locator from the order-sensitive MemberRoot (§3.6 step 6), then admits iff the
\* bundle is well-formed. The candidate sequence is GENERATED via apalache.Gen
\* (capacity MaxM); WellFormed then carves out exactly the admissible bundles.
\* @type: () => Bool;
Admit ==
  \E prev \in RootTags, new \in RootTags :
    LET \* @type: Seq(Int);
        seq == Gen(MaxM)
        \* @type: $bundle;
        cand == [ prevTag |-> prev, newTag |-> new, m |-> Len(seq),
                  memberSeq |-> seq,
                  locator |-> Locator(prev, new, Len(seq), MemberRoot(seq)) ]
    IN
      /\ WellFormed(cand)
      /\ admitted' = admitted \union { cand }

\* @type: () => Bool;
Next == Admit

\* @type: () => Bool;
Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

\* Structural type-correctness: every admitted bundle is well-formed.
\* @type: () => Bool;
TypeOK == \A b \in admitted : WellFormed(b)

(***************************************************************************)
(* THE LOAD-BEARING SAFETY CLAIM (docs#47 §3.6 step 6): any two admitted       *)
(* bundles that share a bundle_locator's member_root carry the SAME ORDERED     *)
(* member sequence. A publisher cannot reorder members or swap the member set   *)
(* under one member_root/proof: member_root binds set AND order.               *)
(*                                                                         *)
(* We test the link from the locator's member_root FIELD (b.locator.mr) to the *)
(* ordered sequence, NOT from the whole locator. This is deliberate and is what *)
(* keeps the invariant NON-VACUOUS: the whole locator is injective in all four  *)
(* fields, so "equal whole locator" would only ever hold for b1 = b2 (the       *)
(* records collapse in `admitted`) -- a vacuous antecedent. The member_root      *)
(* field, by contrast, is shared across DISTINCT bundles (e.g. two bundles with *)
(* the same ordered members but different prev/new roots), so the antecedent IS *)
(* reachable for b1 # b2 (vacuity probe in notes.md), and the order-sensitive   *)
(* MemberRoot is exactly what forces the consequent. The NEGATIVE CONTROL        *)
(* (set-hash member_root) breaks precisely this field-to-sequence link.         *)
(* @type: () => Bool;                                                          *)
(***************************************************************************)
LocatorBindsOrder ==
  \A b1, b2 \in admitted :
    (b1.locator.mr = b2.locator.mr) => (b1.memberSeq = b2.memberSeq)

(***************************************************************************)
(* Carried strengthening: the locator's member_root field is exactly the        *)
(* order-sensitive MemberRoot of the bundle's own sequence (the §3.6-step-6      *)
(* recomputation). This is what makes LocatorBindsOrder inductive -- without it, *)
(* a Gen'd start state could put an arbitrary mr in the locator decoupled from   *)
(* memberSeq. It follows from WellFormed but is restated as a state fact so the  *)
(* SMT step closes over the projected admitted set.                            *)
(* @type: () => Bool;                                                          *)
(***************************************************************************)
RootIsOfOwnSeq ==
  \A b \in admitted : b.locator.mr = MemberRoot(b.memberSeq)

\* @type: () => Bool;
IndInv ==
  /\ TypeOK
  /\ RootIsOfOwnSeq
  /\ LocatorBindsOrder

(***************************************************************************)
(* Assignment-form restatement used as the --init of the inductive STEP       *)
(* (Apalache requires every variable ASSIGNED, not merely \subseteq-          *)
(* constrained). `admitted` is GENERATED via apalache.Gen (a fresh symbolic    *)
(* set of bundle records, cardinality bounded by the argument) and then        *)
(* constrained by the IndInv body -- logically equivalent to IndInv over the   *)
(* assigned variable.                                                          *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit ==
  /\ admitted = Gen(4)
  /\ TypeOK
  /\ RootIsOfOwnSeq
  /\ LocatorBindsOrder

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Small finite instance: 3 member   *)
(* ids (enough for distinct permutations 2!,3! to exist), 2 root tags, m<=3.   *)
(* The argument is uniform: LocatorBindsOrder is a pairwise-local fact over     *)
(* injective structured digests, preserved by each Admit independently of the  *)
(* universe sizes (notes.md records the negative control at the same size).    *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit ==
  /\ MemberIds = 1..3
  /\ RootTags = 1..2
  /\ MaxM = 3

(***************************************************************************)
(* VACUITY PROBE. The antecedent of LocatorBindsOrder (two DISTINCT admitted   *)
(* bundles with equal locator.mr) IS reachable: admit two bundles with the      *)
(* same ordered member sequence but different prev/new roots -- same mr, distinct *)
(* bundles. NoSharedRoot below asserts the antecedent never holds across         *)
(* distinct bundles; a check of NoSharedRoot returns a counterexample (the       *)
(* probe is reachable), so LocatorBindsOrder is asserted over a POPULATED        *)
(* antecedent, not vacuously. (Recorded in notes.md.)                          *)
(* @type: () => Bool;                                                           *)
(***************************************************************************)
NoSharedRoot ==
  \A b1, b2 \in admitted :
    (b1 # b2) => (b1.locator.mr # b2.locator.mr)

(***************************************************************************)
(* NEGATIVE CONTROL (committed companion member_root_nc.tla; recorded run in    *)
(* notes.md). Replacing the order-sensitive MemberRoot with the                 *)
(* order-INSENSITIVE set-hash MemberRootSet(seq) == { seq[i] : i \in DOMAIN     *)
(* seq } makes locator.mr a SET; two distinct PERMUTATIONS of the same members  *)
(* then share locator.mr but differ as sequences => LocatorBindsOrder is FALSE  *)
(* (Apalache: State 2 state invariant violated, outcome Error, exit 12). This   *)
(* is the definitive proof the invariant has real content: the SAME invariant   *)
(* becomes falsifiable the moment the order binding is removed.                 *)
(***************************************************************************)
=============================================================================
