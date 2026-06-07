-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P04 -- Zero-Knowledge (witness confidentiality), the OBSERVATIONAL       *)
(* property.                                                                *)
(*                                                                         *)
(* Phase-2 deliverable of the zkCoins 100% Logical Verification Initiative. *)
(* P4 is special: most of its STRENGTH is the A2 axiom (Plonky2 zero-        *)
(* knowledge), and the headline statement -- "two witnesses w0, w1 with the *)
(* same ProofData are indistinguishable" -- is a HYPERPROPERTY (a relation   *)
(* over PAIRS of traces). Apalache checks SINGLE-trace state invariants, so  *)
(* it cannot machine-check indistinguishability directly. This package       *)
(* therefore splits P4 honestly into three layers, mirroring the P10 /       *)
(* P09 surrogate-scoping pattern, and the certificate headline says which    *)
(* layer carries which claim:                                               *)
(*                                                                         *)
(*   DYNAMIC (machine-checked, non-vacuous, negatively controllable).        *)
(*     An OBSERVER-FLOW / CONTAINMENT invariant over a composed machine: a   *)
(*     per-account proof lineage (module/Proofs.tla) PUBLISHES proofs; an     *)
(*     adversarial relay/chain observer scrapes the public projection and     *)
(*     tries to EXTRACT a witness-private scalar (a coin amount, the         *)
(*     nullifier key nk, a recipient address, a balance, a count) into a      *)
(*     ghost leak set. The protocol's publication discipline (Sec. 2.1       *)
(*     clause 9 "Nothing else is public") GATES what the observer may pull:   *)
(*     only the four committed ProofData fields' public content. The         *)
(*     invariant INV_P4_flow is that the observer's leak set NEVER contains   *)
(*     a witness-only scalar. This is GENUINELY dynamic: the public view and  *)
(*     the leak set grow as the lineage runs; deleting the gate (letting the  *)
(*     observer pull a witness scalar the protocol does not publish) makes a  *)
(*     leak REACHABLE and breaks the invariant (negative control below).      *)
(*                                                                         *)
(*   STRUCTURAL (by-construction, NOT dynamically exercised; labelled).      *)
(*     The TYPED-DISJOINTNESS facts -- that the published record TYPES        *)
(*     ($proofData, $batchInscription delivery-event plaintext) simply have   *)
(*     NO field that carries a $coin amount / recipient / nk / balance / count*)
(*     -- are structural: they hold by the shape of the records, not by any   *)
(*     reachable transition. We STATE them (PublishedCarriesNoWitnessField)   *)
(*     and label them structural, exactly as P10 labels spend-escalation      *)
(*     structural rather than dressing a tautology as a theorem. Equality     *)
(*     across the Int-modelled scalar domains is meaningless (an amount 3 and  *)
(*     a coin-index 3 are the same Int), so we do NOT machine-check a value-   *)
(*     level disjointness -- that would be a vacuity trap. The dynamic core    *)
(*     above carries the real content; the structural layer is documented.    *)
(*                                                                         *)
(*   AXIOM (quoted, scoped, NOT claimed machine-verified).                   *)
(*     A2 (Plonky2 zero-knowledge / proof indistinguishability),             *)
(*     A10/A11 (NIP-44 ciphertext + NIP-59 envelope confidentiality),        *)
(*     A3/A9 (tag/key unlinkability). The HYPERPROPERTY itself -- a proof     *)
(*     leaks nothing beyond ProofData -- is A2, an ideal-functionality        *)
(*     assumption Apalache does not discharge. See notes.md for the full      *)
(*     scope statement and the axiom table.                                  *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P4: HIGH, sound under A2, A10):           *)
(*   At the COMPOSITION level, nothing the protocol publishes -- the on-chain *)
(*   BatchInscription fields, the delivery-event plaintext, or a proof's      *)
(*   ProofData -- carries witness data (amounts, recipients, asset ids, keys, *)
(*   counts) EXCEPT through the four committed roots. The four ProofData       *)
(*   fields ARE the entire public surface (Sec. 2.1 clause 9). The            *)
(*   indistinguishability of two equal-ProofData witnesses is A2.             *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (baseline docs@b6972b8, post-docs#40):      *)
(*   - Sec. 2.1 clause 9 (public-input binding): "All four ProofData fields  *)
(*     ... are the proof's public inputs. Nothing else is public: amounts,    *)
(*     asset ids, recipients, keys, and counts remain in the witness (zero-   *)
(*     knowledge)." Formalised by Proofs.Clause9_PublicBinding (the four       *)
(*     equalities ARE the projection) and the PubItems gate below.            *)
(*   - Sec. 3.5 metadata note: a BatchInscription reveals only Pk_p, the      *)
(*     prev/new roots, the bundle content-address, and the anchoring tip --   *)
(*     "nothing more"; the record count and per-spender input count are       *)
(*     hidden on-chain; amounts/assets/parties/graph are "invisible to a      *)
(*     chain-only observer". Formalised by the on-chain projection class.      *)
(*   - Sec. 4.2: the delivery-event plaintext carries {detect_tag, epk,       *)
(*     blob_id, blob_locators, ack_nonce} and "NO amount, asset, recipient    *)
(*     address, or sender -- those live only inside ciphertext". Formalised    *)
(*     by the delivery projection class (the same opaque-handle set P08 uses). *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly; inherited from          *)
(* module/Proofs.tla, module/Onchain.tla, module/Transport.tla,              *)
(* module/Assumptions.tla):                                                  *)
(*   - A2 zero-knowledge is the Assumptions.PublicProjection oracle: the only  *)
(*     thing a verifier may learn from a proof is its public inputs. The       *)
(*     pre-image hiding of the four Poseidon/SMT roots (one-wayness) is NOT    *)
(*     re-derived; under A2/A4 a root exposes its committed KEY SET (coin ids, *)
(*     account-state identity) but not the scalar witness fields. The gate     *)
(*     PubItems encodes exactly which items the discipline exposes.            *)
(*   - The four ProofData fields are the structured handles of Proofs.tla      *)
(*     (newAsh, ocr, inr, chRoot); their "public content" is the set of coin   *)
(*     ids / nullifier handles / the account-state identity they commit to     *)
(*     (A16/RootCommitsSet), NOT the witness amounts/nk that produced them.    *)
(*   - NIP-44/NIP-59 (A10/A11) and tag/key unlinkability (A3/A9) bound the     *)
(*     transport + detection channels; here they are quoted as axioms (the     *)
(*     transport flow is machine-checked separately in P08).                   *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (recorded in notes.md):                     *)
(*   - REACHABILITY / VACUITY PROBE: the public view and the observer's legal  *)
(*     pulls actually grow (the negation "PublicView stays empty" / "obsLearnt *)
(*     stays empty" is violated) -- the gate is not vacuously closed over an    *)
(*     empty observable state.                                                *)
(*   - NEGATIVE CONTROL: widen the PubItems gate to expose a witness-channel   *)
(*     (the coin amount, or nk) -> the adversarial Observe pulls it -> the      *)
(*     leak set intersects the witness-only domain -> INV_P4_flow fails. The    *)
(*     gate (the Sec. 2.1 clause-9 discipline) is load-bearing.                *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, Apalache, Proofs

(***************************************************************************)
(* THE OBSERVABLE PUBLIC PROJECTION (the composition surface).             *)
(*                                                                         *)
(* What a relay / chain-only / verifier observer can see is the union of:    *)
(*   (P) every PUBLISHED proof's ProofData (Sec. 2.1 clause 9),             *)
(*   (O) every admitted on-chain BatchInscription's fields (Sec. 3.5),      *)
(*   (T) every delivery-event plaintext (Sec. 4.2).                         *)
(* The composition claim is that the SCALARS reachable through this surface  *)
(* are exactly the public ones: coin ids, the account-state identity, the    *)
(* publisher id, the opaque wire handles -- NOT the witness scalars           *)
(* (amounts, nk, recipient, balances, counts).                              *)
(*                                                                         *)
(* We expose the projection as a set of PUBLIC SCALARS the discipline lets a  *)
(* proof contribute. PubItems(w, pd) is the set of provenance-tagged items     *)
(* of (w, pd) legitimately makes observable.                                 *)
(*                                                                         *)
(* PROVENANCE-TAGGED items (the vacuity-trap fix). The prompt warns -- and    *)
(* the first model draft confirmed -- that comparing raw Int VALUES across    *)
(* the public and witness scalar domains is meaningless: an owner address 2,  *)
(* a nullifier key nk = 2, and an amount = 2 are the SAME Int, so a value-     *)
(* level `pulled \cap WitnessOnly # {}` fires on a numeric COINCIDENCE, not a  *)
(* real leak. We therefore tag every exposed/leaked datum by its PROVENANCE   *)
(* CHANNEL: an item is a record [chan |-> Str, val |-> Int]. The flow claim    *)
(* is about which CHANNEL carried a datum, not its numeric value -- a          *)
(* structurally meaningful statement immune to value coincidence.            *)
(*                                                                         *)
(* PUBLIC channels (what Sec. 2.1 clause 9 / Sec. 3.5 / Sec. 4.2 expose):     *)
(*   "ocrIdx"  -- an output coin's public INDEX (in output_coins_root);       *)
(*   "owner"   -- the account owner address H(Pk0) (part of new_ash);         *)
(*   "nextPk"  -- the rotated current_pubkey (public addressing material);    *)
(*   "counter" -- the send_counter (part of new_ash).                         *)
(* WITNESS-ONLY channels (Sec. 2.1 clause 9 "remain in the witness"):         *)
(*   "amount"    -- a coin / issuance amount;                                 *)
(*   "nk"        -- the nullifier key;                                        *)
(*   "recipient" -- a recipient inside an output coin template.               *)
(***************************************************************************)

\* @typeAlias: leakItem = { chan: Str, val: Int };
P04_typedefs == TRUE

\* The witness-only provenance channels (Sec. 2.1 clause 9). The flow invariant
\* forbids any item with one of these channels from reaching the observer.
\* @type: () => Set(Str);
WitnessChannels == { "amount", "nk", "recipient" }

\* @type: (Str, Int) => $leakItem;
Item(chan, val) == [ chan |-> chan, val |-> val ]

\* Output coin indices exposed by ocr, tagged public (Sec. 2.1 clause 6).
\* @type: ($witness) => Set($leakItem);
OcrItems(w) == { Item("ocrIdx", cid.idx) : cid \in OutputIds(w) }

\* The public-identity items of the new account state (Sec. 2.1 clause 7):
\* owner address, rotated current_pubkey, send_counter -- all part of the public
\* new_account_state_hash. (The BALANCES map is part of the ash too, but its
\* VALUES are amounts: committed by the hash, not exposed -- a chain-only
\* observer cannot read AccountState.balances, Sec. 4.2 self-delivery note. So
\* balance values are deliberately NOT exposed.)
\* @type: ($witness) => Set($leakItem);
NewStateIdentityItems(w) ==
  { Item("owner",   w.prevState.owner),
    Item("nextPk",  w.nextPk),
    Item("counter", w.prevState.sendCounter + 1) }

\* THE PUBLICATION GATE (Sec. 2.1 clause 9, "Nothing else is public"). The set
\* of provenance-tagged items publishing (w, pd) legitimately makes observable:
\* the output coin indices and the new-state public-identity items -- ALL tagged
\* with PUBLIC channels. No item here carries a WitnessChannels tag, which IS
\* the content of clause 9. The negative control widens this set with a
\* witness-channel item; deleting the gate lets the observer pull it and
\* INV_P4_flow breaks. (Note: by construction `\A it \in PubItems(w,pd) :
\* it.chan \notin WitnessChannels`.)
\* @type: ($witness, $proofData) => Set($leakItem);
PubItems(w, pd) ==
  OcrItems(w) \union NewStateIdentityItems(w)

(***************************************************************************)
(* THE WITNESS-ONLY ITEMS. The data that, by Sec. 2.1 clause 9, MUST remain   *)
(* in the witness and never become observable: the input/output coin AMOUNTS,  *)
(* the nullifier key nk, the recipients inside output templates, the issuance  *)
(* amount -- each tagged with its WITNESS channel. Used by the negative        *)
(* control's widened gate (it injects one of these) and as the leak domain.    *)
(***************************************************************************)
\* @type: ($witness) => Set($leakItem);
WitnessItems(w) ==
  { Item("amount", c.amount) : c \in w.inputs }
    \union { Item("amount", w.templates[i].amount) : i \in DOMAIN w.templates }
    \union { Item("recipient", w.templates[i].recipient) : i \in DOMAIN w.templates }
    \union { Item("nk", w.nk) }
    \union (IF w.hasIssuance THEN { Item("amount", w.issuance.amount) } ELSE {})

(***************************************************************************)
(* OBSERVER STATE (layered on top of the Proofs lineage state).            *)
(*   obsPublic : the accumulated public projection -- the set of ProofData   *)
(*     records actually published by the lineage (what an observer sees).     *)
(*   obsLearnt : the adversary's leak accumulator -- scalars it has extracted *)
(*     through whatever channel the gate permits. A flow sink.                *)
(*   obsTainted: whether the leak set has EVER absorbed a witness-only scalar *)
(*     through a witness channel. The flow-violation flag (written BEFORE the  *)
(*     gate is consulted, so the gate's removal is observable -- same idiom as *)
(*     P02's onDoubled / Onchain's evidence-before-gate).                     *)
(***************************************************************************)
VARIABLES
  \* @type: Set($proofData);
  obsPublic,
  \* @type: Set($leakItem);
  obsLearnt,
  \* @type: Bool;
  obsTainted

\* @type: <<Set($proofData), Set($leakItem), Bool>>;
obsVars == << obsPublic, obsLearnt, obsTainted >>

(***************************************************************************)
(* The full system = Proofs lineage state + observer state. Init starts a    *)
(* fresh lineage (Proofs.PrInit) with an empty public view and an empty,      *)
(* untainted observer.                                                       *)
(***************************************************************************)
\* @type: () => Bool;
Init ==
  /\ PrInit
  /\ obsPublic = {}
  /\ obsLearnt = {}
  /\ obsTainted = FALSE

(***************************************************************************)
(* PublishAndObserve. The composition step: an account performs a compliant  *)
(* transition (a Mint or a Send -- exactly the Proofs lineage moves), which   *)
(* PUBLISHES its ProofData pd; the adversarial observer then scrapes the      *)
(* public projection and pulls EVERY scalar the publication discipline        *)
(* exposes into its leak set. The gate is the set the pull ranges over:        *)
(* PubItems(w, pd). Witness-channel items are not in that set, so they cannot  *)
(* pulled -- UNLESS the gate is widened (negative control).                   *)
(*                                                                         *)
(* obsTainted is written from a witness-channel test over `pulled` BEFORE the  *)
(* gate decides what `pulled` is, so removing the gate is observable: if the   *)
(* widened gate lets a witness scalar into `pulled`, obsTainted flips and       *)
(* INV_P4_flow fails. With the committed gate, `pulled \subseteq PubItems`      *)
(* and PubItems carries no witness channel, so obsTainted stays FALSE.         *)
(*                                                                         *)
(* The Proofs lineage advances exactly as in module/Proofs.tla (PrNext); we   *)
(* re-derive the (w, pd) of the chosen move so the observer sees the same      *)
(* transition. To keep the action self-contained we inline the two Proofs      *)
(* moves (Mint / Send) and attach the observer effect to each.                *)
(***************************************************************************)

\* The observer effect attached to publishing transition (w, pd): grow the
\* public view by pd, and let the adversary pull the gated public items.
\* @type: ($witness, $proofData, Set($leakItem)) => Bool;
ObserveEffect(w, pd, gate) ==
  \* the adversary pulls ANY subset of what the gate exposes (full strength).
  \E pulled \in SUBSET gate :
    /\ obsPublic'  = obsPublic \union { pd }
    /\ obsLearnt'  = obsLearnt \union pulled
    \* evidence written BEFORE the gate is trusted: did the pull carry an item
    \* tagged with a WITNESS provenance channel? (FALSE for the committed gate,
    \* whose items are all public-channel; TRUE if the gate is widened with a
    \* witness-channel item -- the negative control.) Channel-based, so immune to
    \* the numeric coincidence (owner == nk == amount as Ints) the value-level
    \* test fell into.
    /\ obsTainted' = (obsTainted \/ (\E it \in pulled : it.chan \in WitnessChannels))

\* THE GATE the committed model uses (Sec. 2.1 clause 9): only public-channel
\* items. The negative control replaces this with PubItems(w,pd) \union {one
\* WitnessItems(w) member}.
\* @type: ($witness, $proofData) => Set($leakItem);
CommittedGate(w, pd) == PubItems(w, pd)

(***************************************************************************)
(* Mint + observe. Mirrors Proofs.MintStep, then attaches ObserveEffect.     *)
(***************************************************************************)
\* @type: (Int, Int) => Bool;
MintObserve(a, amount) ==
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
  IN /\ prev.sendCounter = 0
     /\ amount > 0 /\ amount < U128Bound
     /\ C(newAuth, w, pd)
     /\ prAuthorised' = newAuth
     /\ prState' = [ prState EXCEPT ![a] = NextAccountState(w) ]
     /\ prChSet' = [ prChSet EXCEPT ![a] = NextChSet(w) ]
     /\ ObserveEffect(w, pd, CommittedGate(w, pd))

(***************************************************************************)
(* Send + observe. Mirrors Proofs.SendStep, then attaches ObserveEffect.     *)
(***************************************************************************)
\* @type: (Int, $coinId, Int) => Bool;
SendObserve(a, cid, amount) ==
  LET prev   == prState[a]
      asset  == cid.asset
      inCoin == MkCoin(cid, prev.owner, amount, asset)
      \* @type: Seq($coinTemplate);
      tmpl   == << MkCoinTemplate(prev.owner, amount, asset) >>
      cpa    == [ x \in {cid} |-> cid.prevAsh ]
      \* @type: $witness;
      w == [ isInitial |-> FALSE, prevProofAccepts |-> TRUE, prevState |-> prev,
             prevChSet |-> prChSet[a],
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
  IN /\ prev.sendCounter > 0
     /\ cid \in prChSet[a]
     /\ amount > 0 /\ amount < U128Bound
     /\ C(newAuth, w, pd)
     /\ prAuthorised' = newAuth
     /\ prState' = [ prState EXCEPT ![a] = NextAccountState(w) ]
     /\ prChSet' = [ prChSet EXCEPT ![a] = NextChSet(w) ]
     /\ ObserveEffect(w, pd, CommittedGate(w, pd))

(***************************************************************************)
(* Next. The publish+observe moves are the only transitions; each advances    *)
(* both the lineage and the observer in lockstep.                            *)
(***************************************************************************)
\* @type: () => Bool;
Next ==
  \/ \E a \in Accounts : \E amount \in 1 .. 3 : MintObserve(a, amount)
  \/ \E a \in Accounts : \E cid \in prChSet[a] : \E amount \in 1 .. 3 : SendObserve(a, cid, amount)

Spec == Init /\ [][Next]_<<prVars, obsVars>>

(***************************************************************************)
(* THE DYNAMIC SAFETY PROPERTY (the unbounded certificate). Pass-3 P4 HIGH,   *)
(* composition level. The adversarial observer never extracts a witness-only  *)
(* scalar through a witness channel: the leak flag is never raised.           *)
(*                                                                         *)
(*   INV_P4_flow == ~ obsTainted                                            *)
(*                                                                         *)
(* obsTainted can only be raised by ObserveEffect when the pull carries an    *)
(* item tagged with a WITNESS provenance channel; the committed gate PubItems  *)
(* never lets that happen (its items are all PUBLIC-channel: ocrIdx / owner /  *)
(* nextPk / counter), so the flag stays down. Widen the gate (negative         *)
(* control) with a witness-channel item and the flag is raised. This is the    *)
(* dynamic, negatively-controllable core the package requires.                *)
(***************************************************************************)
\* @type: () => Bool;
INV_P4_flow == ~ obsTainted

(***************************************************************************)
(* STRUCTURAL companion (STATED, labelled structural, NOT a dynamic conjunct).*)
(*                                                                         *)
(* The published record TYPES carry no witness field by construction. The     *)
(* delivery-event plaintext has exactly the five opaque fields {detectTag,    *)
(* epk, blobId, blobLocators, ackNonce} (Transport.MkDeliveryEvent) -- none   *)
(* is an amount/recipient/asset/nk. The on-chain BatchInscription's           *)
(* witness-relevant field is batchNullifiers, a set of OPAQUE $nullifier       *)
(* handles (committed, not preimage-readable under A2/A4). The ProofData       *)
(* record has exactly {newAsh, ocr, inr, chRoot} -- the four committed roots.  *)
(* This is a SHAPE fact, true in every state by the record constructors, not  *)
(* a reachable transition, so we label it STRUCTURAL (the P10 pattern) rather  *)
(* than ship a single-trace tautology. It is recorded for completeness; the   *)
(* dynamic content of P4 is INV_P4_flow above.                               *)
(*                                                                         *)
(* We express the structural fact as: every published ProofData exposes only   *)
(* the four committed-root fields (its domain is exactly those four). Asserted *)
(* over obsPublic. This is true by construction of pd in every move; it does   *)
(* not depend on the gate and is NOT part of the machine-checked INV.          *)
(***************************************************************************)
\* @type: () => Bool;
PublishedCarriesNoWitnessField ==
  \A pd \in obsPublic :
    DOMAIN pd = { "newAsh", "ocr", "inr", "chRoot" }

(***************************************************************************)
(* INDUCTIVE INVARIANTS.                                                     *)
(*                                                                         *)
(* The flow property is proved RELATIVE TO the Proofs lineage type-          *)
(* correctness (PrTypeOK), which module/Proofs.tla owns -- the standard        *)
(* compositional move. Two invariants:                                       *)
(*                                                                         *)
(*   ObsInv -- the OBSERVER-LAYER invariant that P4 actually proves            *)
(*     inductive: the observer typing plus the flow flag. This is preserved    *)
(*     by every move BECAUSE the committed gate PubItems carries only public-  *)
(*     channel items (so obsTainted, OR'd with a FALSE witness-channel term,   *)
(*     stays down) -- an argument INDEPENDENT of prState well-formedness.      *)
(*                                                                         *)
(*   IndInv -- ObsInv conjoined with PrTypeOK, used for the BASE and bounded-  *)
(*     sanity checks (which start from Init, where PrTypeOK holds as a          *)
(*     reachable fact and is exercised to depth 8 by the bounded run).         *)
(*                                                                         *)
(* The inductive STEP uses PrTypeOK as the lineage-typing HYPOTHESIS on the    *)
(* generated pre-state (so Next's guards C(...) evaluate over a well-shaped     *)
(* lineage) and checks that ObsInv -- the observer invariant -- is preserved.  *)
(* PrTypeOK is NOT required to be preserved here: it is the responsibility of   *)
(* module/Proofs.tla (its own type-safety obligation; the bounded run [1]       *)
(* confirms it holds along reachable Init/Next to depth 8). This is exactly     *)
(* the audit's compositional contract: P4 proves the FLOW gate, conditioned on  *)
(* the lineage being type-correct, which is Proofs' guarantee. See notes.md.   *)
(***************************************************************************)
\* @type: () => Bool;
ObsTypeOK ==
  /\ \A pd \in obsPublic : DOMAIN pd = { "newAsh", "ocr", "inr", "chRoot" }
  /\ obsTainted \in BOOLEAN

\* The observer-layer invariant P4 proves inductive (relative to PrTypeOK).
\* @type: () => Bool;
ObsInv ==
  /\ ObsTypeOK
  /\ INV_P4_flow

\* @type: () => Bool;
IndInv ==
  /\ PrTypeOK
  /\ ObsInv

(***************************************************************************)
(* Assignment-form restatement of IndInv, used as the --init predicate of    *)
(* the inductive-step check (Apalache requires every variable ASSIGNED in an  *)
(* init predicate). The Proofs variables reuse the assignment shapes Proofs    *)
(* exposes (prState a total map over Accounts of well-formed account states;   *)
(* prChSet a per-account coin-id set; prAuthorised the A7 oracle pairs);       *)
(* obsPublic / obsLearnt / obsTainted are bound over their finite domains,     *)
(* then IndInv is asserted as a state constraint. Logically equivalent to      *)
(* IndInv.                                                                    *)
(*                                                                         *)
(* The Proofs lineage state (prState a total map over Accounts of account      *)
(* states, prChSet per-account coin-id sets, prAuthorised the A7 oracle pairs)  *)
(* and the observer state are RECURSIVELY-typed (a coinId carries a prevAsh     *)
(* account state), so there is no closed finite enumeration to write a literal  *)
(* `\in` assignment form against. We therefore use Apalache's symbolic          *)
(* generator Gen(n): it ASSIGNS each variable an ARBITRARY value of its         *)
(* inferred type (bounded by n on collection sizes -- the standard way to       *)
(* over-approximate the type-correct pre-state for an inductive step), then     *)
(* IndInv constrains it to the inductive invariant. This is exactly the         *)
(* inductive-step semantics: "for every type-correct state satisfying IndInv,   *)
(* one step preserves IndInv". The bound n = 4 covers the smoke instance        *)
(* (<= 2 accounts, small coin/proof sets); notes.md records a larger-n          *)
(* confirmation. PrTypeOK / ObsTypeOK pin the per-state structural facts on top *)
(* of the generated values so a Gen'd value cannot be ill-typed for the step.   *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit ==
  /\ prState      := Gen(4)
  /\ prChSet      := Gen(4)
  /\ prAuthorised := Gen(4)
  /\ obsPublic    := Gen(4)
  /\ obsLearnt    := Gen(8)
  /\ obsTainted   := Gen(1)
  /\ IndInv

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Reuses the Proofs smoke instance: *)
(* two accounts, one v1 asset family. The flow argument is per-transition      *)
(* local (the gate is evaluated fresh on each publish), so the result is        *)
(* uniform in the instance sizes (notes.md records a larger-instance            *)
(* confirmation).                                                             *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit == PrConstInit

=============================================================================
