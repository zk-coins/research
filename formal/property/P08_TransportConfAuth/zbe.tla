-------------------------- MODULE zbe --------------------------
(***************************************************************************)
(* P08 -- ZBE anti-truncation / integrity (spec-v1.1 / docs#47, §4.2.1).      *)
(*                                                                         *)
(* A NEW load-bearing invariant added for the spec-v1.1 baseline            *)
(* (docs@ed7fdece). docs#47 §4.2.1 introduces ZBE (zkCoins Bundle            *)
(* Encryption): the bundle blob is sealed with chunked ChaCha20-Poly1305     *)
(* (NIP-44's 65535-byte limit). Each chunk's AAD is                          *)
(*   "zkCoins/v1/Blob" || u32_be(N) || u32_be(i)                            *)
(* binding the TOTAL chunk count N and the chunk INDEX i; a counter nonce     *)
(* per chunk; blob_id = H(ciphertext). The spec is normative: any tag         *)
(* failure / chunk-count mismatch / missing magic MUST abort -- no partial     *)
(* accept.                                                                    *)
(*                                                                         *)
(* CONFIDENTIALITY is unchanged and stays the existing CanDecrypt/A10 fact    *)
(* (module/Transport.tla, P08 property.tla). ZBE "reduces to A10" -- a thin    *)
(* chunked framing over the SAME AEAD primitive. THIS file is specifically    *)
(* the INTEGRITY / ANTI-TRUNCATION layer the new framing adds.               *)
(*                                                                         *)
(* THE CLAIM proven here (the genuinely NEW #47 guarantee, lifted from        *)
(* hand-argument to a machine-checked invariant): a TRUNCATED (fewer than N),  *)
(* EXTENDED, or REORDERED chunk sequence is REJECTED (does not authenticate).  *)
(* Equivalently, the decrypted plaintext, WHEN ACCEPTED, equals EXACTLY the    *)
(* sealed plaintext:                                                          *)
(*   Accepted => received = sealed.                                          *)
(*                                                                         *)
(* MODELLING (the repo AEAD idiom -- A10 as a capability/authentication        *)
(* oracle; a chunk's Poly1305 tag binds its AAD by A10, so the tag verifies    *)
(* at a receiver position IFF the chunk's sealed (N,i) AAD matches the AAD the  *)
(* receiver computes there -- the observed count and the position index).       *)
(*   - `sealed` is the sender's ordered chunk sequence; chunk j (1-based seq    *)
(*     position, 0-based protocol index j-1) carries n = N (= Len(sealed)) and  *)
(*     idx = j-1 in its AAD, plus an opaque payload.                          *)
(*   - `received` is the sequence the receiver gets off the wire; the relay/    *)
(*     adversary may TRUNCATE, EXTEND, REORDER, or DUPLICATE chunks (any seq    *)
(*     of sealed chunks). The receiver runs Accepts(received): every chunk      *)
(*     must authenticate against the OBSERVED count Len(received) AND its        *)
(*     position, i.e. chunk.n = Len(received) /\ chunk.idx = pos-1, and the      *)
(*     indices must form the contiguous 0..Len-1 the AAD pins. Any mismatch     *)
(*     aborts (no partial accept).                                           *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP (negative control). DROP the per-chunk (N,i)   *)
(* AAD binding (AAD does not cover count/index): ChunkAuth becomes TRUE         *)
(* regardless of (n,idx). Then a truncated or reordered `received` AUTHENTICATES *)
(* yet differs from `sealed` => AntiTruncation fails. The commented variant +    *)
(* recorded run are in notes.md (committed companion zbe_nc.tla).               *)
(***************************************************************************)
EXTENDS Integers, Sequences, Apalache

CONSTANT
  \* Maximum chunk count N (and max received length). The blob is split into
  \* 1..MaxN chunks (NIP-44 65535-byte limit drives N in the real protocol).
  \* @type: Int;
  MaxN,
  \* Finite universe of opaque chunk payloads (ciphertext bodies). The model
  \* needs only equality over them, never their bytes.
  \* @type: Set(Int);
  Payloads

(***************************************************************************)
(* A chunk carries its AAD-bound count n and index idx, plus an opaque payload.*)
(* @typeAlias: chunk = { n: Int, idx: Int, payload: Int };                    *)
(***************************************************************************)
zbe_typedefs == TRUE

VARIABLES
  \* The sender's sealed ordered chunk sequence for the current blob (§4.2.1).
  \* @type: Seq($chunk);
  sealed,
  \* The chunk sequence the receiver got off the wire (possibly truncated /
  \* extended / reordered / duplicated by the relay/adversary).
  \* @type: Seq($chunk);
  received,
  \* Whether the receiver's ZBE decryption ACCEPTED `received` (all chunks
  \* authenticated + count/index match the AAD-bound, contiguous 0..N-1).
  \* @type: Bool;
  accepted

\* @type: <<Seq($chunk), Seq($chunk), Bool>>;
vars == << sealed, received, accepted >>

(***************************************************************************)
(* ChunkAuth -- the A10 AEAD authentication of one chunk at receiver position   *)
(* `pos` (1-based) under observed count `obsN`. The Poly1305 tag binds the AAD  *)
(* "zkCoins/v1/Blob" || u32_be(N) || u32_be(i), so the tag verifies IFF the     *)
(* chunk's sealed (n, idx) equals the AAD the receiver computes here:           *)
(* n = obsN (total count) and idx = pos-1 (0-based index). THIS is the          *)
(* load-bearing (N,i) binding the negative control removes.                    *)
(* @type: ($chunk, Int, Int) => Bool;                                          *)
(***************************************************************************)
ChunkAuth(c, obsN, pos) ==
  /\ c.n = obsN
  /\ c.idx = pos - 1

(***************************************************************************)
(* Accepts -- ZBE decryption of `rx`: accept IFF every chunk authenticates      *)
(* against the observed count Len(rx) and its position (so the indices are       *)
(* exactly the contiguous 0..Len(rx)-1 the AAD pins, and the count matches).     *)
(* Any tag/count/index mismatch aborts -- no partial accept (§4.2.1).           *)
(* @type: (Seq($chunk)) => Bool;                                                *)
(***************************************************************************)
Accepts(rx) ==
  /\ Len(rx) >= 1                                  \* missing magic / zero chunks => abort
  /\ \A p \in DOMAIN rx : ChunkAuth(rx[p], Len(rx), p)

(***************************************************************************)
(* WellSealed -- the sender's sealed sequence is internally consistent: every    *)
(* chunk j carries n = Len(sealed) and idx = j-1 (the honest sealing, §4.2.1).   *)
(* @type: (Seq($chunk)) => Bool;                                                 *)
(***************************************************************************)
WellSealed(s) ==
  /\ Len(s) >= 1 /\ Len(s) <= MaxN
  /\ \A j \in DOMAIN s :
       /\ s[j].n = Len(s)
       /\ s[j].idx = j - 1
       /\ s[j].payload \in Payloads

(***************************************************************************)
(* Init / transitions.                                                       *)
(***************************************************************************)
\* @type: () => Bool;
Init ==
  /\ sealed = << [ n |-> 1, idx |-> 0, payload |-> CHOOSE x \in Payloads : TRUE ] >>
  /\ received = << >>
  /\ accepted = FALSE

\* Seal -- the sender (re)seals a blob into a fresh well-sealed chunk sequence.
\* @type: () => Bool;
Seal ==
  \E s \in { Gen(MaxN) } :
    /\ WellSealed(s)
    /\ sealed' = s
    /\ received' = << >>
    /\ accepted' = FALSE

\* Deliver -- the relay/adversary delivers SOME chunk sequence drawn from the
\* sealed chunks: it may TRUNCATE, EXTEND, REORDER, or DUPLICATE (any sequence
\* whose entries are chunks of `sealed`). The receiver then runs ZBE decryption
\* and sets `accepted` to its all-or-none verdict.
\* @type: () => Bool;
Deliver ==
  \E rx \in { Gen(MaxN) } :
    /\ \A p \in DOMAIN rx : \E j \in DOMAIN sealed : rx[p] = sealed[j]
    /\ received' = rx
    /\ accepted' = Accepts(rx)
    /\ UNCHANGED sealed

\* @type: () => Bool;
Next == Seal \/ Deliver

\* @type: () => Bool;
Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

\* @type: () => Bool;
TypeOK ==
  /\ WellSealed(sealed)
  /\ accepted \in BOOLEAN
  /\ \A p \in DOMAIN received :
       /\ received[p].payload \in Payloads
       /\ received[p].n \in Int
       /\ received[p].idx \in Int

(***************************************************************************)
(* THE LOAD-BEARING SAFETY CLAIM (docs#47 §4.2.1): if the receiver ACCEPTED      *)
(* the chunk sequence, then it equals EXACTLY the sealed sequence -- a truncated, *)
(* extended, or reordered sequence is never accepted. So the decrypted           *)
(* plaintext, when accepted, is exactly the sealed plaintext.                   *)
(* @type: () => Bool;                                                            *)
(***************************************************************************)
AntiTruncation == accepted => (received = sealed)

\* @type: () => Bool;
IndInv ==
  /\ TypeOK
  /\ AntiTruncation

(***************************************************************************)
(* Assignment-form restatement used as the inductive-step --init. Each variable *)
(* is GENERATED via apalache.Gen and constrained by IndInv (the sequences cannot *)
(* be \subseteq-bounded; Gen is the Apalache idiom, as in P03). Logically        *)
(* equivalent to IndInv over the assigned variables.                            *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit ==
  /\ sealed = Gen(MaxN)
  /\ received = Gen(MaxN)
  /\ accepted \in BOOLEAN
  /\ TypeOK
  /\ AntiTruncation

(***************************************************************************)
(* Constant initialiser (Apalache --cinit). Small finite instance: up to 3      *)
(* chunks, 2 distinct payloads (enough for truncation, reorder, and a duplicate  *)
(* to be expressible). The argument is uniform in MaxN / |Payloads|: the AEAD    *)
(* (N,i) binding is per-chunk local and Accepts is a per-position conjunction.   *)
(***************************************************************************)
\* @type: () => Bool;
ConstInit ==
  /\ MaxN = 3
  /\ Payloads = 1..2

(***************************************************************************)
(* VACUITY PROBE. AntiTruncation is NOT vacuous: `accepted` is genuinely        *)
(* reachable as TRUE (the honest full delivery received = sealed authenticates). *)
(* NeverAccepted asserts accepted stays FALSE forever; a check returns a          *)
(* counterexample (the honest sequence IS accepted), so the implication is        *)
(* exercised with a TRUE antecedent, not vacuously. (Recorded in notes.md.)      *)
(* @type: () => Bool;                                                            *)
(***************************************************************************)
NeverAccepted == accepted = FALSE

(***************************************************************************)
(* NEGATIVE CONTROL (committed companion zbe_nc.tla; recorded run in notes.md).  *)
(* DROP the per-chunk (N,i) AAD binding -- ChunkAuth becomes TRUE                 *)
(* regardless of (n,idx), i.e. the AAD does not cover count/index. Then a         *)
(* truncated or reordered `received` AUTHENTICATES (accepted = TRUE) yet differs  *)
(* from `sealed` => AntiTruncation fails (Apalache: outcome Error, exit 12). This *)
(* is the definitive proof the (N,i) AAD binding is load-bearing.               *)
(***************************************************************************)
=============================================================================
