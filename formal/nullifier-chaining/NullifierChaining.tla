-------------------------- MODULE NullifierChaining --------------------------
(*****************************************************************************)
(* A LOGIC-LEVEL specification of zkCoins' nullifier-accumulator chaining    *)
(* over the Bitcoin anchor.  It validates ONE claim of the protocol idea,    *)
(* independent of any implementation:                                        *)
(*                                                                           *)
(*   "Given the chaining discipline -- every transition proves its input     *)
(*    nullifiers are NOT yet in the running accumulator, then inserts them,  *)
(*    and the on-chain TOTAL ORDER chains prev_root -> post_root across       *)
(*    transitions and across batches -- no coin is ever spent twice in the   *)
(*    finalised ledger, even under Bitcoin reorgs."                          *)
(*                                                                           *)
(* Grounded in the specification:                                            *)
(*   - Proofs & State Transitions  2.1 clause 4 (nullifier freshness:        *)
(*     non-membership before insertion; pairwise-distinct within a txn).     *)
(*   - On-chain Layer  3.6 / 3.7 (per-transition roots CHAIN in the on-chain *)
(*     total order; batch prev/post roots are the running root at the batch  *)
(*     boundary).                                                            *)
(*                                                                           *)
(* MODELLING ASSUMPTIONS (deliberate abstractions -- stated openly, because  *)
(* a proof is only meaningful relative to what it assumes):                  *)
(*                                                                           *)
(*   A1. Root binds set.  The accumulator ROOT is abstracted by the SET of   *)
(*       nullifiers it commits to.  We therefore treat roots as sets and do  *)
(*       NOT model a prover lying about a root.  That binding (root <-> set)  *)
(*       is exactly the SNARK knowledge-soundness + SMT collision-resistance *)
(*       assumption -- a separate proof obligation, not this one.            *)
(*                                                                           *)
(*   A2. Nullifier injectivity.  nf = H(nk, coin.identifier) is injective,   *)
(*       so we let the nullifier BE the coin id: distinct coins, distinct    *)
(*       nullifiers.                                                         *)
(*                                                                           *)
(*   A3. Thin Bitcoin anchor.  Bitcoin is ONLY an append-only, totally       *)
(*       ordered log of inscribed batches with eventual finality: the        *)
(*       finalised prefix never changes; the last <= K batches (the pending  *)
(*       zone) may be reorged away.  This is the standard honest-majority /  *)
(*       k-confirmation assumption.  We model nothing else about Bitcoin     *)
(*       (no Script, no UTXO, no mining) because the protocol uses nothing   *)
(*       else.                                                               *)
(*                                                                           *)
(* TO SEE THE MODEL CHECKER EARN ITS KEEP: delete the non-membership         *)
(* conjunct marked [GATE] in Chains(...) below and re-run TLC -- it          *)
(* immediately returns a finalised double-spend trace.  With the conjunct,   *)
(* NoDoubleSpend holds for the whole bounded state space.                    *)
(*****************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Coin,        \* finite set of coin identifiers
    K,           \* finality depth: pending zone holds at most K batches
    MaxBatch,    \* max transitions per inscribed batch
    MaxFinal     \* state-space bound on the finalised log length

(* By A2 a nullifier is identified with the coin it spends. *)
Nullifier == Coin

(* A transition spends a NON-EMPTY set of input nullifiers (clause 2/4).    *)
(* "Set" makes pairwise-distinctness within a transition automatic.        *)
Txn == { S \in SUBSET Nullifier : S # {} }

(* A batch is a non-empty sequence of transitions (the on-chain unit, 3.6),*)
(* bounded to MaxBatch for model checking.                                 *)
BoundedBatch == UNION { [1..n -> Txn] : n \in 1..MaxBatch }

VARIABLES
    finalized,   \* Seq of batches: the immutable, totally-ordered final log
    pending      \* Seq of batches: the reorg-able zone (Len <= K)

vars == << finalized, pending >>

(* ---- Derived quantities ---- *)

(* Flatten a sequence of batches into its sequence of transitions, in order.*)
RECURSIVE Flatten(_)
Flatten(bs) == IF bs = <<>> THEN <<>> ELSE Head(bs) \o Flatten(Tail(bs))

(* The accumulator over a sequence of transitions: every input nullifier    *)
(* inserted so far (clause 4: insert each nf into the accumulator).         *)
RECURSIVE AccOf(_)
AccOf(ts) == IF ts = <<>> THEN {} ELSE Head(ts) \cup AccOf(Tail(ts))

(* The running root at the current tip = finalised ++ pending (A1: root=set).*)
TipAcc == AccOf(Flatten(finalized \o pending))

(* The finalised total order of transitions -- the actual ledger. *)
FinalTxns == Flatten(finalized)

(* ---- The compliance predicate (clause 4 + 3.6/3.7) ---- *)

(* Chains(ts, baseAcc): the transition sequence ts chains correctly when     *)
(* started from accumulator baseAcc.  Walking left to right, each txn's      *)
(* inputs must be fresh w.r.t. the accumulator AS IT STANDS just before it   *)
(* [GATE = non-membership], and are then inserted before the next txn        *)
(* [insertion].  This is precisely the prev_root -> post_root chaining,      *)
(* holding both WITHIN a batch and -- because baseAcc is the previous tip    *)
(* root -- ACROSS batch boundaries (3.7).                                    *)
RECURSIVE Chains(_, _)
Chains(ts, baseAcc) ==
    IF ts = <<>> THEN TRUE
    ELSE /\ Head(ts) \cap baseAcc = {}              \* [GATE] non-membership
         /\ Chains(Tail(ts), baseAcc \cup Head(ts)) \* insert, then continue

(* A batch is admissible iff it chains starting from the current tip root.  *)
ValidBatch(b) == Chains(b, TipAcc)

(* ---- Actions ---- *)

Init ==
    /\ finalized = <<>>
    /\ pending   = <<>>

(* Submit a batch onto the pending tip.  The proposer is UNRESTRICTED: it    *)
(* may choose any batch, including an adversarial one that reuses an         *)
(* already-spent nullifier.  ValidBatch is the only gate.                    *)
SubmitBatch ==
    /\ Len(pending) < K
    /\ \E b \in BoundedBatch :
         /\ ValidBatch(b)
         /\ pending' = Append(pending, b)
    /\ UNCHANGED finalized

(* Finality (A3): the oldest pending batch becomes irrevocably final.        *)
Finalize ==
    /\ pending # <<>>
    /\ Len(finalized) < MaxFinal
    /\ finalized' = Append(finalized, Head(pending))
    /\ pending'   = Tail(pending)

(* Reorg (A3): the non-final zone reorganises -- a suffix of pending is       *)
(* dropped.  Finalised is NEVER touched.  Nullifiers in a dropped batch were *)
(* never finalised, so they may legitimately be respent afterwards.          *)
Reorg ==
    /\ pending # <<>>
    /\ \E j \in 0 .. (Len(pending) - 1) :
         pending' = SubSeq(pending, 1, j)
    /\ UNCHANGED finalized

Next == SubmitBatch \/ Finalize \/ Reorg

Spec == Init /\ [][Next]_vars

(*****************************************************************************)
(* INVARIANTS -- the logic we are checking.                                  *)
(*****************************************************************************)

TypeOK ==
    /\ Len(pending) <= K
    /\ \A i \in 1..Len(finalized) : finalized[i] \in BoundedBatch
    /\ \A i \in 1..Len(pending)   : pending[i]   \in BoundedBatch

(* THE CLAIM.  No nullifier is inserted by two distinct FINALISED            *)
(* transitions: the finalised ledger contains no double-spend.  (Transient   *)
(* duplicates between a pending branch and a reorged-away branch do NOT      *)
(* count -- only the finalised order is the ledger.)                         *)
NoDoubleSpend ==
    \A i, j \in 1..Len(FinalTxns) :
        (i # j) => (FinalTxns[i] \cap FinalTxns[j] = {})

(* The same property as a chaining statement (clause 4 form): every          *)
(* finalised transition's inputs are non-members of the accumulator built    *)
(* from all strictly-earlier finalised transitions.                         *)
ChainContinuity ==
    \A i \in 1..Len(FinalTxns) :
        FinalTxns[i] \cap AccOf(SubSeq(FinalTxns, 1, i - 1)) = {}

(* The accumulator never shrinks as the finalised log grows. *)
Monotonic ==
    \A i \in 1..Len(finalized) :
        AccOf(Flatten(SubSeq(finalized, 1, i - 1)))
            \subseteq AccOf(Flatten(SubSeq(finalized, 1, i)))

(* Even the live tip (finalised ++ pending) is duplicate-free, because every *)
(* admitted batch chained against it.  A reorg can never leave a dup behind. *)
NoDoubleSpendTip ==
    LET ts == Flatten(finalized \o pending) IN
    \A i, j \in 1..Len(ts) : (i # j) => (ts[i] \cap ts[j] = {})

=============================================================================
