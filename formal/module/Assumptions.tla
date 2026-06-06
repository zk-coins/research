-------------------------- MODULE Assumptions --------------------------
(***************************************************************************)
(* Assumptions -- the 17 cryptographic/operational axioms A1-A17 as ideal    *)
(* functionalities (README "Axiomatized assumptions"). Apalache does NOT     *)
(* prove these; it proves the protocol composes them correctly. This module  *)
(* fixes the AXIOM INTERFACE every property module composes, so the trust    *)
(* budget is one file, not scattered conventions.                           *)
(*                                                                         *)
(* Two kinds of axiom encoding:                                            *)
(*  (1) STRUCTURAL -- baked into Foundations' digest abstraction; nothing to *)
(*      compute here, only to state. (A3,A4,A5,A6,A16,A17.)                 *)
(*  (2) ORACLE     -- a reusable operator a state machine evaluates against  *)
(*      state it maintains honestly. (A1,A7,A12,A15; A2,A8-A11,A13,A14 are   *)
(*      confidentiality/channel oracles used by the privacy/transport        *)
(*      properties.)                                                        *)
(***************************************************************************)
EXTENDS Integers, Foundations

(***************************************************************************)
(* A1 -- Plonky2 knowledge-soundness (PCD). A verifying recursive proof      *)
(* implies its statement holds. We model a "proof" by the statement it       *)
(* attests (a Bool the prover could only make true by knowing a real         *)
(* witness); verification = that statement. KnowledgeSound lifts this: a     *)
(* verifier that accepts may rely on the statement.                         *)
(*   Used by: P1, P7 (forgery), and every receive-side re-verification.      *)
(***************************************************************************)

\* @type: (Bool, Bool) => Bool;
KnowledgeSound(proofAccepts, statementHolds) ==
  proofAccepts => statementHolds

(***************************************************************************)
(* A2 -- Plonky2 zero-knowledge. A proof reveals nothing beyond its public   *)
(* inputs (ProofData). Modelled as an indistinguishability obligation: two   *)
(* witnesses with equal public inputs are observationally equal to a         *)
(* verifier. P4 states this as non-interference over the witness; here we    *)
(* expose the public-input projection a verifier is allowed to learn.        *)
(*   Used by: P4, every privacy claim.                                       *)
(***************************************************************************)

\* The only thing a verifier may learn from a proof is its public inputs.
\* @type: (a) => a;
PublicProjection(proofData) == proofData

(***************************************************************************)
(* A3/A4 (Poseidon CR / sponge), A5/A6 (SHA-256 CR / preimage),             *)
(* A16 (Merkle/SMT CR lifting), A17 (serialize injective):                  *)
(* STRUCTURAL -- encoded in Foundations by modelling each digest as the      *)
(* structured value it commits to (collisions impossible by construction)    *)
(* and ash as the AccountState itself (AshEq). A16 additionally licenses     *)
(* reasoning over a tree's KEY SET in place of its opaque root: where a      *)
(* module tracks a root's contents as a set, equality of roots is equality   *)
(* of sets. RootCommitsSet records that licence.                            *)
(***************************************************************************)

\* A16: a root equals another iff their committed key-sets are equal. A module
\* that maintains the set `keys` for a root may treat the root as that set.
\* @type: (Set(a), Set(a)) => Bool;
RootCommitsSet(keysOfR1, keysOfR2) == (keysOfR1 = keysOfR2)

(***************************************************************************)
(* A7 -- BIP-340 Schnorr EUF-CMA. An adversary cannot produce a valid        *)
(* signature under a key whose secret it does not hold. Modelled as an       *)
(* authorisation oracle: `authorised` is the set of (pubkey, message) pairs  *)
(* the legitimate secret-holders have actually signed; a signature verifies  *)
(* iff its (pk, msg) is in that set. The state machine GROWS `authorised`    *)
(* only via honest signing actions for keys the signer controls -- so a      *)
(* forged (pk, msg) for an uncontrolled key is, by EUF-CMA, never in it.     *)
(*   Used by: P1, P7, P8, P10.                                               *)
(***************************************************************************)

\* @type: (Set(<<Int, Int>>), Int, Int) => Bool;
SigValid(authorised, pk, msgTag) ==
  <<pk, msgTag>> \in authorised

(***************************************************************************)
(* A8 (secp256k1 DL+ECDH), A9 (HKDF-SHA256 PRF), A10 (NIP-44 IND-CCA),       *)
(* A11 (NIP-59 gift-wrap): transport confidentiality / key-derivation        *)
(* oracles. A party can decrypt a ciphertext iff it holds the deriving key   *)
(* (ivk for the delivery payload, K_tx for the bundle). Modelled as a        *)
(* capability test; the relay/eavesdropper holds none, so learns nothing     *)
(* beyond the public envelope.                                               *)
(*   Used by: P4, P8.                                                        *)
(***************************************************************************)

\* CanDecrypt: the holder set of a per-object key includes `who` iff `who`
\* legitimately derived it (ivk-holder, or K_tx-holder).
\* @type: (Set(Int), Int) => Bool;
CanDecrypt(keyHolders, who) == who \in keyHolders

(***************************************************************************)
(* A12 -- Bitcoin honest-majority & no reorgs >= 6 blocks. Captured as a     *)
(* model constraint: a reorg removes strictly fewer than 6 confirmations'    *)
(* worth of admitted state (the finality depth K = 6), and a `completed`     *)
(* record (depth >= K) is never reverted. ReorgWithinBound is the predicate  *)
(* on a proposed reorg depth.                                                *)
(*   Used by: P2, P6.                                                        *)
(***************************************************************************)

\* @type: () => Int;
FinalityDepthK == 6

\* @type: (Int) => Bool;
ReorgWithinBound(depth) == depth < FinalityDepthK

(***************************************************************************)
(* A13 -- per-node eclipse resistance (own bitcoind): a node's chain view is *)
(* the true canonical chain. Modelled by giving every honest verifier the    *)
(* same `chainTip`/admitted set (no per-node divergence injected).           *)
(* A14 -- TLS1.2-EMS / TLS1.3 / Tor v3 for the pull endpoint: the channel    *)
(* binding `chan_bind` authenticates the host, so a proof presented to host  *)
(* X cannot be replayed to host Y. ChanBindMatches is the host-binding test. *)
(*   A13 used by: P6. A14 used by: P10.                                      *)
(***************************************************************************)

\* A14: the requester's channel binding matches exactly one host it dialed;
\* a node accepts a proof only if the presented binding is for itself.
\* @type: (Int, Int) => Bool;
ChanBindMatches(presentedHost, servingHost) == presentedHost = servingHost

(***************************************************************************)
(* A15 -- half-aggregation soundness. The publisher's aggregate check        *)
(* accepts iff EVERY constituent BIP-340 signature is valid (transcript-     *)
(* bound coefficients rule out rogue-key cancellation; conditional on A7).   *)
(* Post-docs#40 this lives inside the AggregateBatchProof witness, but the   *)
(* logical content is unchanged: AggValid <=> all members valid.             *)
(*   Used by: P1, P2.                                                        *)
(***************************************************************************)

\* @type: (Set(Bool)) => Bool;
AggSoundValid(memberValidities) ==
  \A v \in memberValidities : v = TRUE

=============================================================================
