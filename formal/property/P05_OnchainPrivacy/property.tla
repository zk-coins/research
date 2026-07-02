-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P05 -- On-chain Privacy / Unlinkability (FULL on-chain model).          *)
(*                                                                         *)
(* Phase-2 property deliverable of the zkCoins 100% Logical Verification    *)
(* Initiative. P05 is an OBSERVATIONAL property: it bounds what a passive    *)
(* chain-only observer of Bitcoin learns from the on-chain footprint. The   *)
(* unlinkability guarantee itself rests on cryptographic AXIOMS (A3 root /  *)
(* nullifier preimage-resistance, BIP-32-PRF rotating-key unlinkability,    *)
(* A2 nk-secrecy); those are NOT claimed verified here. What IS machine-    *)
(* checked is the COMPOSITION SURFACE: the on-chain projection a verifier    *)
(* publishes, and the structural / dynamic facts about that projection that  *)
(* the axioms then compose with to deliver unlinkability.                   *)
(*                                                                         *)
(* This module EXTENDS the full-fidelity on-chain state machine             *)
(* module/Onchain.tla (Spec Sec. 3, spec-v1.1 baseline ed7fdece), the       *)
(* SAME machine P02 No-Double-Spend is proven over. P05 reuses it unchanged  *)
(* and reasons about the CHAIN-OBSERVABLE PROJECTION of each admitted batch. *)
(*                                                                         *)
(* THE CRITICAL POST-#40 FACT (Spec Sec. 3.1 / Sec. 3.5 metadata note).     *)
(*   The on-chain footprint is a CONSTANT-SIZE BatchInscription (231 bytes). *)
(*   A chain-only observer learns ONLY:                                     *)
(*       { publisher_pubkey, prev_root, new_root, bundle_locator,           *)
(*         block_anchor }                                                   *)
(*   and NOTHING ELSE -- NOT the record count m, NOT any per-spender input  *)
(*   count k_j, NOT any individual nullifier. The SpendRecords, the member  *)
(*   nullifiers, and the AggregateBatchProof live OFF-CHAIN inside the       *)
(*   BatchBundle (Sec. 3.1, Sec. 4.6); the chain holds only their roots and  *)
(*   the locator hash. Sec. 3.1: a BatchInscription "reveals no amount,     *)
(*   asset, sender, receiver, nor any individual nullifier."                *)
(*                                                                         *)
(* MODEL-vs-WIRE HONESTY (the A16/A3 boundary -- stated openly).            *)
(*   Onchain.tla models a root AS the SET of nullifiers it commits to       *)
(*   (A16/RootCommitsSet): in the MODEL prevRoot/newRoot literally CARRY the *)
(*   nf-set. On the WIRE they are 32-byte Poseidon/SMT roots whose preimage  *)
(*   is hidden by A3 (root preimage-resistance). Likewise the Onchain record *)
(*   fields `batchNullifiers` and `memberValidities` represent BUNDLE        *)
(*   content used by off-chain verification (Sec. 3.1 (a)/(b)/(c)), NOT      *)
(*   chain bytes. Our observable projection MUST reflect that split: it      *)
(*   PROJECTS AWAY the bundle-only fields and keeps only the five on-chain   *)
(*   fields, and every dynamic claim it makes is designed to have real       *)
(*   content DESPITE the set-representation of roots (see ChainView below).  *)
(*                                                                         *)
(* WHAT IS MACHINE-CHECKED HERE vs WHAT IS AXIOM (honest split; full table   *)
(* in notes.md):                                                            *)
(*   DYNAMIC (negatively controllable, the model earns its keep):           *)
(*     PublisherOnlyLink -- the §3.5 claim "the publisher identity is the    *)
(*       ONLY on-chain link": every admitted batch's publisherPk is a        *)
(*       publisher key and NEVER equals an account identity key (owner /     *)
(*       current_pubkey) of any account behind any on-chain nullifier.       *)
(*       Deleting the model's separation between publisher keys and account  *)
(*       keys breaks it (negative control, notes.md).                       *)
(*   STRUCTURAL (by-construction, clearly labelled -- NOT a tautology dressed *)
(*       as a dynamic claim; the P10 vacuity-defect discipline applies):     *)
(*     NoMemberStructureOnChain -- the observable projection never carries    *)
(*       the bundle-only fields batchNullifiers / memberValidities AS SUCH;   *)
(*       ChainView's record domain is exactly the five on-chain fields.       *)
(*       Labelled structural because it is a property of the PROJECTION       *)
(*       FUNCTION, established by construction, not exercised by the          *)
(*       transition relation.                                               *)
(*   AXIOM (quoted, scoped, NOT claimed verified -- see notes.md):          *)
(*     A3 root/nf preimage-resistance (the set-representation of roots is     *)
(*       exactly the A16/A3 boundary); BIP-32-PRF rotating-key              *)
(*       unlinkability (fresh Pk_i per transition); A2 nk-secrecy; and the    *)
(*       network-layer hygiene that Pass-3 grades MEDIUM (out of scope).     *)
(***************************************************************************)
EXTENDS Onchain, Apalache

(***************************************************************************)
(* The CHAIN-OBSERVER PROJECTION.                                          *)
(*                                                                         *)
(* ChainView(b) is what a passive chain-only observer reads off ONE admitted *)
(* BatchInscription: EXACTLY the five on-chain fields of the 231-byte        *)
(* inscription (Sec. 3.5 byte layout, offsets 3/35/67/99/131+163):          *)
(*     publisherPk        (offset 3,  32B, Pk_p)                            *)
(*     prevRoot           (offset 35, 32B, accumulator root)                *)
(*     newRoot            (offset 67, 32B, accumulator root)                *)
(*     bundleLocator      (offset 99, 32B, Hc over the bundle)              *)
(*     blockAnchorHeight  (offset 163, 4B, big-endian u32 height)          *)
(* It DROPS batchNullifiers, memberValidities and anchorOk -- those are      *)
(* bundle-/admission-internal (Sec. 3.1: the records, nullifiers, and proof  *)
(* are off-chain inside the BatchBundle; anchorOk is the verifier's own       *)
(* §3.5 scan outcome, not an inscribed byte).                               *)
(*                                                                         *)
(* @type: ($batchInscription) =>                                           *)
(*   { publisherPk: Int, prevRoot: Set($nullifier), newRoot: Set($nullifier),*)
(*     bundleLocator: Int, blockAnchorHeight: Int };                        *)
(***************************************************************************)
ChainView(b) ==
  [ publisherPk       |-> b.publisherPk,
    prevRoot          |-> b.prevRoot,
    newRoot           |-> b.newRoot,
    bundleLocator     |-> b.bundleLocator,
    blockAnchorHeight |-> b.blockAnchorHeight ]

(***************************************************************************)
(* Account identity keys behind a nullifier (the WIRE-hidden datum).        *)
(*                                                                         *)
(* A $nullifier carries, in the model, the spending account behind the coin *)
(* (nf.coin.prevAsh : $accountState). The account's identity keys are its    *)
(* `owner` (= address = H(Pk0), §1.4, AddressOf injective) and its           *)
(* `currentPk` (= the rotating Pk_i that signed the transition, §1.2). On    *)
(* the WIRE neither appears (the nf is a 256-bit digest, A3/A2); in the      *)
(* MODEL they are reachable through the set-represented root, which is        *)
(* exactly why the dynamic claim below is non-trivial: it asserts that even  *)
(* with the model's full visibility into the committed set, NO account        *)
(* identity key ever coincides with the one genuinely on-chain identity, the *)
(* publisher key.                                                           *)
(*                                                                         *)
(* @type: ($nullifier) => Set(Int);                                        *)
(***************************************************************************)
AccountKeysOf(nf) == { nf.coin.prevAsh.owner, nf.coin.prevAsh.currentPk }

(* All account identity keys behind every nullifier ever committed on-chain  *)
(* (the union of prev/new roots of every admitted inscription -- the full    *)
(* set the accumulator has ever held; A16 lets us read the committed set).   *)
(* @type: () => Set(Int);                                                   *)
AccountKeysOnChain ==
  UNION { AccountKeysOf(nf) :
            nf \in UNION { onAdmittedChain[i].newRoot
                             : i \in DOMAIN onAdmittedChain } }

(* The publisher-key namespace (Sec. 3.2): publisher identity keys Pk_p.     *)
(* @type: () => Set(Int);                                                   *)
PublisherKeys == Publishers

(***************************************************************************)
(* DYNAMIC invariant -- PublisherOnlyLink (Sec. 3.5: "the publisher identity *)
(* is the only on-chain link").                                            *)
(*                                                                         *)
(* For every admitted inscription: its ChainView.publisherPk is a publisher  *)
(* key, and it NEVER equals an account identity key of any account behind    *)
(* any on-chain nullifier. I.e. the one identity the chain exposes (the       *)
(* publisher) is categorically NOT a wallet/account identity -- a chain       *)
(* observer cannot read an account address or its rotating signing key off    *)
(* the inscription via the publisher field.                                  *)
(*                                                                         *)
(* This is genuinely dynamic: the publisherPk and the committed account keys  *)
(* are both produced by the Admit action, and the claim relates them across   *)
(* the whole admitted history. It is negatively controllable: a model where   *)
(* a publisher key coincides with an account identity key (deleting the       *)
(* namespace separation) admits a batch that violates it (negative control,   *)
(* notes.md). It is NOT vacuous: the reachability probe shows admitted        *)
(* inscriptions WITH non-empty account-key sets exist (notes.md vacuity probe)*)
(* so the disjointness is asserted over a populated set, not the empty set.   *)
(* @type: () => Bool;                                                       *)
(***************************************************************************)
PublisherOnlyLink ==
  \A i \in DOMAIN onAdmittedChain :
    LET cv == ChainView(onAdmittedChain[i]) IN
      /\ cv.publisherPk \in PublisherKeys
      /\ cv.publisherPk \notin AccountKeysOnChain

(***************************************************************************)
(* STRUCTURAL fact -- NoMemberStructureOnChain (labelled structural).       *)
(*                                                                         *)
(* The observable projection of every admitted inscription carries EXACTLY   *)
(* the five on-chain fields and NO bundle-only field: its record domain is    *)
(* { publisherPk, prevRoot, newRoot, bundleLocator, blockAnchorHeight } and   *)
(* in particular does NOT contain `batchNullifiers` or `memberValidities`     *)
(* (Sec. 3.1: records/nullifiers/proof are off-chain). This is a property of  *)
(* the projection FUNCTION ChainView, true by construction; it is checked     *)
(* over the reachable space only to confirm the projection is well-formed on  *)
(* every admitted inscription. Labelled STRUCTURAL -- it is not exercised by  *)
(* the transition relation and is not the load-bearing dynamic claim.        *)
(* @type: () => Bool;                                                       *)
(***************************************************************************)
NoMemberStructureOnChain ==
  \A i \in DOMAIN onAdmittedChain :
    LET cv == ChainView(onAdmittedChain[i]) IN
      /\ DOMAIN cv = { "publisherPk", "prevRoot", "newRoot",
                       "bundleLocator", "blockAnchorHeight" }
      /\ "batchNullifiers"  \notin DOMAIN cv
      /\ "memberValidities" \notin DOMAIN cv

(***************************************************************************)
(* The composite P05 observable invariant: the dynamic claim AND the         *)
(* structural fact. (The structural conjunct is by-construction; it is        *)
(* bundled so a single check certifies the whole observable surface.)        *)
(* @type: () => Bool;                                                       *)
(***************************************************************************)
INV_P5 ==
  /\ PublisherOnlyLink
  /\ NoMemberStructureOnChain

(***************************************************************************)
(* INDUCTIVE invariant for the UNBOUNDED part (the dynamic PublisherOnlyLink *)
(* claim that does not quantify over the Seq differently than P02 must).     *)
(*                                                                         *)
(* PublisherOnlyLink AND NoMemberStructureOnChain both quantify over DOMAIN  *)
(* onAdmittedChain (the same Seq-capacity situation P02 documents for        *)
(* continuity). Apalache encodes a Seq with a STATIC capacity, so an          *)
(* inductive step assuming-and-reestablishing a chain-quantified property of  *)
(* ARBITRARY length is not a single unbounded SMT query. We therefore         *)
(* certify, EXACTLY as P02 does for its chain-quantified continuity result:   *)
(*   - UNBOUNDED (inductive, set-projection): the per-step LOCAL form         *)
(*     PublisherOnlyLinkStep -- "the single inscription Admit appends         *)
(*     satisfies the publisher/account-key separation" -- which references    *)
(*     only the Admit-time data, not the whole history, and is preserved by    *)
(*     every OnNext action (Confirm/Reorg/PublisherSign do not append a new    *)
(*     violating inscription; Admit appends one that satisfies it by the       *)
(*     namespace separation). See IndInv_P5 / IndInvInit.                     *)
(*   - BOUNDED (length 6 = finality depth K): the full history-quantified      *)
(*     INV_P5, by reachability over the full machine.                        *)
(* The honest scope statement mirrors P02's "Seq-variable handling".         *)
(***************************************************************************)

(* Local (single-inscription) form of the dynamic claim, evaluated on the    *)
(* batch Admit is about to append. This is the per-step content of            *)
(* PublisherOnlyLink that is preserved unbounded.                            *)
(* @type: ($batchInscription) => Bool;                                       *)
PublisherOnlyLinkLocal(b) ==
  LET cv == ChainView(b) IN
    /\ cv.publisherPk \in PublisherKeys
    /\ \A nf \in cv.newRoot : cv.publisherPk \notin AccountKeysOf(nf)

(* The set-projection inductive invariant. It carries the type facts and the  *)
(* GLOBAL disjointness of the publisher namespace from the account-key        *)
(* namespace as a STATE fact over the whole committed set -- which is the      *)
(* inductive strengthening that makes PublisherOnlyLink preserved: as long as  *)
(* no publisher key is an account key of any committed nullifier, every newly  *)
(* admitted inscription (whose publisherPk is a publisher key) satisfies the   *)
(* separation, and Admit only ever adds nullifiers whose account keys are       *)
(* drawn from the (publisher-disjoint) account namespace.                      *)
(* @type: () => Bool;                                                         *)
IndInv_P5 ==
  /\ onPending \subseteq Nullifiers
  /\ onCompleted \subseteq Nullifiers
  /\ onDoubled \subseteq Nullifiers
  /\ onAuthorised \subseteq (Publishers \X BundleLocators)
  \* The load-bearing inductive fact: NO committed nullifier's account keys
  \* intersect the publisher namespace. Established at Init (empty chain) and
  \* preserved because Admit draws nullifiers from Nullifiers, whose account
  \* keys are the account namespace, disjoint from Publishers by construction.
  /\ \A nf \in (onPending \union onCompleted) :
       AccountKeysOf(nf) \intersect PublisherKeys = {}

(***************************************************************************)
(* The OBSERVABLE GUARANTEE the inductive invariant ENTAILS (the [P4]        *)
(* implication target). It is the load-bearing state fact that the dynamic    *)
(* PublisherOnlyLink reduces to: NO account identity key behind any committed  *)
(* nullifier is a publisher key -- equivalently, the only on-chain identity    *)
(* (the publisher) is categorically disjoint from every wallet/account         *)
(* identity. IndInv_P5 => ObservableGuarantee is a pure length-0 implication   *)
(* (no transition), exactly the P02 [B4]-style closing step: it shows the      *)
(* inductive invariant is strong enough to deliver the privacy-composition     *)
(* fact, not just to be self-preserving.                                       *)
(* @type: () => Bool;                                                          *)
ObservableGuarantee ==
  \A nf \in (onPending \union onCompleted) :
    AccountKeysOf(nf) \intersect PublisherKeys = {}

(* Assignment-form restatement for the inductive STEP's --init (Apalache       *)
(* requires every variable ASSIGNED). Mirrors P02's IndInvInit: each set var    *)
(* is drawn from its powerset, the Seq is Gen-constructed (its value is          *)
(* irrelevant to the set-projection conjuncts), and the disjointness premise     *)
(* is asserted over the assigned accumulator.                                   *)
(* @type: () => Bool;                                                           *)
IndInvInit ==
  /\ onPending \in SUBSET Nullifiers
  /\ onCompleted \in SUBSET Nullifiers
  /\ onDoubled \in SUBSET Nullifiers
  /\ onAuthorised \in SUBSET (Publishers \X BundleLocators)
  /\ \A nf \in (onPending \union onCompleted) :
       AccountKeysOf(nf) \intersect PublisherKeys = {}
  \* Seq projection: an arbitrary admitted history of bounded capacity. Its
  \* value is not read by IndInv_P5's set-projection conjuncts (same argument
  \* as P02's IndInvInit). Gen(4) constructs an UNCONSTRAINED sequence.
  /\ onAdmittedChain = Gen(4)

(***************************************************************************)
(* Constant initialiser for P05.                                           *)
(*                                                                         *)
(* The publisher namespace and the account namespace are DISJOINT by         *)
(* construction (Sec. 1.2: publisher Pk_p is the node's `op`-family identity, *)
(* a HARDENED sibling that cannot be the SPEND-branch Pk_i nor the address    *)
(* H(Pk0); the two live in different derivation branches). We realise that as: *)
(*   - account identity key = 0 (CanonicalEmptyAccount owner/Pk0 = 0), so the  *)
(*     account namespace behind every smoke nullifier is {0};                  *)
(*   - Publishers = 1..2, DISJOINT from {0}.                                   *)
(* Deleting that separation (an account whose owner is a publisher key) is the *)
(* negative control (notes.md). The argument is uniform in the universe sizes  *)
(* (every conjunct is per-inscription / per-nullifier local).                 *)
(* @type: () => Bool;                                                       *)
(***************************************************************************)
P5ConstInit ==
  /\ Nullifiers = { MkNullifier(0, SmokeCoinId(i)) : i \in 1..3 }
  /\ Publishers = 1..2
  /\ BundleLocators = 1..2

=============================================================================
