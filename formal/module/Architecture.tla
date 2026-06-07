-------------------------- MODULE Architecture --------------------------
(***************************************************************************)
(* Architecture -- the multi-node operation and latest-state selection      *)
(* state machine (spec Sec. 6.3 / 6.6 at docs@ed7fdece, spec-v1.1).         *)
(*                                                                         *)
(* THE CLAIMS modelled here (Requirement 4 + Requirement 10):              *)
(*  - "At least one honest node" correctness (Sec. 6.3, Sec. 6.6 bullet 2):*)
(*    a thin client that fans a query out to several nodes keeps every     *)
(*    VERIFYING answer and may ignore the rest; correctness holds as long  *)
(*    as >= 1 arQueried node is honest.                                      *)
(*  - F12 latest-state selection (Sec. 6.3 "Selecting the latest state"):  *)
(*    among verifying answers pick the highest send_counter whose anchoring *)
(*    BatchInscription is `completed`; with no completed candidate the      *)
(*    wallet MAY extend the highest-counter `pending` one (reorg risk).     *)
(*  - F12 fork-halt: two verifying answers at the SAME send_counter with    *)
(*    DIFFERENT new_account_state_hash are an account fork; the wallet MUST *)
(*    NOT sign a further transition (the protocol picks no fork-winner).    *)
(*  - Node portability (Sec. 6.3 / Requirement 10): a wallet depends on no *)
(*    node-specific state, so it MAY switch nodes by configuration alone    *)
(*    with no migration step -- captured structurally (see NoLockIn).      *)
(*  - `completed` is absolute (Sec. 6.6 "Bitcoin reorg bound", <= 5-block  *)
(*    bound, ReorgWithinBound): a reorg never demotes a completed anchor.   *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly):                     *)
(*  - HONESTY = TRUTHFULNESS-OR-OMISSION. By A1 (KnowledgeSound) a          *)
(*    dishonest node CANNOT forge a valid recursive proof / AggregateBatch- *)
(*    Proof / on-chain BatchInscription, and the wallet re-verifies every   *)
(*    answer against Bitcoin (Sec. 6.2). So a dishonest node is modelled as *)
(*    pure OMISSION: it either returns a truthful snapshot or withholds.    *)
(*    There is no "forged but verifying" answer in the reachable space --   *)
(*    that is exactly what KnowledgeSound rules out, so it is not a state.  *)
(*  - A snapshot is a (send_counter, ash, anchor) triple. ash is the        *)
(*    AccountState value itself (Foundations AshEq / A17), so "different     *)
(*    ash" is value inequality. anchor in {pending, completed} is the       *)
(*    Sec. 3.10 lifecycle state of the snapshot's anchoring BatchInscription.*)
(*  - The TRUE lineage is a single monotone chain of arSnapshots (the SPEND   *)
(*    holder's honest history): exactly one ash per send_counter. An        *)
(*    account FORK is injected by the adversary as a SECOND ash at an        *)
(*    already-used counter; it stands in for "same seed driven from two     *)
(*    wallet instances" or a SPEND-branch custody breach (Sec. 6.3).        *)
(*  - Eclipse (Sec. 6.6 inherited assumption, A13): not weakened/strengthened*)
(*    here -- every honest node shares the one true chain view, so honest    *)
(*    answers never diverge among themselves. Divergence among VERIFYING    *)
(*    answers therefore only ever arises from sync lag (different counters) *)
(*    or an injected fork (same counter, different ash) -- the two cases     *)
(*    Sec. 6.3 enumerates.                                                  *)
(*                                                                         *)
(* OUT OF SCOPE here (modelled elsewhere / later phases): the on-chain      *)
(* accumulator advance (Onchain), proof contents (Proofs), the view-grant   *)
(* capability gate (Access). This module is the wallet-side selection logic *)
(* over already-verified answers.                                          *)
(***************************************************************************)
EXTENDS Integers, Foundations, Assumptions

(***************************************************************************)
(* New type aliases for this module.                                       *)
(*  $nodeSnapshot -- what one node holds for the account: a send_counter,   *)
(*    the ash (account state) at that counter, the lifecycle anchor of its  *)
(*    anchoring BatchInscription, and `honest` (truthful vs omitting).      *)
(*  $answer -- what a node returns to a fanned-out query: its snapshot plus *)
(*    `verifies` (the wallet's client-side Bitcoin re-verification outcome).*)
(***************************************************************************)
\* @typeAlias: nodeSnapshot = { counter: Int, ash: $accountState, anchor: Str, honest: Bool };
\* @typeAlias: answer = { node: Int, snap: $nodeSnapshot, verifies: Bool };
Architecture_typedefs == TRUE

CONSTANTS
  \* @type: Set(Int);
  Nodes,            \* finite set of node identities (small instances, <= 3)
  \* @type: Int;
  Owner,            \* the account this wallet controls (address = H(Pk0))
  \* @type: Int;
  Pk0               \* the account's genesis SPEND pubkey (current_pubkey at counter 0)

\* Lifecycle states of an anchoring BatchInscription (Sec. 3.10).
\* @type: () => Str;
Pending == "pending"
\* @type: () => Str;
Completed == "completed"

VARIABLES
  \* @type: Int -> $nodeSnapshot;
  arSnapshots,        \* per-node held snapshot (its possibly-stale-but-valid view)
  \* @type: $accountState;
  arTrueState,        \* the true latest account state of the honest SPEND lineage
  \* @type: Int;
  arTrueCounter,      \* send_counter of arTrueState (monotone non-decreasing)
  \* @type: Str;
  arTrueAnchor,       \* lifecycle anchor of arTrueState's BatchInscription
  \* @type: Set(Int);
  arQueried,          \* nodes the wallet has fanned the current query out to
  \* @type: Bool;
  arForkInjected,     \* an account fork (equivocation) has been planted
  \* @type: Bool;
  arHalted,           \* wallet detected a fork and MUST NOT sign further (F12)
  \* @type: $accountState;
  arSelected,         \* the state the wallet arSelected as authoritative "latest"
  \* @type: Bool;
  arHasSelected       \* whether `arSelected` is meaningful (a selection has run)

\* @type: <<Int -> $nodeSnapshot, $accountState, Int, Str, Set(Int), Bool, Bool, $accountState, Bool>>;
arVars == << arSnapshots, arTrueState, arTrueCounter, arTrueAnchor, arQueried,
           arForkInjected, arHalted, arSelected, arHasSelected >>

(***************************************************************************)
(* Helpers.                                                                *)
(***************************************************************************)

\* The empty / genesis account state (Sec. 2.2 canonical empty account).
\* @type: () => $accountState;
GenesisState == CanonicalEmptyAccount(Owner, Pk0)

\* A node's answer to the current query: it returns its snapshot, and the
\* wallet's client-side Bitcoin re-verification (Sec. 6.2) accepts it iff the
\* node is honest. A dishonest node forges nothing (A1) -- it omits, modelled
\* as `verifies = FALSE` (the wallet ignores it).
\* @type: (Int) => $answer;
AnswerOf(n) ==
  [ node |-> n, snap |-> arSnapshots[n], verifies |-> arSnapshots[n].honest ]

\* The verifying answers among the arQueried nodes (the wallet keeps these and
\* MAY ignore all others, Sec. 6.3 "keep the answer that verifies").
\* @type: () => Set($answer);
VerifyingAnswers ==
  { AnswerOf(n) : n \in { m \in arQueried : arSnapshots[m].honest } }

\* Verifying answers whose anchor is `completed` (the F12 selection candidates).
\* @type: () => Set($answer);
CompletedCandidates ==
  { a \in VerifyingAnswers : a.snap.anchor = Completed }

\* The set of send_counters present among a set of answers.
\* @type: (Set($answer)) => Set(Int);
CountersOf(A) == { a.snap.counter : a \in A }

\* Highest counter present in a non-empty answer set.
\* @type: (Set($answer)) => Int;
MaxCounter(A) ==
  CHOOSE c \in CountersOf(A) : \A d \in CountersOf(A) : d <= c

\* Fork test (F12): two VERIFYING answers at the SAME send_counter but with
\* DIFFERENT ash (AshEq false). Equivocation the SPEND holder could only
\* produce by error or custody breach (Sec. 6.3); the wallet MUST halt.
\* @type: () => Bool;
ForkAmongVerifying ==
  \E a, b \in VerifyingAnswers :
     /\ a.snap.counter = b.snap.counter
     /\ ~ AshEq(a.snap.ash, b.snap.ash)

(***************************************************************************)
(* Init.                                                                   *)
(***************************************************************************)

\* Every node starts holding the genesis snapshot (counter 0, completed,
\* honest); the true lineage is at genesis. No query has run; no fork.
ArInit ==
  /\ arSnapshots = [ n \in Nodes |->
       [ counter |-> 0, ash |-> GenesisState, anchor |-> Completed, honest |-> TRUE ] ]
  /\ arTrueState = GenesisState
  /\ arTrueCounter = 0
  /\ arTrueAnchor = Completed
  /\ arQueried = {}
  /\ arForkInjected = FALSE
  /\ arHalted = FALSE
  /\ arSelected = GenesisState
  /\ arHasSelected = FALSE

(***************************************************************************)
(* Actions.                                                                *)
(***************************************************************************)

\* The honest SPEND lineage advances one transition: a new ash at the next
\* send_counter, freshly anchored `pending` (Sec. 3.10). The owner is fixed
\* (one account); the new state differs at least in sendCounter, so distinct
\* counters carry distinct ash by construction (no spurious fork).
\* @type: () => Bool;
AdvanceTrue ==
  /\ ~ arHalted
  /\ LET nc == arTrueCounter + 1
         ns == [ arTrueState EXCEPT !.sendCounter = nc ]
     IN /\ arTrueState' = ns
        /\ arTrueCounter' = nc
        /\ arTrueAnchor' = Pending
  /\ UNCHANGED << arSnapshots, arQueried, arForkInjected, arHalted, arSelected, arHasSelected >>

\* The true state's anchor crosses the 6-confirmation threshold: pending ->
\* completed (Sec. 3.9). Once completed it is absolute (handled in Reorg).
\* @type: () => Bool;
ConfirmTrue ==
  /\ arTrueAnchor = Pending
  /\ arTrueAnchor' = Completed
  /\ UNCHANGED << arSnapshots, arTrueState, arTrueCounter, arQueried,
                  arForkInjected, arHalted, arSelected, arHasSelected >>

\* A node SYNCS: an honest node copies the current true lineage tip (its view
\* converges to the canonical chain, A13 eclipse-resistance -- all honest nodes
\* share one chain view). Stale nodes simply have not synced yet, giving the
\* lower-counter verifying answers Sec. 6.3 attributes to sync lag.
\* @type: () => Bool;
SyncNode ==
  /\ \E n \in Nodes :
       /\ arSnapshots[n].honest
       /\ arSnapshots' = [ arSnapshots EXCEPT ![n] =
            [ counter |-> arTrueCounter, ash |-> arTrueState,
              anchor |-> arTrueAnchor, honest |-> TRUE ] ]
  /\ UNCHANGED << arTrueState, arTrueCounter, arTrueAnchor, arQueried,
                  arForkInjected, arHalted, arSelected, arHasSelected >>

\* A node turns DISHONEST: it will withhold (omit) rather than serve truth.
\* It CANNOT forge a verifying answer (A1 KnowledgeSound), so dishonesty is
\* exactly `verifies = FALSE`. Modelled as flipping `honest`.
\* @type: () => Bool;
CorruptNode ==
  /\ \E n \in Nodes :
       /\ arSnapshots[n].honest
       /\ arSnapshots' = [ arSnapshots EXCEPT ![n].honest = FALSE ]
  /\ UNCHANGED << arTrueState, arTrueCounter, arTrueAnchor, arQueried,
                  arForkInjected, arHalted, arSelected, arHasSelected >>

\* INJECT AN ACCOUNT FORK (Sec. 6.3 equivocation): plant, on some honest node,
\* a SECOND verifying snapshot at the same send_counter as the true tip but
\* with a DIFFERENT ash. Stands in for the same seed driven from two wallet
\* instances against stale state, or a SPEND-branch custody breach. The node
\* still "verifies" because each branch is individually proof-valid on-chain;
\* the contradiction is only visible by COMPARING the two answers (F12).
\* @type: () => Bool;
InjectFork ==
  /\ ~ arForkInjected
  /\ arTrueCounter >= 1
  /\ \E n \in Nodes :
       /\ arSnapshots[n].honest
       /\ arSnapshots[n].counter = arTrueCounter
       /\ LET forkAsh == [ arTrueState EXCEPT !.currentPk = Pk0 + 1 ]
          IN arSnapshots' = [ arSnapshots EXCEPT ![n] =
               [ counter |-> arTrueCounter, ash |-> forkAsh,
                 anchor |-> arSnapshots[n].anchor, honest |-> TRUE ] ]
  /\ arForkInjected' = TRUE
  /\ UNCHANGED << arTrueState, arTrueCounter, arTrueAnchor, arQueried,
                  arHalted, arSelected, arHasSelected >>

\* A reorg of < 6 blocks (ReorgWithinBound, Sec. 6.6) demotes a node snapshot's
\* anchor from completed to pending ONLY when it is NOT the absolute true tip:
\* a `completed` true anchor is never reverted (Sec. 6.6 "stays completed").
\* @type: () => Bool;
ArReorg ==
  /\ \E n \in Nodes :
       /\ arSnapshots[n].anchor = Completed
       /\ ~ ( arSnapshots[n].counter = arTrueCounter /\ arTrueAnchor = Completed )
       /\ arSnapshots' = [ arSnapshots EXCEPT ![n].anchor = Pending ]
  /\ UNCHANGED << arTrueState, arTrueCounter, arTrueAnchor, arQueried,
                  arForkInjected, arHalted, arSelected, arHasSelected >>

\* The wallet FANS A QUERY OUT to a non-empty set of nodes (Sec. 6.3 "querying
\* several"). Resets any prior selection -- a fresh fan-out re-selects.
\* @type: () => Bool;
Query ==
  /\ \E S \in SUBSET Nodes :
       /\ S # {}
       /\ arQueried' = S
  /\ arHasSelected' = FALSE
  /\ UNCHANGED << arSnapshots, arTrueState, arTrueCounter, arTrueAnchor,
                  arForkInjected, arHalted, arSelected >>

\* The wallet SELECTS the authoritative latest state from the verifying
\* answers (F12, Sec. 6.3):
\*  - if a fork is present (same counter, different ash) -> HALT, never sign;
\*  - else if any completed candidate exists -> highest-counter completed;
\*  - else (no completed) -> highest-counter pending (MAY extend, reorg risk);
\*  - else (no verifying answer at all) -> nothing to select.
\* @type: () => Bool;
Select ==
  /\ arQueried # {}
  /\ ~ arHalted
  /\ IF ForkAmongVerifying
       THEN /\ arHalted' = TRUE
            /\ UNCHANGED << arSelected, arHasSelected >>
       ELSE IF CompletedCandidates # {}
         THEN \E a \in CompletedCandidates :
                /\ a.snap.counter = MaxCounter(CompletedCandidates)
                /\ arSelected' = a.snap.ash
                /\ arHasSelected' = TRUE
                /\ UNCHANGED arHalted
         ELSE IF VerifyingAnswers # {}
           THEN \E a \in VerifyingAnswers :
                  /\ a.snap.counter = MaxCounter(VerifyingAnswers)
                  /\ arSelected' = a.snap.ash
                  /\ arHasSelected' = TRUE
                  /\ UNCHANGED arHalted
           ELSE UNCHANGED << arSelected, arHasSelected, arHalted >>
  /\ UNCHANGED << arSnapshots, arTrueState, arTrueCounter, arTrueAnchor,
                  arQueried, arForkInjected >>

ArNext ==
  \/ AdvanceTrue
  \/ ConfirmTrue
  \/ SyncNode
  \/ CorruptNode
  \/ InjectFork
  \/ ArReorg
  \/ Query
  \/ Select

ArSpec == ArInit /\ [][ArNext]_arVars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

\* @type: (Str) => Bool;
AnchorOK(an) == an = Pending \/ an = Completed

\* Field-level shape check per node. The record TYPES are pinned by the
\* `@type` annotations and the $nodeSnapshot alias; TypeOK adds the model-level
\* domain facts Apalache cannot read off a type alone (anchor in the two-state
\* lifecycle, counters non-negative, the account owner fixed to this account).
\* It avoids `\in [Nodes -> [...]]` set membership, whose `balances` field would
\* force enumerating an Int-indexed function set.
\* @type: () => Bool;
ArTypeOK ==
  /\ DOMAIN arSnapshots = Nodes
  /\ \A n \in Nodes :
       /\ arSnapshots[n].counter >= 0
       /\ AnchorOK(arSnapshots[n].anchor)
       /\ arSnapshots[n].ash.owner = Owner
  /\ arTrueState.owner = Owner
  /\ arTrueCounter >= 0
  /\ AnchorOK(arTrueAnchor)
  /\ arQueried \subseteq Nodes
  /\ arForkInjected \in BOOLEAN
  /\ arHalted \in BOOLEAN
  /\ arHasSelected \in BOOLEAN

(***************************************************************************)
(* PHASE-2 INVARIANTS (stated now, certified later; only TypeOK smokes).   *)
(***************************************************************************)

\* OneHonestSuffices (Requirement 4 / Sec. 6.3 "at least one honest node"):
\* after a selection in which >= 1 arQueried node is honest AND in sync with the
\* true completed tip, and no fork was detected, the wallet arSelected the TRUE
\* latest completed state. (>= 1 honest in-sync answer is the precondition the
\* spec names; without client-side verification more nodes would not help.)
\* @type: () => Bool;
ArOneHonestSuffices ==
  ( /\ arHasSelected
    /\ ~ arHalted
    /\ arTrueAnchor = Completed
    /\ \E n \in arQueried :
         /\ arSnapshots[n].honest
         /\ arSnapshots[n].counter = arTrueCounter
         /\ AshEq(arSnapshots[n].ash, arTrueState)
         /\ arSnapshots[n].anchor = Completed )
  => AshEq(arSelected, arTrueState)

\* ForkHalts (F12): if two verifying answers equivocate at one counter, the
\* wallet, once it has arSelected, is arHalted -- it MUST NOT sign further.
\* @type: () => Bool;
ArForkHalts ==
  ( arHasSelected /\ ForkAmongVerifying ) => arHalted

\* NoLockIn (Requirement 10 / Sec. 6.3 node portability): a wallet depends on
\* NO node-specific state -- every selection is a pure function of the verifying
\* answers and the true chain, never of WHICH nodes were arQueried. So the wallet
\* MAY switch nodes by configuration alone with no migration step. Structural:
\* `arSelected` is derived solely from snapshot CONTENTS (counter/ash/anchor),
\* not node identity; re-querying a different in-sync honest set yields the same
\* selection. Stated as an operator-level fact rather than a reachability inv.
\* @type: () => Bool;
ArNoLockIn ==
  \A n1, n2 \in Nodes :
     ( arSnapshots[n1] = arSnapshots[n2] ) => ( AnswerOf(n1).snap = AnswerOf(n2).snap )

(***************************************************************************)
(* Constant initialiser (Apalache --cinit) for small instances (<= 3       *)
(* nodes, Sec. 6.3 / 6.6 examples). The selection logic is uniform in the   *)
(* node count -- it ranges over answer CONTENTS, not identities -- so a      *)
(* three-node universe exercises the fan-out, fork, and sync-lag cases.     *)
(***************************************************************************)
\* @type: () => Bool;
ArConstInit ==
  /\ Nodes = { 1, 2, 3 }
  /\ Owner = 100
  /\ Pk0 = 200

=============================================================================
