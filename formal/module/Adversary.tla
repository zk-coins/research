-------------------------- MODULE Adversary --------------------------
(***************************************************************************)
(* Adversary -- the Pass-3 audit Sec. 2 "Adversary model" encoded as a      *)
(* reusable CAPABILITY INTERFACE. This is a DEFINITIONS module: it owns no   *)
(* state machine. Every property module composes these predicates to scope   *)
(* adversary power uniformly, so the threat boundary is one file rather than  *)
(* re-stated per proof.                                                       *)
(*                                                                         *)
(* THE MODEL (Pass-3 Sec. 2). For every property, the adversary is           *)
(* probabilistic polynomial-time. The interface splits its power into:        *)
(*   - the MAY set: everything the PPT adversary is FREE to do, modelled as   *)
(*     "any party in a controlled set may act arbitrarily" predicates plus    *)
(*     the AdversaryActionAllowed gate; and                                   *)
(*   - the MAY-NOT set: the trust boundary A1-A14 (plus the SPEND-branch and  *)
(*     deep-reorg carve-outs), modelled NOT as fresh axioms but by REUSING    *)
(*     the Assumptions oracles -- the adversary is BOUNDED by exactly the     *)
(*     same SigValid / KnowledgeSound / CanDecrypt / ReorgWithinBound the     *)
(*     honest protocol relies on. WHY this shape: the audit's safety          *)
(*     arguments hold "for any PPT adversary"; encoding MAY-NOT as the        *)
(*     negation of the cryptographic oracles means a module cannot accidently *)
(*     grant the adversary a forgery/decryption/proof-break it then "proves"  *)
(*     safe against. The boundary is the oracle, by construction.             *)
(*                                                                         *)
(* WHAT IS *NOT* HERE. The 2^128 work bound and "PPT" are meta-level: TLA+    *)
(* is unconditional, so computational hardness is delegated to the           *)
(* Assumptions oracles (a forgery the adversary "cannot compute" is exactly   *)
(* a (pk,msg) the honest signer never put in `authorised`). We therefore do   *)
(* not model a work budget as a number; AdvWorkBounded records the assumption *)
(* as a always-true marker so the dependency is visible to readers.          *)
(***************************************************************************)
EXTENDS Integers, Foundations, Assumptions

(***************************************************************************)
(* Type aliases for the adversary's controlled resources. A model fixes      *)
(* finite carriers (keys, parties) drawn from Foundations' Int domains; the   *)
(* adversary "controls" a subset of each. Controlled sets are the only new    *)
(* state shape this interface introduces.                                     *)
(***************************************************************************)

\* @typeAlias: advCaps = { keys: Set(Int), parties: Set(Int), relays: Set(Int) };
Adversary_typedefs == TRUE

(***************************************************************************)
(* CONTROL PRIMITIVES. `controlled` is whichever resource set is in scope     *)
(* (keys, parties/nodes, relays). These two operators are the vocabulary the  *)
(* rest of the interface -- and every consuming module -- speaks in.          *)
(***************************************************************************)

\* The adversary controls resource x iff x is in the controlled set.
\* @type: (Set(Int), Int) => Bool;
AdvControls(controlled, x) == x \in controlled

\* Dual: pk is an HONEST key iff the adversary does NOT control it. This is the
\* victim/honest-party predicate the SPEND-branch carve-out builds on.
\* @type: (Set(Int), Int) => Bool;
HonestKey(controlled, pk) == pk \notin controlled

(***************************************************************************)
(* MAY -- the capabilities the PPT adversary is free to exercise (Pass-3      *)
(* Sec. 2 bullet list). Each is "true": within its controlled set the         *)
(* adversary may do this arbitrarily. They are exposed as named predicates so  *)
(* a module can `ASSUME` them or branch on the enabling-condition explicitly  *)
(* rather than smuggling adversary freedom in by omission.                    *)
(***************************************************************************)

\* Run arbitrary users/accounts/addresses/seeds: any party the adversary
\* controls may take any honest-shaped action. Modelled as the membership test
\* itself -- there is no extra restriction on a controlled party.
\* @type: (Set(Int), Int) => Bool;
AdvMayRunParty(parties, p) == AdvControls(parties, p)

\* Run arbitrary publishers: a controlled publisher chooses which records to
\* publish, in which order, and the `block_anchor`. We expose only the
\* permission; the *content* it may choose lives in Onchain.tla. The block-
\* anchor choice is unconstrained EXCEPT it is still bounds-checked at
\* admission (Onchain Sec. 3.5) -- the adversary may pick a bad anchor, but an
\* honest verifier rejects it. So the MAY is unconditional here.
\* @type: (Set(Int), Int) => Bool;
AdvMayPublish(parties, publisher) == AdvControls(parties, publisher)

\* Run arbitrary nodes/relays: a controlled node may choose delivery,
\* retention, pull responses, and ordering freely (it may drop, delay, reorder,
\* or lie in any answer to a delegating wallet).
\* @type: (Set(Int), Int) => Bool;
AdvMayControlNode(parties, node) == AdvControls(parties, node)

\* Control ALL Nostr relays the victim queries, subject only to Sec. 4.6
\* replication. The DA discipline guarantees k=3 independent holders; the
\* adversary's relay control is total UNLESS that would require suppressing all
\* k replicas. `honestReplicas` is the count of replicas outside adversary
\* control; the relay-control freedom is admissible while at least one honest
\* replica remains reachable (the Sec. 4.6 carve-out the audit names).
\* @type: (Int) => Bool;
AdvMayControlRelays(honestReplicas) == honestReplicas >= 1

\* Observe Bitcoin in full and submit Bitcoin transactions. Always permitted:
\* the chain is public and anyone may broadcast. No controlled-set gate.
\* @type: () => Bool;
AdvMayObserveBitcoin == TRUE

\* @type: () => Bool;
AdvMaySubmitBitcoinTx == TRUE

\* Mount network attacks on victim<->peer-node links, subject to A14 (the pull
\* endpoint's channel binding authenticates the host). The attack is admissible
\* only when it respects that binding: a proof presented to one host cannot be
\* replayed to another. ChanBindMatches is the A14 oracle from Assumptions.
\* @type: (Int, Int) => Bool;
AdvMayNetworkAttack(presentedHost, servingHost) ==
  ChanBindMatches(presentedHost, servingHost)

\* Mount computation up to the security parameter (~2^128). Meta-level: TLA+ is
\* unconditional, so hardness is delegated to the Assumptions oracles. Recorded
\* as an always-true marker so the dependency is explicit to a reader.
\* @type: () => Bool;
AdvWorkBounded == TRUE

(***************************************************************************)
(* MAY-NOT -- the trust boundary (Pass-3 Sec. 2). Each operator states what    *)
(* the adversary CANNOT achieve, expressed as a constraint over the SAME       *)
(* Assumptions oracles the honest side uses. A module that lets the adversary  *)
(* mutate state must preserve these; they are the obligations a "scoped"       *)
(* adversary respects.                                                         *)
(***************************************************************************)

\* A7 (BIP-340 EUF-CMA): cannot forge. For a key it does not control, the
\* adversary cannot make a (pk,msg) verify. `advExtended` is the authorised set
\* AFTER any signing actions the adversary took; the boundary says that for an
\* honest pk, no message the honest signer did not actually sign is in it --
\* i.e. the adversary may only have added pairs for keys it controls. WHY this
\* form: it forbids the one move that would break P1/P7/P8/P10 -- silently
\* growing `authorised` for a victim key.
\* @type: (Set(<<Int, Int>>), Set(<<Int, Int>>), Set(Int), Int, Int) => Bool;
AdvCannotForge(honestAuthorised, advExtended, controlledKeys, pk, msgTag) ==
  HonestKey(controlledKeys, pk) =>
    (SigValid(advExtended, pk, msgTag) => SigValid(honestAuthorised, pk, msgTag))

\* A1 (Plonky2 knowledge-soundness): cannot break proofs. If the adversary's
\* proof verifies, its statement holds -- there is no accepting-but-false proof
\* available to the adversary. Direct reuse of the KnowledgeSound oracle.
\* @type: (Bool, Bool) => Bool;
AdvCannotBreakProof(proofAccepts, statementHolds) ==
  KnowledgeSound(proofAccepts, statementHolds)

\* A15: nor can it pass a half-aggregation check with any invalid member.
\* @type: (Set(Bool)) => Bool;
AdvCannotForgeAggregate(memberValidities) ==
  AggSoundValid(memberValidities) => (\A v \in memberValidities : v = TRUE)

\* A8-A11 (transport confidentiality): cannot decrypt without holding the key.
\* For a per-object key whose holder set excludes the adversary, the adversary
\* cannot decrypt. `keyHolders` are the legitimate deriving parties; if no
\* controlled party is among them, CanDecrypt is false for the adversary.
\* @type: (Set(Int), Set(Int)) => Bool;
AdvCannotDecrypt(keyHolders, controlledParties) ==
  (\A w \in controlledParties : ~CanDecrypt(keyHolders, w))
  \/ (\E w \in controlledParties : w \in keyHolders)

\* The one trust root (Pass-3 Sec. 2; Architecture Sec. 6.6): the victim's
\* SPEND branch (sk0 / nk) is never compromised. Modelled as: the set of keys
\* the adversary controls is disjoint from the victim's SPEND-branch keys.
\* @type: (Set(Int), Set(Int)) => Bool;
AdvCannotCompromiseSpend(controlledKeys, victimSpendKeys) ==
  controlledKeys \cap victimSpendKeys = {}

\* A12 (Bitcoin honest-majority): cannot mount a >=6-block reorg. A proposed
\* reorg the adversary can effect is bounded below finality depth K=6; a deeper
\* reorg is outside the model (a protocol-failure event, not a transition).
\* Direct reuse of the ReorgWithinBound oracle.
\* @type: (Int) => Bool;
AdvReorgBounded(depth) == ReorgWithinBound(depth)

(***************************************************************************)
(* THE SCOPING GATE. A consuming module classifies a proposed adversary       *)
(* `action` against the boundary. An action is ALLOWED iff it stays inside     *)
(* the MAY set, which here means: it does not require any MAY-NOT capability.  *)
(* We pass the boundary outcomes the module computed (each a Bool that is TRUE *)
(* when the corresponding boundary is RESPECTED) and require their            *)
(* conjunction. This keeps the gate composable: a module supplies whichever    *)
(* boundaries its action could touch.                                         *)
(***************************************************************************)

\* AdversaryActionAllowed: the action respects every boundary it touches.
\* `respectsBoundaries` is the set of per-boundary respect-flags the calling
\* module evaluated (e.g. {AdvCannotForge(...), AdvReorgBounded(...)}); an empty
\* set means the action touches no boundary and is trivially allowed (a pure
\* MAY action such as observing Bitcoin).
\* @type: (Set(Bool)) => Bool;
AdversaryActionAllowed(respectsBoundaries) ==
  \A respected \in respectsBoundaries : respected = TRUE

(***************************************************************************)
(* Definitions-only module: no VARIABLEs. TypeOK is a placeholder so the      *)
(* file is uniformly checkable alongside the state-machine modules.           *)
(***************************************************************************)

\* @type: () => Bool;
TypeOK == TRUE

=============================================================================
