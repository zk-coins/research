-------------------------- MODULE member_root_nc --------------------------
(* NEGATIVE CONTROL for P02 member_root order-binding.                        *)
(* Identical to member_root.tla EXCEPT the order-sensitive MemberRoot is       *)
(* replaced by an order-INSENSITIVE SET-hash: member_root = a function of the  *)
(* member SET only. Then two distinct PERMUTATIONS of the same members share a *)
(* locator (same prev/new/m/set) but differ as SEQUENCES => LocatorBindsOrder  *)
(* must fail with a counterexample. Everything else is verbatim.              *)
EXTENDS Integers, Sequences, Apalache

CONSTANT
  \* @type: Set(Int);
  MemberIds,
  \* @type: Set(Int);
  RootTags,
  \* @type: Int;
  MaxM

\* @typeAlias: bundle = { prevTag: Int, newTag: Int, m: Int, memberSeq: Seq(Int), locator: $loc };
\* @typeAlias: loc = { prev: Int, new: Int, m: Int, mr: Set(Int) };
member_root_nc_typedefs == TRUE

VARIABLES
  \* @type: Set($bundle);
  admitted

\* @type: <<Set($bundle)>>;
vars == << admitted >>

\* ORDER-INSENSITIVE set-hash member_root (the DELETED order binding): returns
\* the member SET, dropping all ordering information.
\* @type: (Seq(Int)) => Set(Int);
MemberRootSet(seq) == { seq[i] : i \in DOMAIN seq }

\* @type: (Int, Int, Int, Set(Int)) => $loc;
Locator(prev, new, m, mr) == [ prev |-> prev, new |-> new, m |-> m, mr |-> mr ]

\* @type: ($bundle) => Bool;
WellFormed(b) ==
  /\ b.prevTag \in RootTags
  /\ b.newTag \in RootTags
  /\ b.m = Len(b.memberSeq)
  /\ b.m >= 1 /\ b.m <= MaxM
  /\ \A i \in DOMAIN b.memberSeq : b.memberSeq[i] \in MemberIds
  /\ \A i, j \in DOMAIN b.memberSeq : i # j => b.memberSeq[i] # b.memberSeq[j]
  /\ b.locator = Locator(b.prevTag, b.newTag, b.m, MemberRootSet(b.memberSeq))

\* @type: () => Bool;
Init == admitted = {}

\* @type: () => Bool;
Admit ==
  \E prev \in RootTags, new \in RootTags :
    LET \* @type: Seq(Int);
        seq == Gen(MaxM)
        \* @type: $bundle;
        cand == [ prevTag |-> prev, newTag |-> new, m |-> Len(seq),
                  memberSeq |-> seq,
                  locator |-> Locator(prev, new, Len(seq), MemberRootSet(seq)) ]
    IN
      /\ WellFormed(cand)
      /\ admitted' = admitted \union { cand }

\* @type: () => Bool;
Next == Admit

\* @type: () => Bool;
LocatorBindsOrder ==
  \A b1, b2 \in admitted :
    (b1.locator.mr = b2.locator.mr) => (b1.memberSeq = b2.memberSeq)

\* @type: () => Bool;
ConstInit ==
  /\ MemberIds = 1..3
  /\ RootTags = 1..2
  /\ MaxM = 3
=============================================================================
