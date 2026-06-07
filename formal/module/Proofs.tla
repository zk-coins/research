-------------------------- MODULE Proofs --------------------------
(***************************************************************************)
(* Proofs -- the compliance predicate C and the per-account state machine   *)
(* it drives. Models spec Sec. 2.1 (the nine compliance clauses), Sec. 2.2  *)
(* (InitialProof vs AccountUpdateProof, canonical empty account) and the    *)
(* Sec. 6.5 v1 mint clauses that Sec. 2.1 clause 3 invokes, at commit       *)
(* docs@b6972b8 (post docs#40).                                             *)
(*                                                                         *)
(* C(...) is a faithful conjunction of the nine normative clauses. Three    *)
(* places are ABSTRACTED, each with a cited justification:                  *)
(*                                                                         *)
(*  - Coin-history membership (clause 2b). The prior per-account coin-       *)
(*    history SMT is NOT unrolled. Under A16 a Merkle/SMT root is collision- *)
(*    bound to its key set, so membership is an abstract relation: the model *)
(*    carries the set of coin ids the prev state's chRoot commits to, and    *)
(*    clause 2b is `coin.id \in thatSet`. This is exactly the modelling      *)
(*    licence Foundations records (chRoot kept opaque to break the type      *)
(*    cycle) and Assumptions.RootCommitsSet states.                         *)
(*                                                                         *)
(*  - Recursive verification (clause 1, PCD). The prev_proof is NOT a second *)
(*    circuit execution. Under A1 (Plonky2 knowledge-soundness) a verifying  *)
(*    recursive proof attests its statement; Assumptions.KnowledgeSound      *)
(*    lifts `accepts => statement`. We model the statement as "prev_proof    *)
(*    attests prev_account_state" (its public new_account_state_hash equals  *)
(*    ash(prev_account_state)). The InitialProof path instead demands prev   *)
(*    state = CanonicalEmptyAccount. This captures the constant-size,        *)
(*    history-free attestation of Sec. 2.2 without re-executing predecessors.*)
(*                                                                         *)
(*  - Output-coins root (clause 6) and coin-history root (clause 8). Roots   *)
(*    are not Merkle-hashed; under A16/RootCommitsSet a root IS its key set,  *)
(*    so ocr is the SET of output ids and the new chRoot is an opaque handle *)
(*    whose committed set is (prev set minus spent inputs) plus outputs.     *)
(*                                                                         *)
(* The signing oracle A7 (Assumptions.SigValid) is fed by an `authorised`   *)
(* set the state machine grows ONLY when an account's own current key signs  *)
(* its own transition message -- so a forged authorisation is never present. *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, Apalache, Foundations, Assumptions

(***************************************************************************)
(* This module's own record aliases. Shared datatypes ($assetId, $coin, ...) *)
(* are reused verbatim from Foundations; only the witness, the issuance      *)
(* sub-record and the four public-input ProofData fields are introduced here.*)
(***************************************************************************)

\* @typeAlias: prTermsHandle = { asset: $assetId, version: Int };
\* @typeAlias: prMsgHandle = { inr: Set($nullifier), ocr: Set($coinId) };
\* @typeAlias: issuance = { assetId: $assetId, creatorPk: Int, version: Int, nameHash: Int, amount: Int, decimals: Int, termsHash: $prTermsHandle };
\* @typeAlias: proofData = { newAsh: $accountState, ocr: Set($coinId), inr: Set($nullifier), chRoot: Set($coinId) };
\* @typeAlias: witness = { isInitial: Bool, prevProofAccepts: Bool, prevState: $accountState, prevChSet: Set($coinId), prevNewAsh: $accountState, prevCommittedChSet: Set($coinId), inputs: Set($coin), creatingPrevAsh: $coinId -> $accountState, txnSigOk: Bool, txnPk: Int, templates: Seq($coinTemplate), nk: Int, nextPk: Int, hasIssuance: Bool, issuance: $issuance };
Proofs_typedefs == TRUE

(***************************************************************************)
(* Helpers over witness data. The address derivation H(Pk0) = owner is now   *)
(* the shared Foundations.AddressOf (A5/A6 preimage binding, injective).      *)
(***************************************************************************)

\* The transition message the spender signs (SpendRecord message = inr || ocr,
\* Sec. 2.1 clause 2 / Sec. 1.4): BIP-340 over (input_nullifiers_root ||
\* output_coins_root). Modelled as the structured handle over exactly those two
\* public roots (the transition's spent-nullifier set and output-coin id set),
\* kept as the record the A7 oracle keys on. By A3 (Poseidon collision
\* resistance over the concatenation), distinct (inr, ocr) pairs map to distinct
\* handles -- so the signature commits to THIS transition's nullifiers and coins.
\* @type: (Set($nullifier), Set($coinId)) => $prMsgHandle;
PrMsgTag(inr, ocr) == [ inr |-> inr, ocr |-> ocr ]

\* The set of nullifiers derived in this transition (clause 4) and the set of
\* output coin ids (clauses 5/6). Defined up here because clause 2's signed
\* message is (inr || ocr) = (NullifierSet, OutputIds): the SpendRecord binds the
\* clause-4 nullifiers and the clause-6 output coins (Sec. 2.1 clauses 2/4/6).
\* @type: ($witness) => Set($nullifier);
NullifierSet(w) == { MkNullifier(w.nk, c.id) : c \in w.inputs }

\* The output coin id for template index k: identifier binds the PRIOR state's
\* ash, breaking the coin.identifier <-> new_ash recursion (Sec. 2.1 clause 5).
\* @type: ($accountState, $coinTemplate, Int) => $coinId;
OutId(prevState, t, k) == MkCoinId(prevState, t.asset, k)

\* The set of all output coin ids of the transition (clauses 5/6).
\* @type: ($witness) => Set($coinId);
OutputIds(w) ==
  { OutId(w.prevState, w.templates[k], k) : k \in DOMAIN w.templates }

\* @type: (Int, $coin) => Int;
AddCoinAmount(acc, c) == acc + c.amount

\* In(a): total input amount for asset a (clause 3).
\* @type: (Set($coin), $assetId) => Int;
InAmount(inputs, a) ==
  ApaFoldSet(AddCoinAmount, 0, { c \in inputs : c.asset = a })

\* @type: (Int, <<Int, Int>>) => Int;
AddSecond(acc, p) == acc + p[2]

\* Out(a): total output-template amount for asset a (clause 3). Folds over
\* <<index, amount>> pairs (distinct by index, so identical amounts are not
\* deduplicated and the sum stays exact).
\* @type: (Seq($coinTemplate), $assetId) => Int;
OutAmount(templates, a) ==
  ApaFoldSet(AddSecond, 0,
             { <<i, templates[i].amount>> : i \in { j \in DOMAIN templates : templates[j].asset = a } })

\* Mint(a): issuance amount for asset a, zero unless an issuance for a is present.
\* @type: ($witness, $assetId) => Int;
MintAmount(w, a) ==
  IF w.hasIssuance /\ w.issuance.assetId = a THEN w.issuance.amount ELSE 0

\* All asset ids touched by this transition (inputs, outputs, issuance).
\* @type: ($witness) => Set($assetId);
AssetsTouched(w) ==
  { c.asset : c \in w.inputs }
    \union { w.templates[i].asset : i \in DOMAIN w.templates }
    \union (IF w.hasIssuance THEN { w.issuance.assetId } ELSE {})

\* u128 range bound for amounts (clause 3 range check). Kept small for checking;
\* the only property used is non-wrap, so any fixed positive bound suffices.
\* @type: () => Int;
U128Bound == 1000000

(***************************************************************************)
(* Clause-local predicates. Each cites its Sec. 2.1 clause.                  *)
(***************************************************************************)

\* A7 oracle keyed on the structured transition-message handle (FIX 3): the
\* message is (inr || ocr), so the signed pairs are <<pk, $prMsgHandle>>. Same
\* membership content as Assumptions.SigValid, typed for the handle message.
\* @type: (Set(<<Int, $prMsgHandle>>), Int, $prMsgHandle) => Bool;
PrSigValid(authorised, pk, msg) == <<pk, msg>> \in authorised

\* Clause 1 -- recursive verification (PCD), Sec. 2.1 clause 1. InitialProof:
\* no prev proof, prev state IS the canonical empty account for owner = H(Pk0).
\* AccountUpdate: the prev recursive proof verifies and (A1/KnowledgeSound)
\* thereby ATTESTS its statement -- which the spec binds to prev-state fidelity:
\* the prev proof's public new_account_state_hash equals ash(prev_account_state)
\* AND its coin_history_root equals the coin-history root clause 2 proves
\* inclusion against. We carry that prev ProofData in the witness (prevNewAsh,
\* prevCommittedChSet) and make the attested statement bind them, so a verified
\* lineage actually constrains the predecessor rather than being vacuously true.
\* @type: ($witness) => Bool;
Clause1_Recursion(w) ==
  IF w.isInitial
  THEN /\ ~w.prevProofAccepts
       /\ AshEq(w.prevState, CanonicalEmptyAccount(w.prevState.owner, w.prevState.currentPk))
  ELSE /\ w.prevProofAccepts
       \* A1: accepting prev proof attests its statement -- prev-state fidelity:
       \* its new_account_state_hash = ash(prevState) AND its coin_history_root
       \* commits to the set clause 2(b) proves inclusion against (prevChSet).
       /\ KnowledgeSound(w.prevProofAccepts,
                         /\ AshEq(w.prevNewAsh, w.prevState)
                         /\ RootCommitsSet(w.prevCommittedChSet, w.prevChSet))

\* Clause 2 -- input authenticity. txn_sig valid (A7 oracle) under txn_pubkey =
\* prev.current_pubkey over the transition message; and per input coin:
\*  a. recipient = prev.owner (ownership is by account);
\*  b. coin in the prior coin-history set (A16 abstract membership, prevChSet);
\*  c. identifier recomputed via MkCoinId(creating_prev_ash, asset, idx) and
\*     equal to the supplied identifier (a mismatch is a Poseidon collision, A3).
\* @type: (Set(<<Int, $prMsgHandle>>), $witness) => Bool;
Clause2_Inputs(authorised, w) ==
  /\ w.txnPk = w.prevState.currentPk
  /\ w.txnSigOk
  \* FIX 3 / Sec. 2.1 clause 2: txn_sig is BIP-340 over message = inr || ocr,
  \* i.e. (NullifierSet(w), OutputIds(w)) -- the transition's spent nullifiers
  \* and output coins -- under txn_pubkey = prev.current_pubkey.
  /\ PrSigValid(authorised, w.txnPk, PrMsgTag(NullifierSet(w), OutputIds(w)))
  /\ \A c \in w.inputs :
       /\ c.recipient = w.prevState.owner
       /\ c.id \in w.prevChSet
       /\ c.id \in DOMAIN w.creatingPrevAsh
       /\ c.id = MkCoinId(w.creatingPrevAsh[c.id], c.asset, c.id.idx)

\* terms_hash = Hc("IssuanceTerms", asset_id || issuance_version) (Sec. 6.5 (d)).
\* FIX 4: a STRUCTURED handle over the whole (asset_id, version), so it commits
\* to the complete asset_id -- including name_hash and decimals -- not a lossy
\* creator+version sum. By A3 distinct (asset_id, version) map to distinct
\* handles, the collision-freedom the recomputation relies on.
\* @type: ($assetId, Int) => $prTermsHandle;
TermsHash(asset, version) == [ asset |-> asset, version |-> version ]

\* Sec. 6.5 v1 mint clauses (a)-(d), invoked by clause 3 when issuance present.
\* @type: ($witness) => Bool;
MintV1Clauses(w) ==
  LET is == w.issuance IN
  /\ is.version = IssuanceVersionV1                                   \* (a)
  /\ AddressOf(is.creatorPk) = w.prevState.owner                      \* (b)
  /\ is.assetId = MkAssetId(is.creatorPk, is.nameHash, is.decimals, is.version)  \* (c)
  /\ is.termsHash = TermsHash(is.assetId, is.version)                 \* (d) structured Hc("IssuanceTerms", asset_id || version)

\* Clause 3 -- per-asset balance conservation. For every touched asset:
\* In(a)+Mint(a) >= Out(a); all amounts range-checked [0, U128Bound]. When an
\* issuance is present the four Sec. 6.5 v1 clauses must hold.
\* @type: ($witness) => Bool;
Clause3_Balance(w) ==
  /\ \A c \in w.inputs : c.amount >= 0 /\ c.amount < U128Bound
  /\ \A i \in DOMAIN w.templates : w.templates[i].amount >= 0 /\ w.templates[i].amount < U128Bound
  /\ (w.hasIssuance => (w.issuance.amount >= 0 /\ w.issuance.amount < U128Bound))
  /\ \A a \in AssetsTouched(w) : InAmount(w.inputs, a) + MintAmount(w, a) >= OutAmount(w.templates, a)
  /\ (w.hasIssuance => MintV1Clauses(w))

\* Clause 4 -- nullifier derivation: nf = MkNullifier(nk, input.id); the nf are
\* pairwise distinct. Distinct input ids give distinct nf for a fixed nk (A3);
\* the requirement is therefore |inputs| many distinct nullifiers.
\* @type: ($witness) => Bool;
Clause4_Nullifiers(w) ==
  Cardinality(NullifierSet(w)) = Cardinality(w.inputs)

\* Clause 5 -- output coin construction. The constructed ids are exactly the
\* MkCoinId values; nothing to assert beyond OutputIds being well-defined, which
\* it is by construction. Kept as a named TRUE so the clause is traceable.
\* @type: ($witness) => Bool;
Clause5_Outputs(w) ==
  \A k \in DOMAIN w.templates : OutId(w.prevState, w.templates[k], k).prevAsh = w.prevState

\* Clause 6 -- output_coins_root = root over output ids. Under A16 the root IS
\* the set of output ids (RootCommitsSet): ProofData.ocr must equal OutputIds.
\* @type: ($witness, $proofData) => Bool;
Clause6_Ocr(w, pd) == RootCommitsSet(pd.ocr, OutputIds(w))

\* The post-transition coin-history key set (clause 8 result): inputs marked
\* spent (removed) and outputs admitted (added). Abstract SMT update under A16.
\* @type: ($witness) => Set($coinId);
NextChSet(w) ==
  (w.prevChSet \ { c.id : c \in w.inputs }) \union OutputIds(w)

\* The post-transition balances (clause 3/7): debit inputs, credit outputs and
\* any issuance; retained difference stays as the account balance.
\* @type: ($witness) => ($assetId -> Int);
NextBalances(w) ==
  LET assets == AssetsTouched(w) \union DOMAIN w.prevState.balances
      bal(a) == (IF a \in DOMAIN w.prevState.balances THEN w.prevState.balances[a] ELSE 0)
                  + InAmount(w.inputs, a) + MintAmount(w, a) - OutAmount(w.templates, a)
  IN [ a \in { a \in assets : bal(a) > 0 } |-> bal(a) ]

\* The new account state (clause 7): balances per clause 3, current_pubkey =
\* next_pubkey, send_counter+1, chRoot from clause 8, owner unchanged.
\* @type: ($witness) => $accountState;
NextAccountState(w) ==
  MkAccountState(w.prevState.owner, NextBalances(w), w.nextPk,
                 w.prevState.sendCounter + 1, w.prevState.chRoot + 1)

\* Clause 7 -- new account state binding. ProofData.new_account_state_hash equals
\* ash(new state) (AshEq), owner unchanged, key rotated, counter incremented.
\* @type: ($witness, $proofData) => Bool;
Clause7_NewState(w, pd) ==
  /\ AshEq(pd.newAsh, NextAccountState(w))
  /\ pd.newAsh.owner = w.prevState.owner
  /\ pd.newAsh.currentPk = w.nextPk
  /\ pd.newAsh.sendCounter = w.prevState.sendCounter + 1

\* Clause 8 -- coin-history update. ProofData.coin_history_root commits exactly
\* to NextChSet (A16/RootCommitsSet over the updated per-account SMT key set).
\* @type: ($witness, $proofData) => Bool;
Clause8_ChUpdate(w, pd) == RootCommitsSet(pd.chRoot, NextChSet(w))

\* Clause 9 -- public-input binding. The four ProofData fields are the in-circuit
\* values computed by clauses 4/6/7/8; nothing else is public. Asserting the four
\* equalities IS the binding (zero-knowledge: amounts/assets/keys stay in w).
\* @type: ($witness, $proofData) => Bool;
Clause9_PublicBinding(w, pd) ==
  /\ pd.newAsh = NextAccountState(w)
  /\ pd.ocr = OutputIds(w)
  /\ pd.inr = NullifierSet(w)
  /\ pd.chRoot = NextChSet(w)

(***************************************************************************)
(* The compliance predicate C (Sec. 2.1): the conjunction of clauses 1-9.    *)
(* `authorised` is the A7 signing oracle the state machine maintains.        *)
(***************************************************************************)

\* @type: (Set(<<Int, $prMsgHandle>>), $witness, $proofData) => Bool;
C(authorised, w, pd) ==
  /\ Clause1_Recursion(w)
  /\ Clause2_Inputs(authorised, w)
  /\ Clause3_Balance(w)
  /\ Clause4_Nullifiers(w)
  /\ Clause5_Outputs(w)
  /\ Clause6_Ocr(w, pd)
  /\ Clause7_NewState(w, pd)
  /\ Clause8_ChUpdate(w, pd)
  /\ Clause9_PublicBinding(w, pd)

(***************************************************************************)
(* State machine. A small lineage exerciser: per account we keep the current *)
(* AccountState, the abstract coin-history set its chRoot commits to, and the *)
(* shared A7 authorisation oracle. Next picks an account, an InitialProof or  *)
(* AccountUpdateProof witness with C(...) = TRUE, and advances that account.  *)
(* Instances are tiny (2 accounts, a single asset family) on purpose.         *)
(***************************************************************************)

CONSTANTS
  \* @type: Set(Int);
  Accounts,        \* the finite set of account addresses/initial pubkeys
  \* @type: Int;
  AssetNameHash,   \* one asset family's name hash
  \* @type: Int;
  AssetDecimals    \* its decimals

\* The single v1 asset each account may mint (creator-bound, Sec. 6.5).
\* @type: (Int) => $assetId;
AssetOf(pk0) == MkAssetId(pk0, AssetNameHash, AssetDecimals, IssuanceVersionV1)

VARIABLES
  \* @type: Int -> $accountState;
  prState,        \* current AccountState per account
  \* @type: Int -> Set($coinId);
  prChSet,        \* abstract coin-history key set per account (commits to prState[a].chRoot)
  \* @type: Set(<<Int, $prMsgHandle>>);
  prAuthorised    \* A7 oracle: (pk, msgHandle) pairs honestly signed

\* @type: <<Int -> $accountState, Int -> Set($coinId), Set(<<Int, $prMsgHandle>>)>>;
prVars == << prState, prChSet, prAuthorised >>

\* The asset-id carrier for these instances (one v1 family, creators = Accounts).
\* @type: () => Set($assetId);
AssetCarrier ==
  AssetIdsOver(Accounts, {AssetNameHash}, {AssetDecimals}, {IssuanceVersionV1})

\* Structural well-formedness of one account state. balances is a PARTIAL map
\* (omit-zero canonicalisation, Sec. 1.7.4): its domain is a subset of the asset
\* carrier and every retained entry is positive (Foundations.WellFormedBalances),
\* so the empty map is admitted -- a [AssetCarrier -> Int] total-function set would
\* wrongly reject the canonical empty account.
\* @type: ($accountState) => Bool;
WfAccountState(as) ==
  /\ DOMAIN as.balances \subseteq AssetCarrier
  /\ WellFormedBalances(as)
  /\ as.owner \in Int
  /\ as.currentPk \in Int
  /\ as.sendCounter \in Int
  /\ as.chRoot \in Int

\* @type: Bool;
PrTypeOK ==
  /\ DOMAIN prState = Accounts
  /\ \A a \in Accounts : WfAccountState(prState[a])
  /\ DOMAIN prChSet = Accounts
  /\ \A a \in Accounts :
       \A cid \in prChSet[a] : cid.asset \in AssetCarrier /\ WfAccountState(cid.prevAsh)
  \* prAuthorised holds (currentPk, msgHandle) pairs; assert the element shape
  \* (Int pk, structured handle) rather than membership in an infinite SUBSET.
  /\ \A p \in prAuthorised :
       /\ p[1] \in Int
       /\ DOMAIN p[2] = { "inr", "ocr" }

\* @type: Bool;
PrInit ==
  /\ prState = [ a \in Accounts |-> CanonicalEmptyAccount(a, a) ]
  /\ prChSet = [ a \in Accounts |-> {} ]
  /\ prAuthorised = {}

(***************************************************************************)
(* Mint action: an account performs its v1 InitialProof issuance, emitting   *)
(* one self-owned output coin of `amount`. The account's own current key      *)
(* signs (the only way `authorised` grows), so the A7 oracle stays honest.    *)
(***************************************************************************)

\* @type: (Int, Int) => Bool;
MintStep(a, amount) ==
  LET prev   == prState[a]
      asset  == AssetOf(prev.currentPk)
      \* @type: Seq($coinTemplate);
      tmpl   == << MkCoinTemplate(prev.owner, amount, asset) >>
      iss    == [ assetId |-> asset, creatorPk |-> prev.currentPk, version |-> IssuanceVersionV1,
                  nameHash |-> AssetNameHash, amount |-> amount, decimals |-> AssetDecimals,
                  termsHash |-> TermsHash(asset, IssuanceVersionV1) ]
      \* @type: $witness;
      w == [ isInitial |-> TRUE, prevProofAccepts |-> FALSE, prevState |-> prev,
             prevChSet |-> prChSet[a],
             \* InitialProof has no predecessor proof: the clause 1 PCD binding is
             \* not taken (isInitial branch), so these carry the canonical prev.
             prevNewAsh |-> prev, prevCommittedChSet |-> prChSet[a],
             inputs |-> {},
             creatingPrevAsh |-> [ x \in {} |-> prev ],
             txnSigOk |-> TRUE, txnPk |-> prev.currentPk, templates |-> tmpl,
             nk |-> prev.currentPk, nextPk |-> prev.currentPk + 1,
             hasIssuance |-> TRUE, issuance |-> iss ]
      newAuth == prAuthorised \union
                   { << prev.currentPk, PrMsgTag(NullifierSet(w), OutputIds(w)) >> }
      \* @type: $proofData;
      pd == [ newAsh |-> NextAccountState(w), ocr |-> OutputIds(w),
              inr |-> NullifierSet(w), chRoot |-> NextChSet(w) ]
  IN /\ prev.sendCounter = 0                 \* InitialProof = first transition
     /\ amount > 0 /\ amount < U128Bound
     /\ C(newAuth, w, pd)
     /\ prAuthorised' = newAuth
     /\ prState' = [ prState EXCEPT ![a] = NextAccountState(w) ]
     /\ prChSet' = [ prChSet EXCEPT ![a] = NextChSet(w) ]

(***************************************************************************)
(* Send action: a subsequent AccountUpdateProof. The account spends one coin  *)
(* it already holds (membership via chSet, clause 2b) and emits a single self- *)
(* change coin of equal amount (In(a) = Out(a), clause 3 conservation). This   *)
(* exercises clauses 2, 4, 5, 8 that a pure mint leaves trivial, and advances  *)
(* the lineage so the state machine does not deadlock after the first mint.    *)
(* prev_proof verifies (A1) attesting prev state -- the AccountUpdate path.    *)
(***************************************************************************)

\* @type: (Int, $coinId, Int) => Bool;
SendStep(a, cid, amount) ==
  LET prev   == prState[a]
      asset  == cid.asset
      \* the held coin, reconstructed: owned by the account, of the spent amount.
      inCoin == MkCoin(cid, prev.owner, amount, asset)
      \* @type: Seq($coinTemplate);
      tmpl   == << MkCoinTemplate(prev.owner, amount, asset) >>
      \* clause 2c: the coin's id was built over its creating prior state, which
      \* MkCoinId recorded in cid.prevAsh; supply exactly that as the witness.
      cpa    == [ x \in {cid} |-> cid.prevAsh ]
      \* @type: $witness;
      w == [ isInitial |-> FALSE, prevProofAccepts |-> TRUE, prevState |-> prev,
             prevChSet |-> prChSet[a],
             \* clause 1 PCD (FIX 2): the prev proof's public outputs are the
             \* prev state's own ash and the coin-history root clause 2 proves
             \* inclusion against -- here the account's own prev state / chSet.
             prevNewAsh |-> prev, prevCommittedChSet |-> prChSet[a],
             inputs |-> {inCoin},
             creatingPrevAsh |-> cpa,
             txnSigOk |-> TRUE, txnPk |-> prev.currentPk, templates |-> tmpl,
             nk |-> prev.currentPk, nextPk |-> prev.currentPk + 1,
             hasIssuance |-> FALSE,
             issuance |-> [ assetId |-> asset, creatorPk |-> prev.currentPk,
                            version |-> IssuanceVersionV1, nameHash |-> AssetNameHash,
                            amount |-> 0, decimals |-> AssetDecimals,
                            termsHash |-> TermsHash(asset, IssuanceVersionV1) ] ]
      newAuth == prAuthorised \union
                   { << prev.currentPk, PrMsgTag(NullifierSet(w), OutputIds(w)) >> }
      \* @type: $proofData;
      pd == [ newAsh |-> NextAccountState(w), ocr |-> OutputIds(w),
              inr |-> NullifierSet(w), chRoot |-> NextChSet(w) ]
  IN /\ prev.sendCounter > 0                 \* AccountUpdateProof = not the first
     /\ cid \in prChSet[a]                   \* the account actually holds the coin
     /\ amount > 0 /\ amount < U128Bound
     /\ C(newAuth, w, pd)
     /\ prAuthorised' = newAuth
     /\ prState' = [ prState EXCEPT ![a] = NextAccountState(w) ]
     /\ prChSet' = [ prChSet EXCEPT ![a] = NextChSet(w) ]

\* @type: Bool;
PrNext ==
  \/ \E a \in Accounts : \E amount \in 1 .. 3 : MintStep(a, amount)
  \/ \E a \in Accounts : \E cid \in prChSet[a] : \E amount \in 1 .. 3 : SendStep(a, cid, amount)

\* @type: Bool;
PrSpec == PrInit /\ [][PrNext]_prVars

\* Constant initialiser for a small smoke instance (Apalache --cinit), uniform
\* with the other state-machine modules: two accounts, one v1 asset family.
\* @type: Bool;
PrConstInit ==
  /\ Accounts = {1, 2}
  /\ AssetNameHash = 100
  /\ AssetDecimals = 8

=============================================================================
