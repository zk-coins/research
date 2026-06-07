-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P01 -- No-Forgery (mints excluded; covered by P07).                      *)
(*                                                                         *)
(* Phase-0/1 deliverable of the zkCoins 100% Logical Verification          *)
(* Initiative. A coin can be credited only as the proven output of a        *)
(* Sec. 2.1-compliant transition SIGNED by the account that created it.     *)
(*                                                                         *)
(* This package is two-tier (see notes.md "Two-tier result"):              *)
(*                                                                         *)
(*  TIER 1 -- INV_Provenance: the STRUCTURAL no-forgery core, proven         *)
(*    UNBOUNDED via the 3-check inductive pattern over the per-account       *)
(*    compliance-predicate machine PrInit/PrNext in `module/Proofs.tla`.     *)
(*    Every coin id in any account's coin-history was produced as the output *)
(*    of THAT account's OWN Sec. 2.1-compliant transition -- the coin id     *)
(*    structurally embeds the creating prior account state (Foundations      *)
(*    MkCoinId's prevAsh), and its owner is pinned to the holder. This       *)
(*    invariant is `prAuthorised`-free, so its inductive argument is sound   *)
(*    for the genuinely unbounded reachable state space (the signature       *)
(*    oracle prAuthorised grows without bound; an invariant that ENUMERATED  *)
(*    it could not be Gen-represented at all reachable depths -- see          *)
(*    notes.md). UNBOUNDED here means: holds in EVERY reachable state, for    *)
(*    an arbitrary number of MintStep/SendStep transitions.                  *)
(*                                                                         *)
(*  TIER 2 -- INV_NoForgery: the full SIGNATURE-LEVEL statement -- every      *)
(*    credited coin is the SIGNED output of a compliant transition, under     *)
(*    the key current in its creating account state. Proven as a BOUNDED      *)
(*    safety check. Its unbounded extension reduces to TIER 1 plus the        *)
(*    model's honest-oracle lockstep construction (MintStep / SendStep grow   *)
(*    prAuthorised in step with prChSet, signing under the account's own      *)
(*    current key), whose load-bearing role the negative control confirms.    *)
(*                                                                         *)
(* THE CLAIM (M4 ground truth -- Pass-3 audit P1, HIGH for the spec design): *)
(*   "A coin c with c.recipient = R, c.amount = v, c.asset_id = a can exist  *)
(*    only as the proven output of a Sec. 2.1-compliant transition signed by *)
(*    some account's sk_i. A PPT adversary without sk_i for that account, and *)
(*    without breaking A1, A5, A7, cannot cause an honest receiver to credit  *)
(*    c."                                                                     *)
(*   Game: A wins if there exists a coin c that an honest receiver credits,   *)
(*   but c was NOT produced by a valid Sec. 2.1 transition.                   *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (baseline docs@ed7fdece, spec-v1.1):       *)
(*   - Foundations Sec. 1.4 -- coin.identifier = Hc("Coin",                    *)
(*     prev_account_state_hash || asset_id || coin_index): the coin id         *)
(*     STRUCTURALLY EMBEDS its creating prior account state (MkCoinId's        *)
(*     prevAsh). A coin therefore carries the identity of the account state    *)
(*     that produced it -- provenance is recovered from existing state, no      *)
(*     ghost ledger needed (TIER 1 reads only prChSet + the coin structure).   *)
(*   - Proofs Sec. 2.1 clause 5 -- every output coin id is                     *)
(*     MkCoinId(prev_account_state, asset, idx): prevAsh = the creating prev   *)
(*     state. clause 7 -- new_account_state.owner unchanged; with PrInit's     *)
(*     canonical empty account this pins owner = AddressOf(account).           *)
(*   - Proofs Sec. 2.1 clause 2 -- input authenticity: txn_sig valid under     *)
(*     txn_pubkey = prev_account_state.current_pubkey over the message         *)
(*     (input_nullifiers_root || output_coins_root). This is the A7 oracle     *)
(*     PrSigValid / prAuthorised that TIER 2 references.                       *)
(*   - On-chain Sec. 2.4 / Sec. 3.6 -- the publisher path: a forged coin       *)
(*     cannot be laundered onto the chain (covered by P02 admission [AGG];     *)
(*     see notes.md "Composition / scope").                                    *)
(*                                                                         *)
(* HOW THE MODEL REALISES THE CLAIM. The A7 oracle prAuthorised grows ONLY    *)
(* when an account's own current key signs its own transition message         *)
(* (MintStep / SendStep each add exactly                                      *)
(* <<prev.currentPk, PrMsgTag(NullifierSet(w), OutputIds(w))>>); a forged      *)
(* authorisation is never present and signatures are never removed. Every coin *)
(* id that enters an account's coin-history prChSet is an OutId(prev, t, k)    *)
(* whose prevAsh = the creating prev state (clause 5) and which lies in that   *)
(* transition's OutputIds = the signed message's ocr. So every held coin       *)
(* traces back to a compliant, signed transition of the account that created   *)
(* it -- which is No-Forgery.                                                  *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (negative control). Letting the adversary      *)
(* credit a coin without a matching honest signature -- breaking the           *)
(* prChSet/prAuthorised lockstep -- makes INV_NoForgery FAIL with an Apalache  *)
(* counterexample. See notes.md (run in a /tmp copy; this committed model      *)
(* keeps the honest oracle intact).                                           *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, Apalache, Foundations, Assumptions, Proofs

(***************************************************************************)
(* TIER 1 -- the structural no-forgery core (proven UNBOUNDED).             *)
(*                                                                         *)
(* prChSet[acct] is the abstract per-account coin-history key set -- the set  *)
(* of coin ids the account holds/credits (clause 2b membership / clause 8     *)
(* update, A16/RootCommitsSet). A coin is "credited" iff its id is in some    *)
(* prChSet[acct]. The structural claim: every credited coin id was the output *)
(* of its HOLDER's own Sec. 2.1-compliant transition.                        *)
(*                                                                         *)
(* The witness is the coin id itself: MkCoinId embeds the creating prior      *)
(* account state in cid.prevAsh, and clause 7 pins owner across the lineage,  *)
(* so cid.prevAsh.owner = AddressOf(acct) says exactly "the account that      *)
(* created this coin is the account that now holds it". Only a C-valid        *)
(* MintStep/SendStep of account `acct` ever adds a coin whose prevAsh.owner   *)
(* is acct's address (MintStep/SendStep build OutId over prState[acct], whose *)
(* owner = AddressOf(acct)); no other account, and no adversary action, can   *)
(* introduce such a coin. A forged coin -- one no compliant transition of its  *)
(* holder ever output -- would have prevAsh.owner # AddressOf(acct), violating *)
(* the invariant.                                                            *)
(*                                                                         *)
(* This invariant reads only prChSet and the coin-id structure -- never the    *)
(* signature oracle prAuthorised -- so per the maxima probe (notes.md) its     *)
(* state is bounded (|prChSet[a]| <= 1) and the inductive argument is sound    *)
(* for the unbounded reachable space (whereas |prAuthorised| grows without     *)
(* bound and could not be Gen-represented at every depth).                    *)
(***************************************************************************)

\* @type: () => Bool;
INV_Provenance ==
  \A acct \in Accounts :
    \A cid \in prChSet[acct] :
      \* the coin's creating account state is owned by the holder: the coin was
      \* the output of the holder's OWN compliant transition (clause 5 builds
      \* OutId over prState[acct]; clause 7 pins owner across key rotations).
      cid.prevAsh.owner = AddressOf(acct)

(***************************************************************************)
(* TIER 2 -- the full signature-level statement (proven BOUNDED; unbounded   *)
(* extension documented in notes.md).                                        *)
(*                                                                         *)
(* SignedOutputs is the flat (signerKey, coinId) relation every honest        *)
(* signature in prAuthorised attests: each signature <<k, PrMsgTag(inr,ocr)>> *)
(* contributes <<k, cid>> for every output coin cid in ocr. INV_NoForgery     *)
(* then says: every credited coin is a signed output under the key current in *)
(* its own creating account state (cid.prevAsh.currentPk; clause 2:           *)
(* txn_pubkey = prev.current_pubkey). No coin can be credited that no          *)
(* compliant signed transition ever output. This is the strongest form of the *)
(* claim; it is checked BOUNDED because it reads the unbounded prAuthorised.   *)
(***************************************************************************)

\* @type: () => Set(<<Int, $coinId>>);
SignedOutputs ==
  UNION { { <<sig[1], cid>> : cid \in sig[2].ocr } : sig \in prAuthorised }

\* @type: () => Bool;
INV_NoForgery ==
  \A acct \in Accounts :
    \A cid \in prChSet[acct] :
      << cid.prevAsh.currentPk, cid >> \in SignedOutputs

(***************************************************************************)
(* Vacuity probe. Both invariants quantify over `cid \in prChSet[acct]`, so   *)
(* they are trivially true in any state where no account holds a coin. To      *)
(* show the verified verdict is meaningful -- that the model actually CREDITS   *)
(* coins over which the invariants are non-trivial -- we check that            *)
(* NoCoinsEver (no account ever holds a coin) is VIOLATED at depth: a credited *)
(* coin is reachable. verify.sh runs this as check [0] and expects a           *)
(* counterexample.                                                            *)
(***************************************************************************)
\* @type: () => Bool;
NoCoinsEver == \A acct \in Accounts : prChSet[acct] = {}

(***************************************************************************)
(* Inductive strengthening (for TIER 1). INV_Provenance alone is NOT          *)
(* inductive: a fresh account must still be canonical for its first output    *)
(* coin to embed the right owner, and a transitioned account must keep its     *)
(* owner pinned. The same two local strengthenings P07 uses close it:         *)
(*                                                                         *)
(*   S1 (owner pinned).   prState[a].owner = AddressOf(a) for every account    *)
(*       (PrInit + clause 7 owner-invariance).                                 *)
(*   S2 (fresh = canonical). sendCounter = 0  =>  current_pubkey = AddressOf(a) *)
(*       AND balances empty AND coin-history empty (the canonical empty         *)
(*       account; makes the empty-history base case hold and pins the first    *)
(*       output's creating state).                                            *)
(*                                                                         *)
(* PrTypeOK + S1 + S2 + INV_Provenance is closed under PrNext (check [3]).     *)
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
  /\ INV_Provenance

(***************************************************************************)
(* Assignment-form restatement of IndInv, used as the --init predicate of    *)
(* the inductive-step check. Apalache requires every variable ASSIGNED in an  *)
(* init predicate; PrTypeOK (inside IndInv) constrains via membership, not     *)
(* assignment. Each variable is produced by `Gen` (apalache.Gen) -- an          *)
(* UNCONSTRAINED symbolic value of the variable's type -- then pinned by the    *)
(* IndInv body (same idiom as P02/P07). IndInv reads only prState / prChSet,   *)
(* so the small prAuthorised budget here is for type-shape only (it does not   *)
(* affect the TIER-1 argument; see notes.md on why TIER 1 is prAuthorised-     *)
(* free and therefore soundly unbounded).                                     *)
(***************************************************************************)

\* @type: () => Bool;
IndInvInit ==
  /\ prState      = Gen(3)
  /\ prChSet      = Gen(6)
  /\ prAuthorised = Gen(2)
  /\ IndInv

(***************************************************************************)
(* Constant initialiser (Apalache --cinit), reusing the Proofs smoke         *)
(* instance: two accounts, one v1 asset family. The inductive argument is     *)
(* per-account local (each IndInv conjunct quantifies one account at a time    *)
(* and every action touches a single account), so a two-account universe       *)
(* certifies the general result; notes.md records the |Accounts|=3 base/impl   *)
(* re-confirmation.                                                            *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit == PrConstInit

=============================================================================
