-------------------------- MODULE Transport --------------------------
(***************************************************************************)
(* Transport -- the encrypted bundle-trDelivery layer (spec Sec. 4) as a     *)
(* state machine, at commit docs@ed7fdece (spec-v1.1 = b6972b8 +            *)
(* docs#46/#47/#48).                                                        *)
(*                                                                         *)
(* WHAT THIS MODULE IS. The wire/relay layer that moves an encrypted        *)
(* CoinProof bundle from a sender to a recipient (or to the sender's OWN    *)
(* account, Sec. 4.2 self-trDelivery) reliably and confidentially. It models *)
(* the three load-bearing transport guarantees the spec makes normative:    *)
(*   (1) RELIABLE DELIVERY -- ACK+retry with a per-attempt freshness nonce  *)
(*       (Sec. 4.2 "ACK + retry", audit item F17).                          *)
(*   (2) DURABLE CUSTODY  -- the sender retention rule: do NOT drop the     *)
(*       only copy until BOTH a valid ACK AND k-independent replication are *)
(*       confirmed (Sec. 4.2 + Sec. 4.6, k = 3 default, MUST NOT be < 2).   *)
(*   (3) CONFIDENTIALITY  -- only the ivk/K_tx holder can decrypt; the      *)
(*       relay/eavesdropper holds neither and learns only the opaque        *)
(*       envelope (Sec. 4.1, Sec. 4.7), so availability is never safety     *)
(*       (Sec. 4.6 safety invariant).                                       *)
(*                                                                         *)
(* THE TRUST MODEL (Sec. 4.1). The transport key is `op`, a BIP-340 key     *)
(* that runs the node's Nostr relay and MUST NOT be able to spend. A relay  *)
(* is trusted only for AVAILABILITY and metadata minimisation, never for    *)
(* correctness: it can WITHHOLD a bundle but can neither forge nor alter    *)
(* one (the recipient re-verifies every bundle, Sec. 4.5). That is why the  *)
(* safety invariant below holds even when bundles are dropped/unavailable.  *)
(*                                                                         *)
(* MODELLING ABSTRACTIONS (deliberate, stated openly):                     *)
(*   - NIP-44 v2 encryption + NIP-59 gift-wrap (Sec. 4.2 steps 1,4) are NOT *)
(*     modelled byte-for-byte. Their only logical content here is "who can  *)
(*     read the plaintext", captured by Assumptions.CanDecrypt over the     *)
(*     per-object key-holder set (axioms A8-A11). The relay/eavesdropper is *)
(*     simply absent from every holder set, so it decrypts nothing.         *)
(*   - POST-#47 ZBE (docs#47 §4.2.1). The bundle blob is now sealed with    *)
(*     ZBE (zkCoins Bundle Encryption): chunked ChaCha20-Poly1305 over the  *)
(*     blob (NIP-44's 65535-byte limit), per-chunk AAD                      *)
(*     "zkCoins/v1/Blob" || u32_be(N) || u32_be(i) binding total chunk      *)
(*     count N and index i, counter nonce per chunk, blob_id = H(cipher).   *)
(*     It is "a thin chunked framing over the same AEAD primitive" and so   *)
(*     REDUCES to A10's IND-CCA AEAD: who can read the plaintext is still   *)
(*     exactly the K_tx holder set, so CanDecrypt/CanReadBundle is          *)
(*     unchanged. The NEW integrity guarantee #47 adds (any tag failure /   *)
(*     chunk-count mismatch / missing magic MUST abort -- no partial        *)
(*     accept, so truncation/extension/reorder of chunks is rejected) is    *)
(*     the anti-truncation layer machine-checked separately in              *)
(*     property/P08_TransportConfAuth/zbe.tla.                              *)
(*   - The content-addressed blob store (Blossom-style, Sec. 4.2 step 2) is *)
(*     abstracted to an opaque `blobId : Int` handle; blob_id = H(ciphertext)*)
(*     collision-freedom is the Foundations digest abstraction (A5).        *)
(*   - The BIP-340 ACK signature (Sec. 4.2) is the A7 oracle: a recipient's *)
(*     `op` is added to `trAuthorised` for the ack message tag only by an     *)
(*     honest signing action, and SigValid tests membership. The detect_tag,*)
(*     epk, blob_locators are opaque Int handles (Sec. 4.4 detection scan   *)
(*     is out of scope; only addressing-by-IVPK matters to trDelivery here).  *)
(*   - "k independent trReplicas" is modelled as a SET of distinct holder ids *)
(*     (Sec. 4.6 "independent" = distinct operators); |trReplicas| >= k is    *)
(*     the replication-confirmed test. Backoff/retry SCHEDULE (30 s..1 h) is *)
(*     abstracted to a non-deterministic Retry action that just refreshes    *)
(*     the nonce -- timing is liveness, irrelevant to the safety claims.    *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP. Delete the `trAckOk` conjunct from the Drop  *)
(* guard and SenderRetainsUntilSafe fails; delete the nonce-equality check  *)
(* in AckAccepts and AckFreshness fails (a stale captured ACK is accepted). *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Foundations, Assumptions

(***************************************************************************)
(* New type aliases for the transport wire objects. detect_tag, epk,       *)
(* blob_id, blob_locators, ack_nonce are opaque Int handles (their crypto   *)
(* content is carried by the axiom oracles, not by arithmetic).            *)
(***************************************************************************)

\* @typeAlias: deliveryEvent = { detectTag: Int, epk: Int, blobId: Int, blobLocators: Set(Int), ackNonce: Int };
\* @typeAlias: ack = { detectTag: Int, blobId: Int, ackNonce: Int, opPk: Int };
Transport_typedefs == TRUE

(***************************************************************************)
(* The DeliveryEvent plaintext payload (Sec. 4.2 step 3). Carries NO        *)
(* amount/asset/recipient/sender -- those live only inside the ciphertext.  *)
(* @type: (Int, Int, Int, Set(Int), Int) => $deliveryEvent;                *)
(***************************************************************************)
MkDeliveryEvent(detectTag, epk, blobId, blobLocators, ackNonce) ==
  [ detectTag |-> detectTag, epk |-> epk, blobId |-> blobId,
    blobLocators |-> blobLocators, ackNonce |-> ackNonce ]

\* The acknowledgement (Sec. 4.2 "ACK + retry"): echoes {detect_tag, blob_id,
\* ack_nonce} and is BIP-340-signed by the recipient's op over ack_message.
\* @type: (Int, Int, Int, Int) => $ack;
MkAck(detectTag, blobId, ackNonce, opPk) ==
  [ detectTag |-> detectTag, blobId |-> blobId, ackNonce |-> ackNonce, opPk |-> opPk ]

(***************************************************************************)
(* Constants for a small instance.                                         *)
(***************************************************************************)
CONSTANT
  \* The replication target k (Sec. 4.6). Default 3; MUST NOT be < 2.
  \* @type: Int;
  K,
  \* Universe of node/relay ids that may hold a replica (distinct = independent).
  \* @type: Set(Int);
  Holders,
  \* The recipient's published op pubkey (the only key that can sign a valid ACK).
  \* @type: Int;
  RecipientOpPk,
  \* The recipient's incoming-view key holders: who can decrypt the trDelivery
  \* event addressed to IVPK (ivk-holder = recipient devices). A8-A11.
  \* @type: Set(Int);
  IvkHolders,
  \* The per-coin note-key (K_tx) holders: who can decrypt the bundle blob.
  \* Re-derivable from ivk+epk, so == IvkHolders here; relay holds neither.
  \* @type: Set(Int);
  KtxHolders,
  \* The relay/eavesdropper id (holds no decryption key -- availability only).
  \* @type: Int;
  Eve

(***************************************************************************)
(* k MUST NOT be less than 2 (Sec. 4.6 normative). A model that violated    *)
(* this would not be a faithful instance, so we pin it as an ASSUME.        *)
(***************************************************************************)
ASSUME ReplicationFloor == K >= 2

(***************************************************************************)
(* State. A single trDelivery attempt tracked as a small state machine. The   *)
(* trPhase progresses published -> {acked, replicated in any order} -> dropped *)
(* (Sec. 4.2). `trAuthorised` is the A7 signing oracle, grown honestly.       *)
(***************************************************************************)
VARIABLES
  \* Lifecycle trPhase of the trDelivery (Sec. 4.2): "published" once the event
  \* is on a relay, "dropped" once the sender has released its copy.
  \* @type: Str;
  trPhase,
  \* The trDelivery event currently published for THIS attempt (Sec. 4.2 step 3).
  \* @type: $deliveryEvent;
  trDelivery,
  \* The nonce the sender chose for THIS attempt; a retry picks a fresh one
  \* (Sec. 4.2: "Fresh per retry"). The ACK must echo exactly this value.
  \* @type: Int;
  trAttemptNonce,
  \* Whether a VALID, FRESH ACK has been accepted for the current attempt.
  \* @type: Bool;
  trAckOk,
  \* The set of independent holders confirmed to hold the blob (Sec. 4.6).
  \* @type: Set(Int);
  trReplicas,
  \* Whether the sender still retains its own copy + K_tx (Sec. 4.2). The
  \* custody bit the retention rule protects.
  \* @type: Bool;
  trSenderHasCopy,
  \* The A7 authorisation oracle: (pk, msgTag) pairs honest signers produced.
  \* @type: Set(<<Int, Int>>);
  trAuthorised

\* @type: <<Str, $deliveryEvent, Int, Bool, Set(Int), Bool, Set(<<Int,Int>>)>>;
trVars == << trPhase, trDelivery, trAttemptNonce, trAckOk, trReplicas, trSenderHasCopy, trAuthorised >>

(***************************************************************************)
(* Opaque per-attempt wire handles. Concrete values are irrelevant to the   *)
(* safety claims; we fix small constants so Init is fully assigned.         *)
(***************************************************************************)
\* @type: () => Int;
DetectTag == 1
\* @type: () => Int;
Epk == 2
\* @type: () => Int;
BlobId == 3
\* @type: () => Set(Int);
BlobLocators == Holders

\* The ack_message tag (Sec. 4.2): H("zkCoins/v1/Ack" || detect_tag || blob_id
\* || ack_nonce). Modelled as the structured value it commits to (A5 collision
\* freedom): distinct nonces => distinct tags, which is exactly the freshness
\* binding. We encode it as an Int so it indexes the SigValid oracle.
\* @type: (Int) => Int;
AckMsgTag(nonce) == 1000 + nonce

\* The sender's own node id -- a designated holder. Chosen as the minimum of
\* the (non-empty) Holders set so Init is deterministic.
\* @type: () => Int;
SenderNode == CHOOSE h \in Holders : \A g \in Holders : h <= g

(***************************************************************************)
(* Initial state: a sender has just published its first attempt. The blob   *)
(* is replicated only on the sender's own node so far (replica count 1 < k):*)
(* trDelivery is NOT yet complete. No ACK yet; sender still holds its copy.    *)
(***************************************************************************)
\* @type: () => Bool;
TrInit ==
  /\ trPhase = "published"
  /\ trDelivery = MkDeliveryEvent(DetectTag, Epk, BlobId, BlobLocators, 0)
  /\ trAttemptNonce = 0
  /\ trAckOk = FALSE
  /\ trReplicas = { x \in Holders : x = SenderNode }      \* sender's own node only
  /\ trSenderHasCopy = TRUE
  /\ trAuthorised = {}

(***************************************************************************)
(* ACTIONS (Sec. 4.2 / 4.6). Next == Publish \/ Replicate \/ Ack \/ Retry  *)
(* \/ Drop.                                                                *)
(***************************************************************************)

\* Publish (re-)posts the current attempt's trDelivery event to relays. Idempotent
\* on state apart from re-asserting the published trPhase; models step 5.
\* @type: () => Bool;
Publish ==
  /\ trPhase = "published"
  /\ trDelivery' = MkDeliveryEvent(DetectTag, Epk, BlobId, BlobLocators, trAttemptNonce)
  /\ UNCHANGED << trPhase, trAttemptNonce, trAckOk, trReplicas, trSenderHasCopy, trAuthorised >>

\* Replicate adds one more INDEPENDENT holder of the blob (Sec. 4.6): a
\* distinct operator from the recipient's advertised set or an archival relay.
\* @type: () => Bool;
Replicate ==
  /\ trPhase = "published"
  /\ \E h \in Holders \ trReplicas :
       /\ trReplicas' = trReplicas \union { h }
  /\ UNCHANGED << trPhase, trDelivery, trAttemptNonce, trAckOk, trSenderHasCopy, trAuthorised >>

\* The recipient's op honestly signs the ACK for the CURRENT attempt's nonce
\* (Sec. 4.2). This is the only way (pk, ackTag) enters the A7 oracle for the
\* recipient -- EUF-CMA: nobody else can produce this signature.
\* @type: () => Bool;
RecipientSigns ==
  /\ trPhase = "published"
  /\ trAuthorised' = trAuthorised \union { <<RecipientOpPk, AckMsgTag(trAttemptNonce)>> }
  /\ UNCHANGED << trPhase, trDelivery, trAttemptNonce, trAckOk, trReplicas, trSenderHasCopy >>

\* AckAccepts: the sender accepts an ACK iff (i) the op signature verifies
\* (SigValid, A7) AND (ii) the echoed ack_nonce equals THIS attempt's nonce
\* (F17 freshness). The two-part check is the whole point: a captured ACK
\* from an earlier attempt carries a different nonce and so fails (ii).
\* @type: ($ack) => Bool;
AckAccepts(a) ==
  /\ a.opPk = RecipientOpPk
  /\ SigValid(trAuthorised, a.opPk, AckMsgTag(a.ackNonce))   \* (i) A7 op-sig
  /\ a.ackNonce = trAttemptNonce                              \* (ii) F17 freshness

\* Ack: the sender receives some ACK off the wire (adversary may inject any
\* record) and accepts it only if AckAccepts holds. detect_tag/blob_id must
\* match the published event (Sec. 4.2 echoes them).
\* @type: () => Bool;
Ack ==
  /\ trPhase = "published"
  /\ trAckOk = FALSE
  /\ \E a \in [ detectTag: {DetectTag}, blobId: {BlobId},
                ackNonce: Holders \union {trAttemptNonce}, opPk: {RecipientOpPk, Eve} ] :
       /\ AckAccepts(a)
       /\ trAckOk' = TRUE
  /\ UNCHANGED << trPhase, trDelivery, trAttemptNonce, trReplicas, trSenderHasCopy, trAuthorised >>

\* Retry: no valid ACK yet, so re-publish with a FRESH ack_nonce (Sec. 4.2
\* "Fresh per retry"). A fresh nonce invalidates any ACK accepted criteria for
\* old attempts -- trAckOk resets to FALSE for the new attempt.
\* @type: () => Bool;
Retry ==
  /\ trPhase = "published"
  /\ trAckOk = FALSE
  /\ trAttemptNonce' = trAttemptNonce + 1                      \* fresh, distinct nonce
  /\ trDelivery' = MkDeliveryEvent(DetectTag, Epk, BlobId, BlobLocators, trAttemptNonce + 1)
  /\ UNCHANGED << trPhase, trAckOk, trReplicas, trSenderHasCopy, trAuthorised >>

\* Drop: the sender releases its retained copy + K_tx. GUARDED by the Sec. 4.2
\* + Sec. 4.6 retention rule: MUST NOT drop before BOTH a valid ACK AND
\* k-independent replication are confirmed. This guard is the modelled rule.
\* @type: () => Bool;
Drop ==
  /\ trPhase = "published"
  /\ trAckOk = TRUE                       \* valid, fresh ACK confirmed (Sec. 4.2)
  /\ Cardinality(trReplicas) >= K         \* k independent trReplicas confirmed (Sec. 4.6)
  /\ trPhase' = "dropped"
  /\ trSenderHasCopy' = FALSE
  /\ UNCHANGED << trDelivery, trAttemptNonce, trAckOk, trReplicas, trAuthorised >>

\* @type: () => Bool;
TrNext ==
  \/ Publish
  \/ Replicate
  \/ RecipientSigns
  \/ Ack
  \/ Retry
  \/ Drop

TrSpec == TrInit /\ [][TrNext]_trVars

(***************************************************************************)
(* Helper: the set of parties that can decrypt this trDelivery / its blob     *)
(* (Sec. 4.2, A8-A11). The relay/eavesdropper Eve is in NEITHER holder set, *)
(* so CanDecrypt(., Eve) is false for both objects.                         *)
(***************************************************************************)
\* @type: (Int) => Bool;
CanReadDelivery(who) == CanDecrypt(IvkHolders, who)
\* @type: (Int) => Bool;
CanReadBundle(who) == CanDecrypt(KtxHolders, who)

(***************************************************************************)
(* INVARIANTS. Only TypeOK is smoke-checked in Phase 1; the rest are stated *)
(* here for the Phase-2 certificate (named below).                          *)
(***************************************************************************)

\* TypeOK. Membership tests over the infinite carrier `Int` are NOT expandable
\* by Apalache, so integer-typed fields are checked structurally (the value is
\* well-formed and the record exposes exactly its declared fields) rather than
\* by `x \in Int`. The Snowcat type annotations already pin the scalar types;
\* TypeOK asserts the FINITE structural facts a checker can enumerate.
\* @type: () => Bool;
TrTypeOK ==
  /\ trPhase \in { "published", "dropped" }
  /\ DOMAIN trDelivery = { "detectTag", "epk", "blobId", "blobLocators", "ackNonce" }
  /\ trDelivery.blobLocators \subseteq Holders
  /\ trAckOk \in BOOLEAN
  /\ trReplicas \subseteq Holders
  /\ trSenderHasCopy \in BOOLEAN
  \* Only the recipient's op key is ever honestly signed for (A7 oracle grows
  \* solely via RecipientSigns): a faithful structural fact, also a finite test.
  /\ \A pair \in trAuthorised : pair[1] = RecipientOpPk

\* SenderRetainsUntilSafe (Sec. 4.2 + 4.6): the sender never releases its copy
\* before BOTH a valid ACK AND k independent trReplicas are confirmed. Stated
\* over the post-drop state: if the copy is gone, the safe conditions held.
\* @type: () => Bool;
TrSenderRetainsUntilSafe ==
  (~ trSenderHasCopy) => (trAckOk /\ Cardinality(trReplicas) >= K)

\* AckFreshness (Sec. 4.2, F17): an accepted ACK matches the CURRENT attempt's
\* nonce. Modelled as: trAckOk is only ever set true by AckAccepts, whose (ii)
\* binds a.ackNonce = trAttemptNonce. Stated as an inductive invariant that trAckOk
\* implies the recipient signed for this very attempt's nonce (so a stale ACK,
\* carrying an old nonce, can never have set it).
\* @type: () => Bool;
TrAckFreshness ==
  trAckOk => ( <<RecipientOpPk, AckMsgTag(trAttemptNonce)>> \in trAuthorised )

\* AvailabilityNotSafety (Sec. 4.6 safety invariant): a dropped/unavailable
\* bundle never enables theft -- it never lets a non-holder decrypt. The relay/
\* eavesdropper Eve holds no key, so even after the sender drops its copy (the
\* worst availability case) Eve can read neither the trDelivery nor the bundle.
\* Custody safety MUST NOT depend on availability.
\* @type: () => Bool;
TrAvailabilityNotSafety ==
  /\ ~ CanReadDelivery(Eve)
  /\ ~ CanReadBundle(Eve)

(***************************************************************************)
(* Constant initialiser for the smoke instance (Apalache --cinit). One      *)
(* sender node + two other independent holders (so k = 3 is reachable),     *)
(* recipient op pubkey distinct from Eve, ivk/K_tx holders = recipient      *)
(* devices, Eve in neither.                                                 *)
(***************************************************************************)
\* @type: () => Bool;
TrConstInit ==
  /\ K = 3
  /\ Holders = { 1, 2, 3 }
  /\ RecipientOpPk = 10
  /\ IvkHolders = { 20, 21 }
  /\ KtxHolders = { 20, 21 }
  /\ Eve = 99

=============================================================================
