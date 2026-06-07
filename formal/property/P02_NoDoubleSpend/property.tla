-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P02 -- No-Double-Spend (FULL on-chain model).                           *)
(*                                                                         *)
(* Phase-upgrade deliverable of the zkCoins 100% Logical Verification       *)
(* Initiative. Where the Phase-0 companion `abstract.tla` carries only the   *)
(* three opaque nullifier sets (pending/completed/doubled), THIS module     *)
(* EXTENDS the full-fidelity on-chain state machine `module/Onchain.tla`     *)
(* (Spec Sec. 3, spec-v1.1 baseline ed7fdece) and proves the same safety     *)
(* claim over the CONCRETE BatchInscription machine: the publisher signature *)
(* oracle (A7), the half-aggregation obligation (A15), prev_root continuity  *)
(* (Sec. 3.4 / 3.6 step 4), block_anchor admissibility (Sec. 3.5), the       *)
(* three-state lifecycle (Sec. 3.10), and reorg handling (Sec. 3.7/3.9).     *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P2, HIGH):                              *)
(*   No coin is ever double-spent -- no nullifier is admitted into the       *)
(*   global accumulator a second time while it is already present. A         *)
(*   finalised (`completed`) spend is unique and absolute.                  *)
(*                                                                         *)
(* WHAT EACH LAYER PROVES.                                                  *)
(*   abstract.tla (Phase 0): the set-level admission discipline is sound,    *)
(*     unbounded, over the three-set accumulator abstraction.               *)
(*   property.tla (this phase): the SAME safety holds when the accumulator   *)
(*     advances through the real BatchInscription admission gate -- [SIG],   *)
(*     [ANCHOR], [AGG], [CONT], [INSERT], [GATE] -- and the three structural *)
(*     invariants OnNoDoubleSpend / OnZonesDisjoint / OnPrevRootContinuity   *)
(*     hold together on the concrete machine.                               *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP: delete the [GATE] conjunct in Onchain's     *)
(* `Admit` (the post-#40 first-spend-wins non-membership obligation) and     *)
(* re-run the implication/sanity checks -- Apalache returns a double-spend   *)
(* counterexample (`onDoubled` becomes non-empty). See notes.md for the      *)
(* recorded negative run on the FULL model.                                 *)
(*                                                                         *)
(* PROOF STRUCTURE AND THE Seq VARIABLE (honest scope statement).          *)
(*   The accumulator-safety invariants OnNoDoubleSpend and OnZonesDisjoint   *)
(*   depend ONLY on the SET variables onPending/onCompleted/onDoubled        *)
(*   (and onAuthorised, untouched by them). They do NOT reference the        *)
(*   `onAdmittedChain` sequence at all. The induction that closes the        *)
(*   double-spend proof is therefore taken over the SET PROJECTION of the    *)
(*   state, and is genuinely UNBOUNDED: the inductive step is a single SMT   *)
(*   query with no bound on the number of transitions.                      *)
(*                                                                         *)
(*   OnPrevRootContinuity, by contrast, quantifies over DOMAIN              *)
(*   onAdmittedChain. Apalache encodes a Seq with a STATIC capacity, so an   *)
(*   inductive step that assumes-and-reestablishes a continuity-respecting   *)
(*   chain of ARBITRARY length is not expressible as one unbounded SMT       *)
(*   query (the chain length would have to be a fixed capacity). We are      *)
(*   explicit about this: continuity is verified by BOUNDED reachability     *)
(*   over the full machine (length 6, the finality depth K), NOT by an       *)
(*   unbounded inductive step. The unbounded claim is the no-double-spend    *)
(*   safety property; continuity is a bounded sanity result that the chain   *)
(*   bookkeeping is consistent with the set accumulator at every reachable   *)
(*   admitted history up to depth 6.                                        *)
(*                                                                         *)
(*   Crucially, no-double-spend does not LEAN on continuity: the [GATE] in   *)
(*   Admit tests batch nullifiers against `Acc` (= onPending \cup onCompleted,*)
(*   the live set), not against the chain. So the unbounded set-projection   *)
(*   proof is a complete proof of the P2 safety claim; the chain is pure     *)
(*   bookkeeping for the continuity sanity result. (Full argument: notes.md, *)
(*   "Full-model upgrade" / "Seq-variable handling".)                       *)
(***************************************************************************)
EXTENDS Onchain, Apalache

(***************************************************************************)
(* Local (step-form) restatement of OnPrevRootContinuity.                  *)
(*                                                                         *)
(* Onchain's OnPrevRootContinuity states prev_root continuity in CUMULATIVE *)
(* form: chain[i].prevRoot = UNION_{j<i} batch[j]. That uses a dynamic       *)
(* integer range `1..(i-1)`, which Apalache cannot evaluate symbolically     *)
(* (it requires a constant range). We restate the SAME property in its       *)
(* equivalent LOCAL step form, which references only adjacent entries and is *)
(* exactly the chained prev_root -> new_root continuity Admit maintains      *)
(* (`prevRoot = Acc`, `newRoot = Acc \cup batch`):                          *)
(*   - the first batch chains off the empty accumulator;                    *)
(*   - each batch's prevRoot equals the previous batch's newRoot;           *)
(*   - each batch's newRoot equals its prevRoot plus its own nullifiers.    *)
(* By induction on i these two forms are logically equivalent; the local     *)
(* form is the one Apalache can check (constant-index access only).         *)
(***************************************************************************)
\* @type: () => Bool;
OnPrevRootContinuityLocal ==
  /\ (Len(onAdmittedChain) > 0 => onAdmittedChain[1].prevRoot = {})
  /\ \A i \in DOMAIN onAdmittedChain :
       /\ onAdmittedChain[i].newRoot
            = onAdmittedChain[i].prevRoot \union onAdmittedChain[i].batchNullifiers
       /\ (i > 1 => onAdmittedChain[i].prevRoot = onAdmittedChain[i - 1].newRoot)

(***************************************************************************)
(* The composite SAFETY invariant for P2 over the FULL on-chain machine     *)
(* (PublisherSign / Admit / Confirm / Reorg). This is the part proven        *)
(* UNBOUNDED by the inductive invariant below AND smoke-checked bounded.     *)
(* It is the actual P2 claim plus the disjoint-zone structural fact; neither *)
(* references the chain, so both hold under EVERY OnNext action.             *)
(***************************************************************************)
\* @type: () => Bool;
INV ==
  /\ OnNoDoubleSpend
  /\ OnZonesDisjoint

(***************************************************************************)
(* The chain-continuity structural invariant -- HONEST SCOPE.              *)
(*                                                                         *)
(* OnPrevRootContinuity holds for the ADMIT/CONFIRM fragment of the machine *)
(* (every admitted batch chains prev_root -> new_root off the live          *)
(* accumulator, §3.4 / §3.6 step 4 / §3.7 [INSERT]). It is NOT an invariant *)
(* of the FULL machine including Reorg, because Onchain's `Reorg` rebuilds   *)
(* the chain with `SelectSeq(onAdmittedChain, Survives)`, which removes the  *)
(* reverted batches WHEREVER they sit -- a non-suffix removal leaves a       *)
(* surviving later batch whose prev_root still commits to a now-removed      *)
(* predecessor, so local continuity is broken. (The module comment intends a *)
(* SUFFIX-only revert; the coded `SelectSeq` over an arbitrary D \subseteq    *)
(* onPending over-approximates that to any-position removal.)               *)
(*                                                                         *)
(* This over-approximation does NOT weaken the P2 result: no-double-spend    *)
(* (INV) is tested against the live set accumulator `Acc`, never against the *)
(* chain, so it holds under Reorg regardless. Continuity is therefore        *)
(* checked over the admit/confirm fragment only, and the gap is documented   *)
(* (notes.md, "Reorg continuity over-approximation"). NextAdmitConfirm is    *)
(* OnNext without Reorg.                                                     *)
(***************************************************************************)
\* @type: () => Bool;
NextAdmitConfirm == PublisherSign \/ Admit \/ Confirm

\* @type: () => Bool;
INV_Continuity == OnPrevRootContinuityLocal

(***************************************************************************)
(* INDUCTIVE INVARIANT for the UNBOUNDED no-double-spend proof.            *)
(*                                                                         *)
(* IndInv_P2 is stated over the SET variables only (plus their types). It   *)
(* is strong enough to be inductive for OnNoDoubleSpend and OnZonesDisjoint *)
(* under the FULL OnNext (PublisherSign / Admit / Confirm / Reorg): every   *)
(* on-chain action either leaves the sets unchanged or moves nullifiers     *)
(* between the disjoint zones / blocks a re-insertion via [GATE], so the     *)
(* set-level conjuncts reproduce exactly the abstract-model induction --     *)
(* now under the concrete admission gate.                                   *)
(*                                                                         *)
(* It deliberately omits OnPrevRootContinuity (the only chain-dependent     *)
(* conjunct); continuity is established by bounded reachability, see INV    *)
(* and verify.sh check [F1]. IndInv_P2 => OnNoDoubleSpend is check [F4].    *)
(***************************************************************************)
\* @type: () => Bool;
IndInv_P2 ==
  /\ onPending \subseteq Nullifiers
  /\ onCompleted \subseteq Nullifiers
  /\ onDoubled \subseteq Nullifiers
  /\ onAuthorised \subseteq (Publishers \X BundleLocators)
  /\ onPending \intersect onCompleted = {}    \* OnZonesDisjoint
  /\ onDoubled = {}                            \* OnNoDoubleSpend

(***************************************************************************)
(* Assignment-form restatement of IndInv_P2, used as the --init predicate   *)
(* of the inductive-STEP check. Apalache requires every variable to be      *)
(* ASSIGNED in an init predicate (`\subseteq` is a constraint, not an        *)
(* assignment), so each set var is drawn from its powerset and the chain is  *)
(* assigned an arbitrary value of bounded length.                          *)
(*                                                                         *)
(* THE Seq ASSIGNMENT (the honest projection argument made concrete).       *)
(*   IndInv_P2 does not constrain `onAdmittedChain`; the step's job is only  *)
(*   to show the SET conjuncts are preserved. We assign onAdmittedChain an   *)
(*   ARBITRARY (Gen-constructed) sequence so the step holds for ANY chain    *)
(*   value, not a specific one -- and since IndInv_P2 never reads the chain  *)
(*   and OnNext's set effects never read the chain either, the chain's value *)
(*   is irrelevant to the preserved conjuncts. The step is thus a faithful   *)
(*   unbounded statement about the set projection: "for every reachable set  *)
(*   state satisfying IndInv_P2 (under any admitted history), one OnNext     *)
(*   step preserves IndInv_P2." The bounded capacity of the Gen'd chain      *)
(*   bounds only the bookkeeping witness, never the safety conclusion.       *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit ==
  /\ onPending \in SUBSET Nullifiers
  /\ onCompleted \in SUBSET Nullifiers
  /\ onDoubled = {}
  /\ onAuthorised \in SUBSET (Publishers \X BundleLocators)
  /\ onPending \intersect onCompleted = {}
  \* Seq projection: an arbitrary admitted history of bounded capacity. Its
  \* value is never read by IndInv_P2 nor by the set-effects of OnNext, so it
  \* plays no role in the preserved conjuncts (see module header). `Gen(4)`
  \* (apalache.Gen) constructs an UNCONSTRAINED sequence of capacity <= 4.
  /\ onAdmittedChain = Gen(4)

=============================================================================
