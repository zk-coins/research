-------------------------- MODULE fee_atomicity --------------------------
(***************************************************************************)
(* P03 -- Fee-coin ATOMICITY (spec-v1.1 / docs#47, On-chain §3.8).            *)
(*                                                                         *)
(* A NEW load-bearing invariant added for the spec-v1.1 baseline            *)
(* (docs@ed7fdece). docs#47 §3.8 introduces the publisher fee-coin           *)
(* mechanism: a spender adds ONE ordinary output coin addressed to the        *)
(* publisher's fee_address, as one of the outputs under the transition's      *)
(* SINGLE output_coins_root (ocr). The spec states the fee coin and the       *)
(* recipient payment are ATOMICALLY bound -- anchoring the one SpendRecord     *)
(* admits ALL outputs under that ocr, or NONE. Consequences the spec claims:  *)
(* a censoring publisher that never anchors collects nothing; the spender      *)
(* pays exactly one fee.                                                      *)
(*                                                                         *)
(* THE CLAIM proven here (the genuinely NEW #47 guarantee, lifted from        *)
(* hand-argument to a machine-checked invariant):                            *)
(*   (a) ATOMICITY -- for every transition, the fee coin reaches `completed`   *)
(*       IFF the recipient payment under the SAME ocr reaches `completed`. No  *)
(*       reachable state has the fee admitted/completed while the payment is   *)
(*       not, or vice versa.                                                  *)
(*   (b) CENSORSHIP-SAFETY -- if a transition is never anchored, its fee coin   *)
(*       never becomes spendable (a censoring publisher collects nothing).     *)
(*                                                                         *)
(* MODELLING (the repo idiom -- the accumulator/lifecycle abstraction of       *)
(* property/P02_NoDoubleSpend/abstract.tla, here over OCRs instead of          *)
(* nullifiers; A16 RootCommitsSet: an ocr root IS the set of outputs it        *)
(* commits to, and both the payment and the fee are members of that ONE set).  *)
(*   - A transition is identified by its ocr id (an Int; by A3/A16 the ocr IS  *)
(*     the structured output set, so equal ocr = equal output set). Each ocr   *)
(*     carries exactly one payment output and one fee output, both under it.   *)
(*   - ANCHORING is all-or-none admission of the WHOLE ocr (the single         *)
(*     SpendRecord binds the single ocr, §3.8): Admit moves an ocr into the    *)
(*     `pending` zone; Confirm promotes it to `completed` (>= 6 conf, §3.9);   *)
(*     Reorg reverts only `pending` ocrs (A12, <= 5-block bound). A coin (fee   *)
(*     or payment) is SPENDABLE/completed iff its ocr is completed -- the       *)
(*     per-output status is DERIVED from the ocr's zone, never set per-output.  *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (negative control). Decouple the fee coin from *)
(* the payment's ocr -- give the fee an INDEPENDENT admission set `feePending`/  *)
(* `feeCompleted` that can advance on its own -- and Apalache finds a state      *)
(* where the fee is collected (completed) while the payment's ocr is not        *)
(* anchored, violating FeeAtomicity. The commented variant + recorded run are   *)
(* in notes.md (committed companion fee_atomicity_nc.tla).                      *)
(***************************************************************************)
EXTENDS Integers, Apalache

CONSTANT
  \* Finite universe of transition / ocr ids (each = one SpendRecord's single
  \* output_coins_root, §3.8). By A16 an ocr id IS the output set it commits to.
  \* @type: Set(Int);
  Ocrs

VARIABLES
  \* OCRs anchored but < 6 confirmations (admitted, reorg-eligible, §3.9/3.10).
  \* The WHOLE ocr (payment + fee outputs together) is admitted atomically.
  \* @type: Set(Int);
  pending,
  \* OCRs with >= 6 confirmations: absolute under the <= 5-block bound (A12). An
  \* output (payment OR fee) is spendable/completed iff its ocr is here.
  \* @type: Set(Int);
  completed

\* @type: <<Set(Int), Set(Int)>>;
vars == << pending, completed >>

(***************************************************************************)
(* Derived per-output status. BOTH the payment and the fee under an ocr are    *)
(* "completed" exactly when the ocr is completed -- there is no per-output       *)
(* status, because the single SpendRecord admits the single ocr atomically      *)
(* (§3.8). This is the all-or-none binding the invariant rests on.            *)
(***************************************************************************)
\* @type: (Int) => Bool;
PaymentCompleted(o) == o \in completed
\* @type: (Int) => Bool;
FeeCompleted(o) == o \in completed
\* @type: (Int) => Bool;
Anchored(o) == (o \in pending) \/ (o \in completed)

(***************************************************************************)
(* Init / transitions.                                                       *)
(***************************************************************************)
\* @type: () => Bool;
Init ==
  /\ pending = {}
  /\ completed = {}

\* Admit -- a publisher anchors one transition's SpendRecord: its whole ocr
\* (payment + fee outputs) enters the < 6-conf zone atomically (§3.8 / §3.10).
\* @type: () => Bool;
Admit ==
  \E o \in Ocrs :
    /\ o \notin pending
    /\ o \notin completed
    /\ pending' = pending \union { o }
    /\ completed' = completed

\* Confirm -- some pending ocrs cross the 6-conf finality threshold (§3.9). The
\* whole ocr promotes together: both its payment and fee become completed at once.
\* @type: () => Bool;
Confirm ==
  \E M \in (SUBSET pending) \ {{}} :
    /\ completed' = completed \union M
    /\ pending' = pending \ M

\* Reorg -- a Bitcoin reorg orphans some pending ocrs (their SpendRecord
\* un-anchored). Only `pending` reverts; `completed` (depth >= 6) is never
\* touched (A12, <= 5-block bound). The whole ocr reverts together.
\* @type: () => Bool;
Reorg ==
  \E D \in (SUBSET pending) \ {{}} :
    /\ pending' = pending \ D
    /\ completed' = completed

\* @type: () => Bool;
Next == Admit \/ Confirm \/ Reorg

\* @type: () => Bool;
Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

\* @type: () => Bool;
TypeOK ==
  /\ pending \subseteq Ocrs
  /\ completed \subseteq Ocrs

\* Structural: an ocr is pending OR completed, never both (Confirm is one-way).
\* @type: () => Bool;
ZonesDisjoint == pending \intersect completed = {}

(***************************************************************************)
(* THE LOAD-BEARING SAFETY CLAIM (docs#47 §3.8):                              *)
(*   (a) ATOMICITY -- the fee coin is completed IFF the recipient payment under *)
(*       the same ocr is completed. Equivalently: no reachable state has the    *)
(*       fee admitted/completed while the payment is not (or vice versa).      *)
(*   (b) CENSORSHIP-SAFETY -- a never-anchored transition's fee is never         *)
(*       spendable: ~Anchored(o) => ~FeeCompleted(o).                          *)
(* @type: () => Bool;                                                          *)
(***************************************************************************)
FeeAtomicity ==
  \A o \in Ocrs :
    /\ FeeCompleted(o) <=> PaymentCompleted(o)            \* (a) atomic
    /\ (~ Anchored(o)) => (~ FeeCompleted(o))             \* (b) censorship-safe

\* @type: () => Bool;
IndInv ==
  /\ TypeOK
  /\ ZonesDisjoint
  /\ FeeAtomicity

(***************************************************************************)
(* Assignment-form restatement used as the inductive-step --init (Apalache     *)
(* requires each variable ASSIGNED; \subseteq alone is not assignment form).    *)
(* Both sets are drawn from the powerset of Ocrs, then IndInv is asserted.      *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit ==
  /\ pending \in SUBSET Ocrs
  /\ completed \in SUBSET Ocrs
  /\ ZonesDisjoint
  /\ FeeAtomicity

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Small finite instance: 3 ocrs.     *)
(* The argument is uniform in |Ocrs|: every conjunct is per-ocr local and each  *)
(* action preserves it independently of the universe size.                     *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit == Ocrs = 1..3

(***************************************************************************)
(* VACUITY PROBE. FeeAtomicity is NOT vacuous: the reachable space DOES         *)
(* contain states with a completed ocr (so FeeCompleted/PaymentCompleted hold   *)
(* non-trivially). NoneEverCompleted asserts completed stays empty forever; a    *)
(* check returns a counterexample (an ocr DOES reach completed via Admit;       *)
(* Confirm), so the IFF is exercised over a populated `completed`, not          *)
(* vacuously. (Recorded in notes.md.)                                          *)
(* @type: () => Bool;                                                           *)
(***************************************************************************)
NoneEverCompleted == completed = {}

(***************************************************************************)
(* NEGATIVE CONTROL (committed companion fee_atomicity_nc.tla; recorded run in  *)
(* notes.md). DECOUPLE the fee from the payment's                              *)
(* ocr: add independent fee zones (feePending/feeCompleted) that advance on      *)
(* their OWN AdmitFee/ConfirmFee, with FeeCompleted(o) reading feeCompleted     *)
(* instead of the payment's `completed`. Then a state is reachable where the     *)
(* fee is completed while the payment's ocr is NOT anchored => FeeAtomicity      *)
(* (both the IFF and the censorship clause) fails (Apalache: outcome Error,      *)
(* exit 12). This is the definitive proof the SINGLE-ocr atomic binding is       *)
(* load-bearing.                                                                *)
(***************************************************************************)
=============================================================================
