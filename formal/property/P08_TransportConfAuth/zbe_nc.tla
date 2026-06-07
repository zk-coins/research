-------------------------- MODULE zbe_nc --------------------------
(* NEGATIVE CONTROL for P08 ZBE anti-truncation.                              *)
(* Identical to zbe.tla EXCEPT the per-chunk (N,i) AAD binding is DROPPED:      *)
(* ChunkAuth becomes TRUE regardless of (n,idx) -- the AAD does not cover the    *)
(* count/index. Then a truncated or reordered `received` AUTHENTICATES yet       *)
(* differs from `sealed` => AntiTruncation fails. Everything else is verbatim.  *)
EXTENDS Integers, Sequences, Apalache

CONSTANT
  \* @type: Int;
  MaxN,
  \* @type: Set(Int);
  Payloads

\* @typeAlias: chunk = { n: Int, idx: Int, payload: Int };
zbe_nc_typedefs == TRUE

VARIABLES
  \* @type: Seq($chunk);
  sealed,
  \* @type: Seq($chunk);
  received,
  \* @type: Bool;
  accepted

\* @type: <<Seq($chunk), Seq($chunk), Bool>>;
vars == << sealed, received, accepted >>

\* DROPPED (N,i) AAD binding: the tag verifies regardless of count/index.
\* @type: ($chunk, Int, Int) => Bool;
ChunkAuth(c, obsN, pos) == TRUE

\* @type: (Seq($chunk)) => Bool;
Accepts(rx) ==
  /\ Len(rx) >= 1
  /\ \A p \in DOMAIN rx : ChunkAuth(rx[p], Len(rx), p)

\* @type: (Seq($chunk)) => Bool;
WellSealed(s) ==
  /\ Len(s) >= 1 /\ Len(s) <= MaxN
  /\ \A j \in DOMAIN s :
       /\ s[j].n = Len(s)
       /\ s[j].idx = j - 1
       /\ s[j].payload \in Payloads

\* @type: () => Bool;
Init ==
  /\ sealed = << [ n |-> 1, idx |-> 0, payload |-> CHOOSE x \in Payloads : TRUE ] >>
  /\ received = << >>
  /\ accepted = FALSE

\* @type: () => Bool;
Seal ==
  \E s \in { Gen(MaxN) } :
    /\ WellSealed(s)
    /\ sealed' = s
    /\ received' = << >>
    /\ accepted' = FALSE

\* @type: () => Bool;
Deliver ==
  \E rx \in { Gen(MaxN) } :
    /\ \A p \in DOMAIN rx : \E j \in DOMAIN sealed : rx[p] = sealed[j]
    /\ received' = rx
    /\ accepted' = Accepts(rx)
    /\ UNCHANGED sealed

\* @type: () => Bool;
Next == Seal \/ Deliver

\* @type: () => Bool;
AntiTruncation == accepted => (received = sealed)

\* @type: () => Bool;
ConstInit ==
  /\ MaxN = 3
  /\ Payloads = 1..2
=============================================================================
