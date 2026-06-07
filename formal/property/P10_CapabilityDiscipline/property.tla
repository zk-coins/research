-------------------------- MODULE property --------------------------
(***************************************************************************)
(* P10 -- Capability Discipline (Access & Explorer, Sec. 5).               *)
(*                                                                         *)
(* Phase-2 property deliverable of the zkCoins 100% Logical Verification    *)
(* Initiative: the Sec. 5 capability-gated pull endpoint (module/Access.tla)*)
(* verified UNBOUNDED via an inductive invariant -- the four release-       *)
(* discipline safety claims hold in EVERY reachable state, for an arbitrary *)
(* number of Sign/IssueChallenge/Release/Revoke/Tick transitions, not just  *)
(* a fixed depth.                                                           *)
(*                                                                         *)
(* THE CLAIM (matches Pass-3 audit P10, HIGH):                             *)
(*   "A presented capability releases at most the data its scope            *)
(*    authorizes; no capability widens spend authority; OwnershipProof and  *)
(*    GrantProof cannot be replayed against a different node; revoked/       *)
(*    expired grants release nothing."                                      *)
(*                                                                         *)
(* GROUNDED IN THE SPECIFICATION (baseline zk-coins/docs@b6972b8):          *)
(*   - Sec. 5.1 (capability-gated pull): exactly two authorisations         *)
(*     (ownership proof, view grant); challenge->proof with server-issued   *)
(*     nonce + expiry, consumed-once; chan_bind binds the proof to the host *)
(*     the requester dialed (proof-forwarding / MITM defence).              *)
(*   - Sec. 5.1(b)/5.2 (view grant): release ONLY records inside the        *)
(*     grant's scope; the grant MUST be unexpired and unrevoked; revocation *)
(*     is forward-only.                                                     *)
(*   - Sec. 5.2/5.3/5.4/5.8: a view capability is read-only and NEVER       *)
(*     confers spend authority; bearer secrets (zkview/zkavk) are not node   *)
(*     authorisations (Sec. 5.1 para 2).                                    *)
(*                                                                         *)
(* INV_P10 is the conjunction of the THREE dynamically machine-checked      *)
(* Sec. 5 safety claims that module/Access.tla exposes:                     *)
(*   AcNoReleaseWithoutCapability  -- scope evasion (Sec. 5.1 normative)    *)
(*   AcScopeRespected              -- scope evasion (Sec. 5.1(b) check 4)   *)
(*   AcNoReplayAcrossHosts         -- proof-forwarding MITM (A14, chan_bind)*)
(*                                                                         *)
(* The fourth Pass-3 attack class, SPEND ESCALATION (Sec. 5.2/5.4), is a    *)
(* STRUCTURAL by-construction property of the release machine, NOT a         *)
(* dynamically exercised invariant, so it is deliberately NOT a conjunct of *)
(* INV_P10. The release actions' write set is { acConsumed, acReleased };   *)
(* no action writes the signing oracle except the honest Sign action, so a   *)
(* release never confers spend authority; the VIEW/SPEND key separation is  *)
(* a Foundations/Assumptions-level axiom (A9). This is documented as         *)
(* structural in module/Access.tla, notes.md and certificate.txt. (An        *)
(* earlier formulation shipped it as the tautology CanDecrypt({pk},pk) =>    *)
(* e.rec \in Records, which asserted nothing; it was removed, not patched.)  *)
(*                                                                         *)
(* WHY THE MODEL EARNS ITS KEEP: the release guards are load-bearing. The    *)
(* requester PRESENTS a chan_bind (possibly ForeignHost), which the release  *)
(* actions carry through to the audit entry's host field; only                *)
(* ChanBindMatches(presented, ServingHost) and the challenge-side equality   *)
(* ch.chanBind = presented keep a ForeignHost-bound proof from releasing.    *)
(* Delete those chan_bind conjunct(s) from an admit predicate and re-run --  *)
(* Apalache returns a counterexample in which a ForeignHost-bound proof      *)
(* releases (e.host = ForeignHost), violating AcNoReplayAcrossHosts (a proof *)
(* bound to host X accepted at host Y). With the guard, INV_P10 and the      *)
(* inductive invariant hold for the whole unbounded state space. (See        *)
(* notes.md for the recorded negative run and its trace.)                    *)
(***************************************************************************)
EXTENDS Access

(***************************************************************************)
(* INV_P10 -- the safety claim. The conjunction of the three dynamically    *)
(* machine-checked Sec. 5 release-discipline invariants Access.tla exposes.  *)
(* The fourth Pass-3 attack class (spend escalation) is structural, see the  *)
(* header and module/Access.tla; it is intentionally not a conjunct here.    *)
(***************************************************************************)
\* @type: () => Bool;
INV_P10 ==
  /\ AcNoReleaseWithoutCapability   \* release names the right subject, record exists
  /\ AcScopeRespected               \* every released record belongs to its subject
  /\ AcNoReplayAcrossHosts          \* every release is bound to ServingHost (A14)

(***************************************************************************)
(* IndInv_P10 -- inductive invariant sufficient to close the unbounded      *)
(* proof. AcTypeOK is carried so the per-state record domains are pinned     *)
(* (an inductive-step --init may otherwise place arbitrary, ill-typed       *)
(* values into the variables, which would spuriously break the safety        *)
(* conjuncts). INV_P10 is the safety payload. No further strengthening is    *)
(* needed: every conjunct of INV_P10 is a closed predicate over `acReleased`*)
(* and `Records`, and every action either leaves `acReleased` unchanged or   *)
(* extends it ONLY with entries the release actions construct to satisfy all *)
(* four conjuncts (host = ServingHost, rec \in Records, rec.subject =        *)
(* subject), so INV_P10 is preserved given AcTypeOK. See notes.md for the    *)
(* inductiveness argument and the strengthening log.                        *)
(***************************************************************************)
\* @type: () => Bool;
IndInv_P10 ==
  /\ AcTypeOK
  /\ INV_P10

(***************************************************************************)
(* Assignment-form restatement of IndInv_P10, used as the --init predicate  *)
(* of the inductive-step check. Apalache requires every variable to be       *)
(* ASSIGNED in an init predicate; AcTypeOK's `\subseteq` / `\in S` shapes    *)
(* are assignment-friendly for set/Int variables, so IndInvInit_P10 reuses   *)
(* AcTypeOK directly and adds INV_P10 as a constraint over the assigned       *)
(* state. It is logically equivalent to IndInv_P10.                         *)
(***************************************************************************)
\* @type: () => Bool;
IndInvInit_P10 ==
  /\ acAuthorised \in SUBSET (Pubkeys \X (1..MaxTime))
  /\ acIssued \in SUBSET [ nonce: 1..MaxTime, expiry: 0..MaxTime,
                           chanBind: { ServingHost, ForeignHost },
                           subject: Subjects ]
  /\ acConsumed \in SUBSET (1..MaxTime)
  /\ acRevoked \in SUBSET (1..MaxTime)
  /\ acReleased \in SUBSET [ rec: Records, subject: Subjects,
                             host: { ServingHost, ForeignHost } ]
  /\ acNow \in 0..MaxTime
  /\ INV_P10

(***************************************************************************)
(* Constant initialiser. Reuses Access.AcConstInit verbatim (the Sec. 5     *)
(* smoke world): two hosts (so the cross-host / proof-forwarding case is     *)
(* witnessed), two subjects, two public keys, a handful of records over two  *)
(* assets and two timestamps. The release discipline is per-request local,   *)
(* so this instance exercises every action and guard; the inductive argument *)
(* is uniform in the world size (notes.md records a larger-world             *)
(* confirmation).                                                            *)
(***************************************************************************)
\* @type: () => Bool;
P10ConstInit == AcConstInit

=============================================================================
