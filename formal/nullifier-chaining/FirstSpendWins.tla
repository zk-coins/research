-------------------------- MODULE FirstSpendWins --------------------------
(*****************************************************************************)
(* A LOGIC-LEVEL specification of zkCoins' first-spend-wins discipline       *)
(* over the Bitcoin anchor, matching the post-`zk-coins/docs#21` and #25     *)
(* design. It validates ONE claim of the protocol idea, independent of any   *)
(* implementation:                                                           *)
(*                                                                           *)
(*   "Given that every node admits a `SpendRecord` only when its published    *)
(*    nullifiers are disjoint from the locally-rebuilt accumulator           *)
(*    (On-chain §3.6 step 6), and Bitcoin produces no canonical reorgs       *)
(*    deeper than 5 blocks (Architecture §6.6), no coin is ever spent twice  *)
(*    in the finalised ledger -- and double-spend protection takes effect    *)
(*    at admission, not at finality."                                        *)
(*                                                                           *)
(* GROUNDED IN THE SPECIFICATION:                                            *)
(*   - On-chain §3.5 / §3.6 -- the admission predicate (parser, block_anchor *)
(*     bounds, signature, nullifier-`inr` binding, canonical order, and the  *)
(*     load-bearing rule modelled here: first-spend-wins, §3.6 step 6).      *)
(*   - On-chain §3.7 -- the global nullifier accumulator, rebuilt by every   *)
(*     node from the chain alone.                                            *)
(*   - On-chain §3.9 -- the 6-confirmation finality threshold (and the       *)
(*     "no reorgs deeper than 5 blocks" assumption).                         *)
(*   - On-chain §3.10 -- the three-state transaction lifecycle               *)
(*     (`pending` / `completed` / `failed`); the accumulator absorbs every   *)
(*     ADMITTED record (pending ∪ completed), not only completed ones --     *)
(*     so double-spend protection takes effect at admission, while receivers *)
(*     credit only on completion.                                            *)
(*   - Architecture §6.6 -- the Bitcoin reorg-bound assumption.              *)
(*                                                                           *)
(* COMPARED TO THE EARLIER MODEL (`NullifierChaining.tla`, removed):         *)
(* That model encoded the per-batch `prev_root → post_root` chaining of the  *)
(* pre-#21 design. #21 dropped that mechanism entirely -- the spent          *)
(* nullifiers are now published IN THE CLEAR on Bitcoin, and every node      *)
(* rebuilds the accumulator first-spend-wins from the chain. The claim       *)
(* (no double-spend) is the same; the mechanism is far simpler, and so is    *)
(* this model: no claimed roots, no `Chains` predicate, no aggregator.       *)
(*                                                                           *)
(* MODELLING ASSUMPTIONS (deliberate abstractions, stated openly):           *)
(*                                                                           *)
(*   A1. Nullifier injectivity. `nf = Hc("Nullifier", nk ‖ coin.identifier)` *)
(*       is injective, so we let the nullifier BE the coin identity:         *)
(*       distinct coins -> distinct nullifiers.                              *)
(*                                                                           *)
(*   A2. Thin Bitcoin anchor. Bitcoin is modelled as nothing more than an    *)
(*       append-only, totally-ordered log of admitted `SpendRecord`s. Reorgs *)
(*       drop AT MOST `K - 1` records from the tail (the assumption from     *)
(*       Architecture §6.6 + On-chain §3.9 -- "no canonical reorgs deeper    *)
(*       than 5 blocks", with `K = 6` confirmations as the finality          *)
(*       threshold). No Script, no UTXO, no mining.                          *)
(*                                                                           *)
(*   A3. The §3.5+§3.6 admission predicate, except for first-spend-wins,     *)
(*       is folded into the proposer's freedom: a record `r` is just an      *)
(*       arbitrary non-empty set of nullifiers, and the model lets any       *)
(*       proposer attempt to admit any such record. The other admission      *)
(*       checks (signature validity, block_anchor bounds, nullifier-`inr`    *)
(*       binding, structural parsing) reject ill-formed records but do not   *)
(*       affect the nullifier-set logic this model verifies, so they are     *)
(*       abstracted away.                                                    *)
(*                                                                           *)
(* TO SEE THE MODEL CHECKER EARN ITS KEEP: delete the conjunct marked        *)
(* [GATE] in `Admit` (the first-spend-wins disjoint-check) and re-run TLC.   *)
(* It returns a finalised double-spend trace within seconds. With the        *)
(* conjunct, `NoDoubleSpend` holds for the whole bounded state space.        *)
(*****************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS
    Nullifier,   \* finite set of possible nullifiers (= coins, by A1)
    K,           \* finality depth (= 6 in zkCoins per On-chain §3.9)
    Bound        \* state-space bound on log length

ASSUME K \in Nat /\ K >= 1
ASSUME Bound \in Nat /\ Bound >= 1

VARIABLE log    \* Seq of admitted SpendRecords in canonical Bitcoin order

vars == << log >>

(* A SpendRecord publishes a non-empty set of input nullifiers.
   (A mint publishes an empty list; mints cannot trigger double-spend
   conflicts, so they are omitted from this model.) *)
Record == { S \in SUBSET Nullifier : S # {} }

(* Running accumulator over a sequence of records: the union of every
   admitted record's nf set. Bound by FiniteSet semantics for FiniteSets. *)
RECURSIVE Acc(_)
Acc(s) == IF s = <<>> THEN {} ELSE Head(s) \cup Acc(Tail(s))

(* Pending-zone size: the verifier-local interpretation of §3.10 places the
   last `K - 1` records in the `pending` state (depth < K). Anything earlier
   is `completed` (depth >= K). The completed prefix is immutable per A2. *)
PendingMax(L) == IF K - 1 <= L THEN K - 1 ELSE L

Init == log = <<>>

(* ---- Actions ---- *)

(* Admit a new record onto the canonical Bitcoin log. The proposer is
   UNRESTRICTED -- it may pick ANY non-empty nf set, including an
   adversarial one that reuses an already-spent nullifier. ValidNext is
   the §3.6 step 6 gate that must reject double-spends. *)
Admit ==
    /\ Len(log) < Bound
    /\ \E r \in Record :
         /\ r \cap Acc(log) = {}              \* [GATE] first-spend-wins
         /\ log' = Append(log, r)

(* Bitcoin reorg: drop a non-empty suffix of the pending zone. The
   completed prefix is NEVER touched -- under A2, records at depth >= K
   do not reorg out. Records dropped here are pending records whose
   nullifiers re-enter the pool (a legitimate respend after reorg is
   then possible). *)
Reorg ==
    /\ Len(log) > 0
    /\ \E n \in 1..PendingMax(Len(log)) :
         log' = SubSeq(log, 1, Len(log) - n)

Next == Admit \/ Reorg

Spec == Init /\ [][Next]_vars

(*****************************************************************************)
(* INVARIANTS -- the logic we are checking.                                  *)
(*****************************************************************************)

TypeOK ==
    /\ Len(log) <= Bound
    /\ \A i \in 1..Len(log) : log[i] \in Record

(* THE CLAIM. No nullifier appears in two distinct records of the current
   canonical log. Because completed records (depth >= K) NEVER reorg out
   under A2, this also implies the stronger property "no two records ever
   classified `completed` share an nf" -- the `completed` state is
   absolute under the protocol's reorg-bound assumption (§3.10).         *)
NoDoubleSpend ==
    \A i, j \in 1..Len(log) :
        (i # j) => (log[i] \cap log[j] = {})

(* Equivalent restatement: every record's nfs were FRESH with respect to
   the accumulator at the moment of admission. (This is the §3.6 step 6
   semantics traced through the canonical order, and equivalently the
   "admission gates the accumulator" sentence in §3.10.) *)
AdmissionFreshness ==
    \A i \in 1..Len(log) :
        log[i] \cap Acc(SubSeq(log, 1, i - 1)) = {}

=============================================================================
