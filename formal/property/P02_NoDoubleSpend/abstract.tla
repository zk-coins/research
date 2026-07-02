-------------------------- MODULE abstract --------------------------
(***************************************************************************)
(* P02 -- No-Double-Spend (abstract accumulator level).                     *)
(*                                                                         *)
(* Phase-0 deliverable of the zkCoins 100% Logical Verification Initiative: *)
(* the legacy bounded TLC model `FirstSpendWins.tla` (Bound = 5) ported to  *)
(* Apalache and verified UNBOUNDED via an inductive invariant -- a smoke    *)
(* test that the toolchain proves a state-machine safety property over the  *)
(* whole (length-unbounded) reachable state space, not just a fixed depth.  *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P2, HIGH):                              *)
(*   No coin is ever double-spent -- no nullifier is admitted into the      *)
(*   global accumulator a second time while it is already present. A        *)
(*   finalised (`completed`) spend is unique and absolute.                  *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (spec-v1.1 baseline ed7fdece, = b6972b8     *)
(* + docs#46/#47/#48; the on-chain accumulator clauses are unchanged by #47): *)
(*   - On-chain Sec. 3.6/3.7 -- the global nullifier accumulator advances   *)
(*     one `prev_root -> new_root` transition per admitted BatchInscription;*)
(*     the AggregateBatchProof attests new_root = SMT.insert_many(prev_root,*)
(*     batch_nullifiers). The load-bearing first-spend-wins rule modelled   *)
(*     here is the in-circuit obligation that every batch nullifier is a    *)
(*     NON-MEMBER of prev_root (the [GATE] in `Admit`), together with the   *)
(*     sequential prev_root continuity that serialises admissions.          *)
(*   - On-chain Sec. 3.9/3.10 -- the 6-confirmation finality threshold and  *)
(*     the three-state lifecycle. The accumulator absorbs every admitted    *)
(*     (bundle-verified) batch -- `pending` union `completed` -- not only   *)
(*     `completed` ones, so double-spend protection takes effect at         *)
(*     admission while receivers credit only on completion.                 *)
(*   - Architecture Sec. 6.6 -- the <= 5-block reorg bound: `completed`     *)
(*     (depth >= 6) never reorgs out, modelled by `Reorg` touching only     *)
(*     `pending`.                                                           *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly):                     *)
(*   A1 (axiom). Nullifier injectivity: nf = Hc("Nullifier", nk || id) is   *)
(*      injective, so a nullifier IS the coin identity -- distinct coins ->  *)
(*      distinct nullifiers (set membership = double-spend test).           *)
(*   A15/A16 (axioms). The AggregateBatchProof's SMT-insertion and          *)
(*      half-aggregation obligations hold as ideal functionalities; the     *)
(*      accumulator is modelled as the abstract set of admitted nullifiers  *)
(*      (its SMT root is collision-bound to that set under A16). What stays  *)
(*      in scope here is the SET-LEVEL admission discipline, which is what   *)
(*      P2 depends on.                                                      *)
(*   Out of scope for this Phase-0 smoke test (modelled fully in            *)
(*   module/Onchain.tla + the Phase-3 P02 certificate): the BatchInscription*)
(*   byte format, prev_root continuity races, the pending-due-to-DA         *)
(*   sub-state, and the `mint-verified` status. None affect the abstract    *)
(*   accumulator-level invariant proven here.                              *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP: delete the conjunct marked [GATE] in       *)
(* `Admit` and re-run -- Apalache returns a double-spend counterexample     *)
(* (`doubled` becomes non-empty). With the gate, NoDoubleSpend and the      *)
(* inductive invariant hold for the whole unbounded state space. (See       *)
(* notes.md for the recorded negative run.)                                 *)
(***************************************************************************)
EXTENDS Integers

CONSTANT
  \* @type: Set(Int);
  Nullifier                 \* finite universe of nullifiers (= coins, by A1)

VARIABLES
  \* @type: Set(Int);
  pending,                  \* admitted, < 6 confirmations (may reorg out)
  \* @type: Set(Int);
  completed,                \* admitted, >= 6 confirmations (absolute, Architecture Sec. 6.6)
  \* @type: Set(Int);
  doubled                   \* evidence: nullifiers an admitted batch re-inserted while present

\* @type: <<Set(Int), Set(Int), Set(Int)>>;
vars == << pending, completed, doubled >>

\* The live accumulator: the nf set behind the current `new_root`
\* (On-chain Sec. 3.7). A batch sees this as its `prev_root` contents.
\* @type: () => Set(Int);
Acc == pending \union completed

Init ==
  /\ pending = {}
  /\ completed = {}
  /\ doubled = {}

\* Admit one publisher batch carrying the nullifier set B (On-chain Sec. 3.6).
\* [GATE] = the AggregateBatchProof's non-membership obligation: every batch
\* nullifier is absent from prev_root (= Acc). `doubled` is written first so
\* that DELETING the gate makes a re-spent nullifier observable.
Admit ==
  /\ \E B \in SUBSET Nullifier :
       /\ B # {}
       /\ doubled'   = doubled \union (B \intersect Acc)   \* {} under the gate
       /\ B \intersect Acc = {}                            \* [GATE] first-spend-wins
       /\ pending'   = pending \union B
       /\ completed' = completed

\* Some pending nullifiers cross the 6-confirmation threshold (On-chain Sec. 3.9).
Confirm ==
  /\ \E M \in SUBSET pending :
       /\ M # {}
       /\ completed' = completed \union M
       /\ pending'   = pending \ M
       /\ doubled'   = doubled

\* Bitcoin reorg drops some pending nullifiers (their batch orphaned). `completed`
\* is never touched -- depth >= 6 does not reorg out under the <= 5-block bound,
\* so `completed` is absolute (On-chain Sec. 3.10, Architecture Sec. 6.6).
Reorg ==
  /\ \E D \in SUBSET pending :
       /\ D # {}
       /\ pending'   = pending \ D
       /\ completed' = completed
       /\ doubled'   = doubled

Next == Admit \/ Confirm \/ Reorg

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

\* @type: () => Bool;
TypeOK ==
  /\ pending   \subseteq Nullifier
  /\ completed \subseteq Nullifier
  /\ doubled   \subseteq Nullifier

\* THE SAFETY CLAIM: no nullifier is ever double-spent.
\* @type: () => Bool;
NoDoubleSpend == doubled = {}

\* Structural: a nullifier is pending OR completed, never both.
\* @type: () => Bool;
ZonesDisjoint == pending \intersect completed = {}

\* Inductive strengthening sufficient to close the proof for the unbounded
\* state space. NoDoubleSpend alone is inductive; ZonesDisjoint is carried
\* because it is the structural fact the (richer) on-chain model relies on.
\* @type: () => Bool;
IndInv ==
  /\ TypeOK
  /\ ZonesDisjoint
  /\ NoDoubleSpend

\* Assignment-friendly restatement of IndInv, used as the --init predicate of
\* the inductive-step check (Apalache requires every variable to be ASSIGNED
\* in an init predicate; `\subseteq` is not an assignment form). Syntactically
\* equivalent to IndInv: `x \in SUBSET S` iff `x \subseteq S`, and
\* `doubled = {}` iff NoDoubleSpend (which also implies doubled \subseteq
\* Nullifier).
\* @type: () => Bool;
IndInvInit ==
  /\ pending \in SUBSET Nullifier
  /\ completed \in SUBSET Nullifier
  /\ doubled = {}
  /\ pending \intersect completed = {}

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). The inductive argument is      *)
(* uniform in |Nullifier|: every conjunct of IndInv is per-nullifier local *)
(* and every action preserves it independently of the universe size. A     *)
(* small finite universe therefore certifies the general result; notes.md  *)
(* records a confirming run at a larger size.                              *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit == Nullifier = 1..6

=============================================================================
