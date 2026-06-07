-------------------------- MODULE fee_atomicity_nc --------------------------
(* NEGATIVE CONTROL for P03 fee-atomicity.                                     *)
(* Identical to fee_atomicity.tla EXCEPT the fee is DECOUPLED from the          *)
(* payment's ocr: the fee gets its OWN independent zones feePending/feeCompleted *)
(* advanced by its OWN AdmitFee/ConfirmFee, and FeeCompleted(o) reads           *)
(* feeCompleted instead of the payment's `completed`. Then a state is reachable  *)
(* where the fee is completed while the payment's ocr is NOT anchored =>         *)
(* FeeAtomicity fails. Everything else is verbatim.                            *)
EXTENDS Integers, Apalache

CONSTANT
  \* @type: Set(Int);
  Ocrs

VARIABLES
  \* @type: Set(Int);
  pending,
  \* @type: Set(Int);
  completed,
  \* DECOUPLED fee zones (the deleted single-ocr binding): the fee advances
  \* independently of the payment's ocr.
  \* @type: Set(Int);
  feePending,
  \* @type: Set(Int);
  feeCompleted

\* @type: <<Set(Int), Set(Int), Set(Int), Set(Int)>>;
vars == << pending, completed, feePending, feeCompleted >>

\* @type: (Int) => Bool;
PaymentCompleted(o) == o \in completed
\* DECOUPLED: fee status reads its OWN zone, not the payment's ocr.
\* @type: (Int) => Bool;
FeeCompleted(o) == o \in feeCompleted
\* Anchored = the PAYMENT's ocr is anchored (as in the real model).
\* @type: (Int) => Bool;
Anchored(o) == (o \in pending) \/ (o \in completed)

\* @type: () => Bool;
Init ==
  /\ pending = {}
  /\ completed = {}
  /\ feePending = {}
  /\ feeCompleted = {}

\* Admit the PAYMENT's ocr only.
\* @type: () => Bool;
Admit ==
  \E o \in Ocrs :
    /\ o \notin pending
    /\ o \notin completed
    /\ pending' = pending \union { o }
    /\ completed' = completed
    /\ UNCHANGED << feePending, feeCompleted >>

\* @type: () => Bool;
Confirm ==
  \E M \in (SUBSET pending) \ {{}} :
    /\ completed' = completed \union M
    /\ pending' = pending \ M
    /\ UNCHANGED << feePending, feeCompleted >>

\* @type: () => Bool;
Reorg ==
  \E D \in (SUBSET pending) \ {{}} :
    /\ pending' = pending \ D
    /\ completed' = completed
    /\ UNCHANGED << feePending, feeCompleted >>

\* DECOUPLED fee admission: the fee anchors on its OWN, independent of the ocr.
\* @type: () => Bool;
AdmitFee ==
  \E o \in Ocrs :
    /\ o \notin feePending
    /\ o \notin feeCompleted
    /\ feePending' = feePending \union { o }
    /\ UNCHANGED << pending, completed, feeCompleted >>

\* @type: () => Bool;
ConfirmFee ==
  \E M \in (SUBSET feePending) \ {{}} :
    /\ feeCompleted' = feeCompleted \union M
    /\ feePending' = feePending \ M
    /\ UNCHANGED << pending, completed >>

\* @type: () => Bool;
Next == Admit \/ Confirm \/ Reorg \/ AdmitFee \/ ConfirmFee

\* @type: () => Bool;
FeeAtomicity ==
  \A o \in Ocrs :
    /\ FeeCompleted(o) <=> PaymentCompleted(o)
    /\ (~ Anchored(o)) => (~ FeeCompleted(o))

\* @type: () => Bool;
ConstInit == Ocrs = 1..3
=============================================================================
