-------------------------- MODULE Foundations --------------------------
(***************************************************************************)
(* Foundations -- the shared TYPE BACKBONE for the zkCoins formal model.    *)
(*                                                                         *)
(* Models spec Sec. 1 (Foundations) at commit docs@ed7fdece (spec-v1.1 =     *)
(* b6972b8 + docs#46/#47/#48): every key,                                    *)
(* identifier, hash, and core data structure the rest of the model uses.    *)
(* This is a DEFINITIONS module: no state machine of its own. Every other   *)
(* module EXTENDS it so datatypes line up (the Phase-1 harmonization        *)
(* requirement).                                                           *)
(*                                                                         *)
(* DIGEST ABSTRACTION (the load-bearing modelling decision; axioms A3/A5/   *)
(* A16/A17). A cryptographic digest is modelled as the STRUCTURED VALUE it  *)
(* commits to, so equality of digests is equality of pre-images and        *)
(* collision-freedom holds by construction:                                *)
(*   - asset_id        = the (creator, name_hash, decimals, version) tuple  *)
(*                       (Hc collision resistance, A3)                      *)
(*   - coin.identifier = the (prev_account_state, asset_id, coin_index)    *)
(*                       tuple (A3); carries the PRIOR account state,      *)
(*                       exactly as Sec. 1.4 breaks the would-be            *)
(*                       coin.identifier <-> new_ash recursion              *)
(*   - nf              = the (nk, coin.identifier) tuple (A3)               *)
(*   - ash             = the AccountState value itself: serialize is        *)
(*                       injective (A17) and Hc collision resistant (A3),   *)
(*                       so the state IS a faithful stand-in for its hash   *)
(* TYPE-RECURSION is broken by keeping the coin-history root OPAQUE: under  *)
(* A16 a Merkle/SMT root is collision-bound to its key set, so coin-history *)
(* membership is modelled as an abstract relation in Proofs.tla rather than *)
(* by unrolling the tree. `accountState` therefore carries `chRoot : Int`   *)
(* (an opaque handle), never the set of coin ids that would close a type    *)
(* cycle.                                                                  *)
(*                                                                         *)
(* SECRET keys and signatures are NOT modelled as scalars/curve points;     *)
(* BIP-340 EUF-CMA (A7) is captured in Assumptions.tla as an authorisation  *)
(* oracle. Foundations fixes only the PUBLIC types and data structures.     *)
(***************************************************************************)
EXTENDS Integers

(***************************************************************************)
(* Opaque scalar domains. Each is an uninterpreted token space modelled as  *)
(* Int -- the model never relies on arithmetic over them, only on equality. *)
(*   address  -- account identity = H(Pk0) (Sec. 1.4); 1:1 with an account  *)
(*   pubkey   -- BIP-340 x-only public key Pk_i / Pk0 / op / IVPK (Sec. 1.2)*)
(*   keyref   -- handle for a secret key (nk, ivk, ovk, op, sk_i)           *)
(*   amount   -- u128 value, range-checked in-circuit (Sec. 1.7.3)          *)
(*   root     -- an opaque Poseidon/SMT root handle (coin-history root,     *)
(*               accumulator root); collision-bound to its contents (A16)   *)
(*   nameHash -- H(name) (Sec. 1.4); the human-readable name never appears  *)
(***************************************************************************)

\* @typeAlias: assetId = { creator: Int, nameHash: Int, decimals: Int, version: Int };
\* @typeAlias: accountState = { owner: Int, balances: $assetId -> Int, currentPk: Int, sendCounter: Int, chRoot: Int };
\* @typeAlias: coinId = { prevAsh: $accountState, asset: $assetId, idx: Int };
\* @typeAlias: nullifier = { nk: Int, coin: $coinId };
\* @typeAlias: coin = { id: $coinId, recipient: Int, amount: Int, asset: $assetId };
\* @typeAlias: coinTemplate = { recipient: Int, amount: Int, asset: $assetId };
\* @typeAlias: invoice = { amount: Int, recipient: Int, asset: $assetId, pk0: Int, ivpk: Int, opPubkey: Int, relays: Set(Int), addrSigOk: Bool, opSigOk: Bool };
Foundations_typedefs == TRUE

(***************************************************************************)
(* Reference-instantiation constants.                                      *)
(***************************************************************************)

\* The only issuance schema this spec version defines (Sec. 6.5).
\* @type: () => Int;
IssuanceVersionV1 == 1

\* Opaque handle for E'_256, the empty coin-history SMT root (Sec. 1.7.6).
\* @type: () => Int;
EmptyChRoot == 0

(***************************************************************************)
(* Constructors -- each builds the structured digest/record of Sec. 1.4/1.5.*)
(***************************************************************************)

\* asset_id = Hc("AssetId", genesis_tag || creator_pubkey || H(name) || decimals || version)
\* @type: (Int, Int, Int, Int) => $assetId;
MkAssetId(creatorPk, nh, dec, ver) ==
  [ creator |-> creatorPk, nameHash |-> nh, decimals |-> dec, version |-> ver ]

\* coin.identifier = Hc("Coin", prev_account_state_hash || asset_id || coin_index)
\* @type: ($accountState, $assetId, Int) => $coinId;
MkCoinId(prevState, asset, idx) ==
  [ prevAsh |-> prevState, asset |-> asset, idx |-> idx ]

\* nf = Hc("Nullifier", nk || coin.identifier)
\* @type: (Int, $coinId) => $nullifier;
MkNullifier(nk, cid) ==
  [ nk |-> nk, coin |-> cid ]

\* @type: ($coinId, Int, Int, $assetId) => $coin;
MkCoin(cid, recipient, amt, asset) ==
  [ id |-> cid, recipient |-> recipient, amount |-> amt, asset |-> asset ]

\* @type: (Int, Int, $assetId) => $coinTemplate;
MkCoinTemplate(recipient, amt, asset) ==
  [ recipient |-> recipient, amount |-> amt, asset |-> asset ]

\* @type: (Int, $assetId -> Int, Int, Int, Int) => $accountState;
MkAccountState(owner, balances, currentPk, sendCounter, chRoot) ==
  [ owner |-> owner, balances |-> balances, currentPk |-> currentPk,
    sendCounter |-> sendCounter, chRoot |-> chRoot ]

\* The empty balances map (balances_count = 0 in serialize, Sec. 1.7.4).
\* @type: () => ($assetId -> Int);
EmptyBalances == [ a \in {} |-> 0 ]

(***************************************************************************)
(* Canonical empty account (Sec. 2.2, normative): owner = address,          *)
(* balances = {}, current_pubkey = Pk0, send_counter = 0,                   *)
(* coin_history_root = E'_256.                                              *)
(***************************************************************************)

\* @type: (Int, Int) => $accountState;
CanonicalEmptyAccount(address, pk0) ==
  MkAccountState(address, EmptyBalances, pk0, 0, EmptyChRoot)

(***************************************************************************)
(* Predicates.                                                             *)
(***************************************************************************)

\* ash equality: by A17 + A3, ash is a bijection on account states, so digest
\* equality IS state equality.
\* @type: ($accountState, $accountState) => Bool;
AshEq(a, b) == a = b

\* Account identity derivation: address = H(Pk0) (Sec. 1.4). H is collision
\* resistant and preimage binding (A5/A6), so the address is INJECTIVE in the
\* pubkey; the model needs only equality of addresses, never the hash bytes, so
\* the identity representative over the opaque scalar is a sound stand-in (equal
\* addresses iff equal pubkeys). Promoted here so every module shares one H(Pk0).
\* @type: (Int) => Int;
AddressOf(pk) == pk

\* serialize omit-zero canonicalisation (Sec. 1.7.4): a well-formed balances
\* map carries no zero entries (and no negative ones; amounts are u128).
\* @type: ($accountState) => Bool;
WellFormedBalances(as) ==
  \A a \in DOMAIN as.balances : as.balances[a] > 0

\* @type: ($coin) => Bool;
WellFormedCoin(c) ==
  /\ c.amount >= 0
  /\ c.asset.version = IssuanceVersionV1

\* A coin's identifier commits to the same asset the coin claims (clause 2c
\* recomputation makes a mismatch a Poseidon collision, A3).
\* @type: ($coin) => Bool;
CoinIdConsistent(c) == c.id.asset = c.asset

\* The Sec. 4.3 Invoice three-check rule: (i) H(pk0) == recipient -- the caller
\* supplies addressOfPk0, the address the invoice's pk0 derives to (A5/A6
\* preimage binding); (ii) addr_sig valid under pk0; (iii) sig valid under op.
\* Signature validity itself is the A7 oracle, carried as outcome booleans.
\* @type: ($invoice, Int) => Bool;
InvoiceValid(inv, addressOfPk0) ==
  /\ inv.recipient = addressOfPk0
  /\ inv.addrSigOk
  /\ inv.opSigOk

(***************************************************************************)
(* Domain builders for concrete instances: a model fixes finite scalar      *)
(* carriers and derives the structured domains from them.                   *)
(***************************************************************************)

\* @type: (Set(Int), Set(Int), Set(Int), Set(Int)) => Set($assetId);
AssetIdsOver(creators, nameHashes, decimalsSet, versions) ==
  { MkAssetId(c, nh, d, v) :
      c \in creators, nh \in nameHashes, d \in decimalsSet, v \in versions }

=============================================================================
