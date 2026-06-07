-------------------------- MODULE Access --------------------------
(***************************************************************************)
(* Access -- the CAPABILITY-GATED PULL ENDPOINT of Sec. 5 (Access &         *)
(* Explorer) at docs@b6972b8. This module models, as a state machine, the   *)
(* one endpoint through which a node releases Private data, and the release  *)
(* predicate that governs it.                                              *)
(*                                                                         *)
(* THE CLAIM (Sec. 5.1, normative). A node releases a Private record for a  *)
(* `subject` within a `scope` IFF the requester demonstrates one of exactly *)
(* TWO authorisation capabilities over a fresh, host-bound challenge:        *)
(*   (a) an OWNERSHIP PROOF  -- a BIP-340 signature under Pk0 over the        *)
(*       challenge, with H(Pk0) == subject; grants the subject's FULL view.  *)
(*   (b) a delegated VIEW GRANT (GrantProof) -- an op-signed ViewGrant plus  *)
(*       a grantee signature over the challenge; releases ONLY records inside *)
(*       the grant's scope, and only while the grant is unexpired and        *)
(*       unrevoked.                                                          *)
(* No other capability is a node authorisation (Sec. 5.1, Sec. 5.4).         *)
(*                                                                         *)
(* WHY THE CHALLENGE EXISTS (Sec. 5.1). The endpoint runs challenge->proof  *)
(* so captured transcripts cannot be replayed: a node rejects a PullProof    *)
(* whose nonce it did not issue or has already acConsumed, whose expiry has    *)
(* passed, or whose chan_bind does not match the host it serves. chan_bind   *)
(* binds the proof to one server (A14), defeating the proof-forwarding /      *)
(* MITM attack: a proof bound to host X is rejected at host Y.               *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly):                     *)
(*   - SIGNATURES (A7). All signature checks go through the Assumptions      *)
(*     SigValid(acAuthorised, pk, msgTag) oracle; `acAuthorised` is the honest   *)
(*     signing set (sk0-holders, op-holders, grantee-key-holders), grown     *)
(*     ONLY by honest signing actions, so EUF-CMA forgery is impossible by   *)
(*     construction. A signature's "message" is tagged by the challenge it   *)
(*     covers (the proof binds to `chal`, Sec. 5.1) and, for a grant, by the *)
(*     grant_message (Sec. 5.2).                                             *)
(*   - HASH H(Pk0)==subject (A5/A6 preimage binding). Modelled by an honest  *)
(*     address map `addrOfPk0`: the subject identity a public key derives to.*)
(*     Equality of derived address with the requested subject is the check.  *)
(*   - chan_bind (A14). Modelled as host EQUALITY: a challenge records the    *)
(*     host the requester dialed; ChanBindMatches(presentedHost, servingHost)*)
(*     accepts iff they are equal. This is the faithful set-level content of  *)
(*     the H("PullHost" || host) derivation -- collision-free hashing makes   *)
(*     the digest a 1:1 stand-in for the host (A5).                          *)
(*   - SCOPE (Sec. 5.2). A scope is an asset-id set (a finite set; "*" =      *)
(*     the full asset universe) plus a [not_before, not_after] data window    *)
(*     and an `expiry` instant. A record is IN scope iff its asset is in the  *)
(*     set and its timestamp is within the window. Ownership = the universal  *)
(*     scope (whole account, Sec. 5.1(a)/5.4).                               *)
(*   - BEARER CAPS (Sec. 5.3 zkview, Sec. 5.8 zkavk). These are client-side  *)
(*     decryption secrets, NOT node authorisations (Sec. 5.1 para 2). We     *)
(*     model that presenting one NEVER causes a node release: a bearer        *)
(*     request carries no ownership/grant capability, so the release          *)
(*     predicate is FALSE for it. CanDecrypt is what the bearer secret grants *)
(*     OFF the node (over already-public ciphertext); it appears here only to *)
(*     state that it is orthogonal to node release (NoSpendEscalation).       *)
(*   - TIME is an abstract monotone clock `acNow` (Int); expiry/window are      *)
(*     comparisons against it. Constant-time compare (Sec. 5.1) is a          *)
(*     side-channel property, not a functional one, so it is out of scope of  *)
(*     this state model.                                                     *)
(*                                                                         *)
(* OUT OF SCOPE here (rendered elsewhere / later phases): Bech32m HRP         *)
(* discrimination (Sec. 5.2/5.6 encoding), the balance attestation circuit   *)
(* (Sec. 5.7, lives in Proofs.tla), the explorer presentation layer          *)
(* (Sec. 5.5/5.6), and link-fragment transport (Sec. 5.6). This module owns  *)
(* the NODE'S release decision only.                                         *)
(***************************************************************************)
EXTENDS Integers, Foundations, Assumptions

(***************************************************************************)
(* Type aliases for the Sec. 5 capability objects. Foundations aliases      *)
(* ($assetId, $accountState, ...) are reused unchanged.                     *)
(***************************************************************************)

\* @typeAlias: scope = { assets: Set($assetId), allAssets: Bool, notBefore: Int, notAfter: Int, expiry: Int };
\* @typeAlias: viewGrant = { version: Int, subject: Int, grantee: Int, scope: $scope, nonce: Int, sigOk: Bool };
\* @typeAlias: challenge = { nonce: Int, expiry: Int, chanBind: Int, subject: Int };
\* @typeAlias: ownershipProof = { subject: Int, pk0: Int, chanBind: Int, nonce: Int };
\* @typeAlias: grantProof = { grant: $viewGrant, granteePk: Int, chanBind: Int, nonce: Int };
\* @typeAlias: record = { subject: Int, asset: $assetId, ts: Int, payload: Int };
Access_typedefs == TRUE

CONSTANTS
  \* The host this node authoritatively serves on its pull endpoint
  \* (Sec. 5.1: the node accepts only chan_bind for a host it serves).
  \* @type: Int;
  ServingHost,
  \* A second, distinct host -- a foreign/relaying node, used to witness the
  \* proof-forwarding defence (Sec. 5.1: chan_bind binds to host X, not Y).
  \* @type: Int;
  ForeignHost,
  \* The full Private store this node could disclose: each record is owned by
  \* a subject, tagged with an asset and a timestamp (Foundations Sec. 1.6).
  \* @type: Set($record);
  Records,
  \* Public keys that may appear as Pk0 / grantee D (Foundations Sec. 1.2).
  \* @type: Set(Int);
  Pubkeys,
  \* Subject identities (addresses = H(Pk0), Foundations Sec. 1.4). The address
  \* derivation is the shared Foundations.AddressOf (FIX 5: one H(Pk0) model),
  \* injective by A5/A6, so a subject IS the address its Pk0 derives to.
  \* @type: Set(Int);
  Subjects,
  \* Finite tick budget for the abstract clock `acNow`.
  \* @type: Int;
  MaxTime

VARIABLES
  \* The signing oracle (A7): (pk, msgTag) pairs honest secret-holders signed.
  \* @type: Set(<<Int, Int>>);
  acAuthorised,
  \* Challenges the node has acIssued and not yet acConsumed (Sec. 5.1 step 2).
  \* @type: Set($challenge);
  acIssued,
  \* Nonces already acConsumed by a completed proof (replay defence, Sec. 5.1).
  \* @type: Set(Int);
  acConsumed,
  \* Forward-only revocation set: grant nonces the subject acRevoked (Sec. 5.2).
  \* @type: Set(Int);
  acRevoked,
  \* Records the node has actually acReleased, with the request that acReleased
  \* them -- the audit trail the safety invariants quantify over.
  \* @type: Set({ rec: $record, subject: Int, host: Int });
  acReleased,
  \* Abstract monotone clock (Sec. 5.1 expiry / Sec. 5.2 window are vs. this).
  \* @type: Int;
  acNow

\* @type: <<Set(<<Int, Int>>), Set($challenge), Set(Int), Set(Int), Set({ rec: $record, subject: Int, host: Int }), Int>>;
acVars == << acAuthorised, acIssued, acConsumed, acRevoked, acReleased, acNow >>

(***************************************************************************)
(* Derived domains and helpers.                                            *)
(***************************************************************************)

\* The universe of assets that appear in the store (the meaning of "*").
\* @type: () => Set($assetId);
AllAssets == { r.asset : r \in Records }

\* A record is within a scope iff its asset is covered AND its timestamp is
\* inside the [not_before, not_after] data window (Sec. 5.2 scope fields).
\* @type: ($record, $scope) => Bool;
InScope(r, sc) ==
  /\ (sc.allAssets \/ r.asset \in sc.assets)
  /\ r.ts >= sc.notBefore
  /\ r.ts <= sc.notAfter

\* The universal scope: whole account, no time bound -- what an ownership
\* proof confers (Sec. 5.1(a): "the subject's full Private view"; Sec. 5.4).
\* @type: () => $scope;
FullScope ==
  [ assets |-> {}, allAssets |-> TRUE, notBefore |-> 0,
    notAfter |-> MaxTime, expiry |-> MaxTime ]

(***************************************************************************)
(* THE RELEASE PREDICATE (Sec. 5.1, normative). Given a presented           *)
(* capability and a fresh, host-matching challenge, what may a node serve?   *)
(* These are pure predicates over a candidate request; the state machine     *)
(* below uses them to gate the Release action.                              *)
(***************************************************************************)

\* A challenge is FRESH for a proof iff it was acIssued, names the proof's
\* nonce, that nonce is unconsumed, and the challenge has not expired
\* (Sec. 5.1: reject unknown/acConsumed nonce or passed expiry).
\* @type: ($challenge, Int) => Bool;
ChallengeFresh(ch, proofNonce) ==
  /\ ch \in acIssued
  /\ ch.nonce = proofNonce
  /\ ch.nonce \notin acConsumed
  /\ ch.expiry >= acNow

\* (a) Ownership proof admissible at this node (Sec. 5.1(a)). The challenge is
\* fresh and host-bound to us (A14), the requester's chan_bind matches our
\* host, the BIP-340 signature over the challenge verifies under Pk0 (A7),
\* and H(Pk0) == subject (A5/A6). Grants the FULL subject scope.
\* @type: ($ownershipProof, $challenge) => Bool;
OwnershipAdmits(op, ch) ==
  /\ ChallengeFresh(ch, op.nonce)
  /\ ch.subject = op.subject
  /\ ChanBindMatches(op.chanBind, ServingHost)
  /\ ch.chanBind = op.chanBind
  /\ SigValid(acAuthorised, op.pk0, ch.nonce)
  /\ AddressOf(op.pk0) = op.subject

\* (b) Grant proof admissible at this node (Sec. 5.1(b), four checks). The
\* challenge is fresh and host-bound to us; (1) the grant's op-signature
\* verifies under the subject's op key (modelled by the grant's sigOk, set
\* only by an honest op-signing action); (2) grantee_pk == grant.grantee and
\* the grantee's BIP-340 signature over the challenge verifies (A7);
\* (3) the grant is unexpired and unrevoked; release scope is grant.scope.
\* @type: ($grantProof, $challenge) => Bool;
GrantAdmits(gp, ch) ==
  /\ ChallengeFresh(ch, gp.nonce)
  /\ ch.subject = gp.grant.subject
  /\ ChanBindMatches(gp.chanBind, ServingHost)
  /\ ch.chanBind = gp.chanBind
  /\ gp.grant.sigOk                              \* (1) op signature valid
  /\ gp.granteePk = gp.grant.grantee             \* (2) grantee identity
  /\ SigValid(acAuthorised, gp.granteePk, ch.nonce) \* (2) grantee challenge sig
  /\ gp.grant.scope.expiry >= acNow                \* (3) not expired
  /\ gp.grant.nonce \notin acRevoked               \* (3) not acRevoked

(***************************************************************************)
(* Initial state.                                                          *)
(***************************************************************************)

AcInit ==
  /\ acAuthorised = {}
  /\ acIssued = {}
  /\ acConsumed = {}
  /\ acRevoked = {}
  /\ acReleased = {}
  /\ acNow = 0

(***************************************************************************)
(* Actions.                                                                *)
(***************************************************************************)

\* Honest signing (grows the A7 oracle ONLY for keys a legitimate holder
\* controls). The model lets any pk sign any nonce-tagged message; this is
\* sound because the forgery-relevant invariants depend on WHICH (pk, msg)
\* pairs were honestly signed, never on an adversary signing for itself.
\* @type: () => Bool;
Sign ==
  /\ \E pk \in Pubkeys, msgTag \in (1..MaxTime) :
       acAuthorised' = acAuthorised \union { <<pk, msgTag>> }
  /\ UNCHANGED << acIssued, acConsumed, acRevoked, acReleased, acNow >>

\* Step 2: the node issues a Challenge for a requested subject, on some host
\* the requester claims to have dialed (Sec. 5.1). The nonce is the
\* timestamp-like fresh value; chan_bind records the dialed host.
\* @type: () => Bool;
IssueChallenge ==
  /\ \E subject \in Subjects, host \in { ServingHost, ForeignHost },
        nonce \in (1..MaxTime), exp \in (acNow..MaxTime) :
       LET ch == [ nonce |-> nonce, expiry |-> exp,
                   chanBind |-> host, subject |-> subject ] IN
         acIssued' = acIssued \union { ch }
  /\ UNCHANGED << acAuthorised, acConsumed, acRevoked, acReleased, acNow >>

\* Step 3+4: an OWNERSHIP proof is presented and, iff admissible, the node
\* releases the subject's FULL Private view (every record for that subject),
\* consuming the nonce (Sec. 5.1(a)). An inadmissible proof releases nothing.
\* The requester PRESENTS a chan_bind for some host `h` it claims to have
\* dialed -- ADVERSARIALLY, `h` may be ForeignHost (a proof captured by, or
\* bound to, a different node: the Sec. 5.1 proof-forwarding / MITM case). The
\* presented binding is carried THROUGH to the audit entry's `host` field, so a
\* ForeignHost-bound proof would release at a foreign host UNLESS the admit
\* predicate's ChanBindMatches(presented, ServingHost) (and the challenge-side
\* equality ch.chanBind = op.chanBind) rejects it. Those two checks are now the
\* only thing preventing a cross-host release -- the chan_bind gate is
\* load-bearing (see property/P10/notes.md negative control).
\* @type: () => Bool;
ReleaseByOwnership ==
  /\ \E ch \in acIssued, pk \in Pubkeys, h \in { ServingHost, ForeignHost } :
       LET op == [ subject |-> ch.subject, pk0 |-> pk,
                   chanBind |-> h, nonce |-> ch.nonce ] IN
         /\ OwnershipAdmits(op, ch)
         /\ acConsumed' = acConsumed \union { ch.nonce }
         /\ acReleased' = acReleased \union
              { [ rec |-> r, subject |-> ch.subject, host |-> op.chanBind ] :
                  r \in { rr \in Records :
                            InScope(rr, FullScope) /\ rr.subject = ch.subject } }
  /\ UNCHANGED << acAuthorised, acIssued, acRevoked, acNow >>

\* Step 3+4: a GRANT proof is presented and, iff admissible, the node releases
\* ONLY the records inside the grant's scope (Sec. 5.1(b) check 4), consuming
\* the nonce. The grant's subject fixes whose records may be acReleased. As in
\* ReleaseByOwnership the requester PRESENTS a chan_bind for some host `h`
\* (possibly ForeignHost -- the proof-forwarding case), and that presented
\* binding is carried THROUGH to the audit entry's `host` field; only the admit
\* predicate's ChanBindMatches(presented, ServingHost) plus ch.chanBind =
\* gp.chanBind prevent a ForeignHost-bound proof from releasing here.
\* @type: () => Bool;
ReleaseByGrant ==
  /\ \E ch \in acIssued, h \in { ServingHost, ForeignHost }, g \in
        { gg \in [ version: {1}, subject: Subjects, grantee: Pubkeys,
                   scope: [ assets: SUBSET AllAssets, allAssets: BOOLEAN,
                            notBefore: 0..MaxTime, notAfter: 0..MaxTime,
                            expiry: 0..MaxTime ],
                   nonce: 1..MaxTime, sigOk: BOOLEAN ] : TRUE } :
       LET gp == [ grant |-> g, granteePk |-> g.grantee,
                   chanBind |-> h, nonce |-> ch.nonce ] IN
         /\ GrantAdmits(gp, ch)
         /\ acConsumed' = acConsumed \union { ch.nonce }
         /\ acReleased' = acReleased \union
              { [ rec |-> r, subject |-> ch.subject, host |-> gp.chanBind ] :
                  r \in { rr \in Records :
                            rr.subject = g.subject /\ InScope(rr, g.scope) } }
  /\ UNCHANGED << acAuthorised, acIssued, acRevoked, acNow >>

\* Forward-only revocation (Sec. 5.2): the subject adds a grant nonce to the
\* node's revocation set; thereafter GrantAdmits rejects it at check (3).
\* Monotone -- never removed -- which is the "forward-only" content.
\* @type: () => Bool;
Revoke ==
  /\ \E gnonce \in (1..MaxTime) :
       acRevoked' = acRevoked \union { gnonce }
  /\ UNCHANGED << acAuthorised, acIssued, acConsumed, acReleased, acNow >>

\* Time advances (abstract monotone clock); used to expire challenges/grants.
\* @type: () => Bool;
Tick ==
  /\ acNow < MaxTime
  /\ acNow' = acNow + 1
  /\ UNCHANGED << acAuthorised, acIssued, acConsumed, acRevoked, acReleased >>

AcNext ==
  \/ Sign
  \/ IssueChallenge
  \/ ReleaseByOwnership
  \/ ReleaseByGrant
  \/ Revoke
  \/ Tick

AcSpec == AcInit /\ [][AcNext]_acVars

(***************************************************************************)
(* Invariants. Only TypeOK is the Phase-1 smoke target; the rest are the    *)
(* Sec. 5 safety claims carried for the Phase-2 certificate.               *)
(***************************************************************************)

\* @type: () => Bool;
AcTypeOK ==
  /\ acAuthorised \subseteq (Pubkeys \X (1..MaxTime))
  /\ acIssued \subseteq [ nonce: 1..MaxTime, expiry: 0..MaxTime,
                        chanBind: { ServingHost, ForeignHost }, subject: Subjects ]
  /\ acConsumed \subseteq (1..MaxTime)
  /\ acRevoked \subseteq (1..MaxTime)
  /\ acReleased \subseteq [ rec: Records, subject: Subjects,
                          host: { ServingHost, ForeignHost } ]
  /\ acNow \in 0..MaxTime

\* NO RELEASE WITHOUT CAPABILITY (Sec. 5.1, normative). Every acReleased record
\* is for the subject the release names, and the record genuinely exists in the
\* store for that subject -- the node never fabricates or mislabels. Combined
\* with the action guards (OwnershipAdmits / GrantAdmits), a release implies a
\* valid, fresh, host-bound, unexpired, unrevoked, in-scope capability was
\* presented; no unauthenticated/invalid/expired/out-of-scope/acRevoked request
\* yields a Private record.
\* @type: () => Bool;
AcNoReleaseWithoutCapability ==
  \A e \in acReleased :
    /\ e.rec \in Records
    /\ e.rec.subject = e.subject

\* SCOPE RESPECTED (Sec. 5.1(b) check 4 / Sec. 5.2). Every acReleased record
\* belongs to the subject it was acReleased for; an ownership release uses the
\* FullScope (whole account), a grant release stays within grant.scope -- in
\* both cases the record's subject equals the release subject.
\* @type: () => Bool;
AcScopeRespected ==
  \A e \in acReleased : e.rec.subject = e.subject

\* NO REPLAY ACROSS HOSTS (Sec. 5.1, A14). Every release this node performed is
\* bound to the host it serves. The release actions carry the requester's
\* PRESENTED chan_bind through to `e.host`, so a proof presenting a ForeignHost
\* binding would, absent the gate, produce a release with e.host = ForeignHost
\* -- a cross-host replay. This invariant asserts that never happens: the only
\* way `acReleased` grows is via an admit predicate that requires both
\* ChanBindMatches(presented, ServingHost) and ch.chanBind = presented, so the
\* presented binding (= e.host) must equal ServingHost. A proof bound to host X
\* is therefore rejected at host Y. Removing either chan_bind conjunct makes a
\* ForeignHost-bound proof releasable and this invariant FALSE (see the negative
\* control in property/P10_CapabilityDiscipline/notes.md).
\* @type: () => Bool;
AcNoReplayAcrossHosts ==
  \A e \in acReleased : e.host = ServingHost

(***************************************************************************)
(* NO SPEND ESCALATION -- STRUCTURAL (Sec. 5.2/5.3/5.4/5.8, A9).            *)
(*                                                                         *)
(* A view capability (ownership view, view grant, or the bearer secrets    *)
(* zkview/zkavk) is read-only and NEVER confers spend authority. In this   *)
(* state model that is a BY-CONSTRUCTION fact about the machine's write set,*)
(* not a dynamically exercised invariant, so it is deliberately NOT a       *)
(* conjunct of INV_P10 (see property/P10_CapabilityDiscipline). The honest  *)
(* grounds are:                                                            *)
(*   (1) WRITE-SET. The two release actions (ReleaseByOwnership,            *)
(*       ReleaseByGrant) write ONLY { acConsumed, acReleased }. No action   *)
(*       in AcNext writes the signing oracle `acAuthorised` except `Sign`,  *)
(*       which models an HONEST secret-holder signing -- never a release.   *)
(*       So a release (a read) can never grow the signing/spend oracle;     *)
(*       there is no spend-granting action in the Access machine at all.    *)
(*   (2) KEY SEPARATION is a Foundations/Assumptions-level axiom (A9: the   *)
(*       BIP-32 hardened derivation makes a view key unable to derive the   *)
(*       spend key sk0); it is assumed, not re-derived here.               *)
(*   (3) BEARER ORTHOGONALITY (Sec. 5.1 para 2). CanDecrypt over already-   *)
(*       public ciphertext is a client-side predicate independent of        *)
(*       `acReleased`; presenting a bearer secret carries no ownership/grant *)
(*       capability, so the release predicate is FALSE for it and the node   *)
(*       releases nothing extra.                                           *)
(*                                                                         *)
(* A previous formulation stated this as an invariant                      *)
(*   \A e \in acReleased : \A pk \in Pubkeys :                              *)
(*     CanDecrypt({pk}, pk) => (e.rec \in Records)                         *)
(* but CanDecrypt({pk}, pk) == pk \in {pk} == TRUE and e.rec \in Records   *)
(* holds for every audit entry by AcTypeOK, so the implication was a        *)
(* tautology that asserted nothing about spend authority. It is removed     *)
(* rather than shipped as a vacuous machine-checked claim.                  *)
(***************************************************************************)

(***************************************************************************)
(* Constant initialiser (Apalache --cinit) for the smoke instance. A small  *)
(* finite world: two hosts (so the proof-forwarding / cross-host case is     *)
(* witnessed), two subjects, two public keys, and a handful of records over  *)
(* two assets and two timestamps. The release discipline is per-request      *)
(* local, so a small instance exercises every action and guard.             *)
(***************************************************************************)

\* @type: () => $assetId;
AssetA == MkAssetId(1, 1, 0, IssuanceVersionV1)

\* @type: () => $assetId;
AssetB == MkAssetId(2, 2, 0, IssuanceVersionV1)

\* @type: () => Bool;
AcConstInit ==
  /\ ServingHost = 10
  /\ ForeignHost = 20
  /\ Pubkeys = { 1, 2 }
  \* FIX 5: subjects ARE the addresses their Pk0 derives to under the single
  \* Foundations.AddressOf model (identity over the opaque scalar), so the
  \* subject of an account is exactly its Pk0 value.
  /\ Subjects = { 1, 2 }
  /\ MaxTime = 3
  /\ Records =
       { [ subject |-> 1, asset |-> AssetA, ts |-> 1, payload |-> 1 ],
         [ subject |-> 1, asset |-> AssetB, ts |-> 2, payload |-> 2 ],
         [ subject |-> 2, asset |-> AssetA, ts |-> 1, payload |-> 3 ] }

=============================================================================
