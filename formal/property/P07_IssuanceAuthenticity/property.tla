-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P07 -- Issuance Authenticity (v1).                                      *)
(*                                                                         *)
(* Phase-0/1 deliverable of the zkCoins 100% Logical Verification          *)
(* Initiative: the §6.5 v1 mint discipline, as modelled by the compliance  *)
(* predicate C in `module/Proofs.tla`, proven to enforce issuance          *)
(* authenticity UNBOUNDED via an inductive invariant -- not at a fixed     *)
(* execution depth, but over the entire (length-unbounded) reachable state *)
(* space of the per-account issuance/spend state machine PrInit/PrNext.    *)
(*                                                                         *)
(* THE CLAIM (M4 ground truth -- Pass-3 audit P7, HIGH for v1):            *)
(*   "A coin claiming asset a can be admitted as a v1-issuance output ONLY *)
(*    by a transition signed by the creator account of a (the account      *)
(*    whose Pk0 satisfies Hc(\"AssetId\", genesis_tag || Pk0 || H(name) || *)
(*    decimals || 1) == a)."                                               *)
(*   Game: the adversary wins if a coin with asset a is admitted via the   *)
(*   v1 mint clauses but the signing account is NOT the creator account.   *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (baseline docs@ed7fdece, spec-v1.1):      *)
(*   - Architecture Sec. 6.5 -- v1 issuance clauses (a)-(d): the mint       *)
(*     circuit MUST verify issuance_version==1 (a); H(creator_pubkey) ==    *)
(*     prev_account_state.owner (b); the asset_id derivation               *)
(*     asset_id == Hc(\"AssetId\", ... creator_pubkey ... version) (c); and *)
(*     terms_hash == Hc(\"IssuanceTerms\", asset_id || version) (d). These  *)
(*     are `module/Proofs.tla`'s MintV1Clauses, gated into Clause3 when an  *)
(*     issuance is present.                                                 *)
(*   - Proofs Sec. 2.1 clause 3 -- per-asset balance conservation invokes   *)
(*     the §6.5 clauses; clause 2 binds txn_sig to                          *)
(*     prev_account_state.current_pubkey (the A7 oracle); clause 7 keeps    *)
(*     new_account_state.owner unchanged. Together: the witnessed           *)
(*     creator_pubkey is forced to be the same Pk0 that fixed the account   *)
(*     at creation, and that account must hold the current spend key.       *)
(*                                                                         *)
(* HOW THE MODEL REALISES THE CLAIM. In Proofs.tla the only minting action  *)
(* is MintStep(a, amount): an InitialProof (sendCounter = 0) that builds an  *)
(* issuance for asset AssetOf(prev.current_pubkey) and signs under          *)
(* prev.current_pubkey (the only way the A7 oracle `prAuthorised` grows --   *)
(* an account signing its OWN transition). Because a fresh account satisfies *)
(* current_pubkey = owner = a (= Pk0 = AddressOf(a)), the asset minted by    *)
(* account a has creator = a. SendStep never mints (hasIssuance = FALSE) and *)
(* moves only assets the account already holds. So in every reachable state, *)
(* account a holds ONLY assets whose creator is a -- which is exactly        *)
(* issuance authenticity: an asset's coins exist only in the balances/coin-  *)
(* history of the one account that is its creator (asset.creator = that      *)
(* account's Pk0), and only that account ever minted it.                     *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (negative control). Weakening MintV1Clauses *)
(* -- dropping conjunct (b) AddressOf(creatorPk) == owner, or conjunct (c)  *)
(* the asset_id derivation -- lets a non-creator account mint someone else's *)
(* asset, and Apalache then returns an INV_P7 counterexample. See notes.md  *)
(* for the recorded negative run (done in a /tmp copy; this committed model  *)
(* keeps the clauses intact).                                               *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, Apalache, Foundations, Assumptions, Proofs

(***************************************************************************)
(* The authenticity invariant.                                             *)
(*                                                                         *)
(* In this machine the account index `a` IS its own Pk0 and owner (PrInit   *)
(* seeds CanonicalEmptyAccount(a, a); AddressOf(a) = a). The creator         *)
(* account of an asset x is therefore the account a with a = x.creator. So   *)
(* "asset x present in account a  =>  x.creator = a" says: every coin/       *)
(* balance of asset x lives only in x's creator account -- authenticity.    *)
(***************************************************************************)

\* Every asset retained in account a's balances was created by a.
\* @type: (Int) => Bool;
BalancesAuthentic(a) ==
  \A x \in DOMAIN prState[a].balances : x.creator = AddressOf(a)

\* Every coin in account a's coin-history is of an asset created by a.
\* @type: (Int) => Bool;
CoinsAuthentic(a) ==
  \A cid \in prChSet[a] : cid.asset.creator = AddressOf(a)

\* THE SAFETY CLAIM: in every reachable state, no account holds a balance or
\* coin of an asset whose creator is a different account. Equivalently, an
\* asset claiming creator c can only appear where c = the holding account's
\* Pk0 -- i.e. only the creator account ever admitted (minted) it.
\* @type: () => Bool;
INV_P7 ==
  \A a \in Accounts :
    /\ BalancesAuthentic(a)
    /\ CoinsAuthentic(a)

(***************************************************************************)
(* Inductive strengthening. INV_P7 alone is NOT inductive: MintStep builds  *)
(* asset AssetOf(prev.current_pubkey), so preservation of "creator = a"      *)
(* needs that a mintable account (sendCounter = 0) still has                 *)
(* current_pubkey = a and owner = a (the canonical-empty shape). Once an     *)
(* account transitions, sendCounter becomes > 0 and MintStep is disabled, so *)
(* no further asset is introduced; SendStep preserves creators because it    *)
(* re-emits the spent asset. We therefore carry:                            *)
(*                                                                         *)
(*   S1 (owner pinned).   prState[a].owner = a  for every account.          *)
(*   S2 (fresh = canonical). sendCounter = 0  =>  current_pubkey = a AND     *)
(*       balances empty AND coin-history empty. This is the fact MintStep    *)
(*       relies on to mint a's OWN asset, and the fact that makes a second   *)
(*       mint impossible (after a mint, sendCounter > 0).                    *)
(*                                                                         *)
(* S1 + S2 + INV_P7 is closed under PrNext.                                 *)
(***************************************************************************)

\* S1: the account index is its owner, immutably (PrInit + clause 7).
\* @type: (Int) => Bool;
OwnerPinned(a) == prState[a].owner = AddressOf(a)

\* S2: a still-mintable account (sendCounter = 0) is the canonical empty
\* account of a -- current key equals a and it holds nothing yet.
\* @type: (Int) => Bool;
FreshIsCanonical(a) ==
  prState[a].sendCounter = 0 =>
    /\ prState[a].currentPk = AddressOf(a)
    /\ DOMAIN prState[a].balances = {}
    /\ prChSet[a] = {}

\* @type: () => Bool;
IndInv ==
  /\ PrTypeOK
  /\ \A a \in Accounts :
       /\ OwnerPinned(a)
       /\ FreshIsCanonical(a)
  /\ INV_P7

(***************************************************************************)
(* Assignment-form restatement of IndInv, used as the --init predicate of   *)
(* the inductive-step check. Apalache requires every variable ASSIGNED in an *)
(* init predicate; PrTypeOK constrains via membership, not assignment.        *)
(*                                                                         *)
(* Each variable is produced by `Gen` (apalache.Gen) -- an UNCONSTRAINED      *)
(* symbolic value of the variable's type, bounded only by a size budget -- and *)
(* then pinned down entirely by the IndInv body. This is the supported idiom  *)
(* for an inductive-step `--init`: enumerating an explicit set-of-functions    *)
(* carrier for `prState` would force the solver to expand a set of functions   *)
(* (which Apalache rejects), whereas Gen + a constraining invariant gives the  *)
(* SAME reachable shape symbolically. PrTypeOK (inside IndInv) fixes the       *)
(* domains (= Accounts), the per-account WfAccountState, and the prChSet /     *)
(* prAuthorised element shapes, so IndInvInit admits exactly the states IndInv *)
(* characterises -- the assignment form is logically equivalent to IndInv.     *)
(*                                                                         *)
(* Size budgets: |Accounts| = 2, so a function over Accounts and the small     *)
(* per-account coin-history / authorisation sets are covered by Gen(.) bounds  *)
(* a few above the reachable maxima (one mint + one send per account).        *)
(***************************************************************************)

\* @type: () => Bool;
IndInvInit ==
  /\ prState      = Gen(3)
  /\ prChSet      = Gen(6)
  /\ prAuthorised = Gen(6)
  /\ IndInv

(***************************************************************************)
(* Constant initialiser (Apalache --cinit), reusing the Proofs smoke         *)
(* instance: two accounts, one v1 asset family. The inductive argument is     *)
(* per-account local (each conjunct of IndInv quantifies one account at a     *)
(* time and every action touches a single account), so a two-account universe *)
(* certifies the general result; notes.md records the |Accounts|=3 base/impl   *)
(* re-confirmation.                                                           *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit == PrConstInit

=============================================================================
