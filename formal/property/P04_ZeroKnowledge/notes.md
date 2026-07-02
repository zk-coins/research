# P04 — Zero-Knowledge (witness confidentiality) — notes

P04 is the **observational** property. Most of its STRENGTH is the **A2** axiom
(Plonky2 zero-knowledge), and the headline statement — *two witnesses with the
same `ProofData` are indistinguishable* — is a **hyperproperty** (a relation
over PAIRS of traces). Apalache checks **single-trace** state invariants, so it
cannot machine-check indistinguishability directly. This package therefore
splits P4 honestly into a machine-checked DYNAMIC half, a labelled STRUCTURAL
companion, and the A2/A10/A11/A3/A9 AXIOM half — mirroring the surrogate-scoping
discipline of P10 (`AcNoSpendEscalation` re-scoped structural) and P09 (liveness
surrogate). The certificate headline says which layer carries which claim.

## Toolchain (pinned)

```
Apalache version: 0.58.0  (build 711dce6)
Z3 (SMT backend): 4.14.1.0  (bundled in the Apalache distribution)
Host            : Apple Silicon (arm64), macOS (Darwin 25.5.0)
```

Every certificate re-states the Apalache + Z3 version it was produced under, so a
divergent result on a future version is attributable.

## What this is

Phase-2 deliverable: the witness-confidentiality COMPOSITION surface, formalised
as an **observer-flow / containment** machine layered on top of
[`module/Proofs.tla`](../../module/Proofs.tla) (the §2.1 compliance predicate `C`
and its per-account proof lineage, which PUBLISHES `ProofData`). `property.tla`
EXTENDS `Proofs` (which EXTENDS `Foundations` and `Assumptions`) and defines the
adversarial observer, the publication gate, the dynamic flow invariant
`INV_P4_flow`, the inductive invariants `ObsInv` / `IndInv`, the assignment-form
`IndInvInit`, the structural companion `PublishedCarriesNoWitnessField`, and the
`ConstInit` alias.

Because Apalache resolves `EXTENDS` only from the spec's own directory,
[`verify.sh`](./verify.sh) stages `property.tla` together with `Foundations.tla`,
`Assumptions.tla`, `Proofs.tla` from `formal/module/` into a `mktemp` scratch dir
and runs there — the module files are never duplicated into this committed
directory (same convention as `module/verify-modules.sh` and the other property
runners). The scratch dir and all `_apalache-out` are removed on exit.

## Property statement (M4 ground-truth)

- **Prose spec sections formalised** (baseline `zk-coins/docs@ed7fdece`, spec-v1.1):
  - **§2.1 clause 9 (public-input binding):** "All four `ProofData` fields —
    `new_account_state_hash`, `output_coins_root`, `input_nullifiers_root`,
    `coin_history_root` — **MUST** be the in-circuit-computed values above and
    are the proof's public inputs. **Nothing else is public**: amounts, asset
    ids, recipients, keys, and counts remain in the witness (zero-knowledge)."
    Formalised by `Proofs.Clause9_PublicBinding` (the four equalities ARE the
    projection) and the `PubItems` gate here.
  - **§3.5 metadata note:** a `BatchInscription` reveals only `Pkₚ`, the
    prev/new roots, the bundle content-address, and the anchoring tip —
    "nothing more"; the **record count is hidden on-chain**; the per-spender
    input count is bundle-only; "amounts, assets, parties, the transaction
    graph … remain invisible to a chain-only observer."
  - **§4.2:** the delivery-event plaintext carries `{detect_tag, epk, blob_id,
    blob_locators, ack_nonce}` and "**no** amount, asset, recipient address, or
    sender — those live only inside `ciphertext`"; the NIP-59 gift-wrap means "a
    relay sees neither sender nor recipient — only an opaque blob."

- **Pass-3 §P4 statement (the oracle), quoted verbatim:**
  > **Statement.** A proof π produced under §2.1 reveals to a verifier only the
  > four `ProofData` fields (all roots/digests) and no information about the
  > witness — amounts, asset ids, recipients, keys, counts, the coin graph.
  >
  > **Game.** A wins if there exists a PPT distinguisher that, given two
  > witnesses w₀, w₁ producing the same `ProofData`, can distinguish π₀ from π₁
  > with non-negligible advantage.
  >
  > **Attack-class enumeration.**
  > - *Plonky2 ZK property violation.* A2 dependency.
  > - *Leakage through the public-input set itself.* The roots … are 32-byte
  >   Poseidon digests. Distinct witnesses with the same `ProofData` are by
  >   construction indistinguishable at the public-input level.
  > - *Side-channel via proof size or timing.* Plonky2 produces constant-size
  >   proofs (§2.2). Constant-time verification. No size/timing leak.
  > - *Cross-transition correlation (rotating `Pkᵢ`).* Each transition's
  >   signature uses a fresh `Pkᵢ` derived from BIP-32 hardened path. Without
  >   `nk` and the spend branch (held only by the wallet), an outside observer
  >   cannot link two `SpendRecord`s of the same account. Anonymity-set quality
  >   depends on usage density (acknowledged in `risks.md`).
  > - *Cross-protocol composition with NIP-44 envelope leakage.* The bundle
  >   ciphertext is NIP-44 v2 with power-of-2 padding … Padding leaks an upper
  >   bound on bundle size — bundles are ~100KB+ with very similar size, so no
  >   amount-discriminating leak.
  >
  > **Verdict.** Sound under A2, A10. **Confidence: HIGH**.

- **The hyperproperty caveat (the whole point of the split).** The Game is a
  two-trace indistinguishability statement — a hyperproperty. Apalache checks
  single-trace invariants and CANNOT encode it. The faithful machine-checkable
  surface is therefore the **flow/containment** direction: nothing the protocol
  publishes carries a witness datum except through the four committed roots. The
  indistinguishability itself is the **A2** axiom (the first attack class in the
  enumeration is explicitly "A2 dependency").

## Dynamic vs structural vs axiom (the honest split)

| Layer | Carrier | Status | Content |
|---|---|---|---|
| **DYNAMIC** | `INV_P4_flow == ~obsTainted` | **machine-VERIFIED, unbounded, inductive** ([2]+[3]+[4]) | An adversarial observer scrapes the public projection of a live proof lineage and pulls **provenance-tagged** items into a leak set, **gated** by the §2.1 clause-9 publication discipline (`PubItems`: only public channels `ocrIdx`/`owner`/`nextPk`/`counter`). `obsTainted` flips iff a pulled item is tagged with a **witness** channel (`amount`/`nk`/`recipient`). The committed gate never exposes such an item → flag stays down in every reachable state. Genuinely dynamic (public view + leak set grow), negatively controllable (widen the gate → leak reachable). |
| **STRUCTURAL** | `PublishedCarriesNoWitnessField` | **stated, labelled structural, NOT a dynamic conjunct** (the P10 pattern) | The published record TYPES carry no witness field by construction: `ProofData` = `{newAsh, ocr, inr, chRoot}`; delivery-event plaintext = `{detectTag, epk, blobId, blobLocators, ackNonce}`; on-chain `batchNullifiers` = opaque `$nullifier` handles. A SHAPE fact, true in every state, not a reachable transition. NOT machine-claimed as a theorem: a VALUE-level disjointness across the Int-modelled scalar domains is meaningless (amount 3 == coin-index 3 as Ints), so shipping it would be a **vacuity trap**. Labelled structural, exactly as P10 labels spend-escalation. |
| **AXIOM** | A2 / A10 / A11 / A3 / A9 | **quoted, scoped, NOT machine-verified** | A2 = the indistinguishability hyperproperty (`Assumptions.PublicProjection` is the ideal oracle; Apalache does not discharge it). A10 = NIP-44 ciphertext, A11 = NIP-59 envelope, A3 = Poseidon tag/root unlinkability, A9 = HKDF key separation / rotating-`Pkᵢ` unlinkability. These are the trust budget P4's strength rests on. |

## The composition machine (dynamic half)

The observer layer models a relay / chain-only / verifier adversary watching a
proof lineage:

- **Publishing transitions.** `MintObserve` / `SendObserve` mirror
  `Proofs.MintStep` / `Proofs.SendStep` (a compliant transition with
  `C(newAuth, w, pd) = TRUE`), then attach `ObserveEffect(w, pd, gate)`. The
  lineage advances exactly as in `module/Proofs.tla`; the observer sees the same
  `(w, pd)`.
- **The publication gate** `PubItems(w, pd)` (the §2.1 clause-9 discipline): the
  provenance-tagged items publishing `(w, pd)` legitimately exposes — output
  coin **indices** (`ocrIdx`), and the new-state **identity** scalars `owner` /
  `nextPk` / `counter` (all part of the public `new_account_state_hash`). **No
  item carries a witness channel** — that IS clause 9. The account `balances`
  VALUES (which are amounts) are committed by `new_ash` but deliberately NOT
  exposed (a chain-only observer cannot read `AccountState.balances`, §4.2
  self-delivery note).
- **The witness-only items** `WitnessItems(w)`: `amount` (coin/issuance amounts),
  `nk` (nullifier key), `recipient` (output-template recipients) — each tagged
  with its **witness** channel.
- **`ObserveEffect`** lets the adversary pull ANY subset of the gate (full
  strength) into `obsLearnt`, and writes the violation flag
  `obsTainted' = (obsTainted \/ (\E it \in pulled : it.chan \in
  WitnessChannels))` **before** trusting the gate — so the gate's widening is
  observable (the P02/Onchain evidence-before-gate idiom).

### Why channel-provenance, not value-disjointness (vacuity-trap avoidance)

An earlier draft tested the leak with a VALUE-level cross-domain test
`pulled \cap WitnessOnlyScalars(w) # {}`. It produced a **spurious** violation:
in the smoke instance the owner address `H(Pk0)`, the nullifier key `nk`, and the
mint amount were all the same `Int` (`2`), so a pull of the **public** owner
scalar tripped the witness test by numeric coincidence — the exact Int-domain
trap the M4 ground truth warns about ("with Int-modelled scalars equality across
types is meaningless"). The model was rebuilt to tag every exposed/leaked datum
by its **provenance channel** (`[chan, val]`); the leak test is now `\E it \in
pulled : it.chan \in {"amount","nk","recipient"}`, a **structural** statement
about which channel carried the datum, immune to value coincidence. This is the
load-bearing content of P4's dynamic half, and is the genuinely dynamic,
negatively-controllable invariant the package requires.

## INV / IndInv design and the relative-inductiveness decision

- **`INV_P4_flow == ~obsTainted`** — the observer never extracts a
  witness-channel datum.
- **`ObsInv == ObsTypeOK /\ INV_P4_flow`** — the observer-layer invariant P4
  proves inductive. It is preserved by every move because the committed gate
  `PubItems` carries only public-channel items, so `obsTainted`, OR'd with a
  FALSE witness-channel term, stays down. **This argument is independent of
  `prState` well-formedness.**
- **`IndInv == PrTypeOK /\ ObsInv`** — the full invariant for the BASE and
  bounded-sanity checks (started from `Init`, where `PrTypeOK` holds as a
  reachable fact and is exercised to depth 8 by the bounded run).
- **Relative inductiveness (the compositional move).** `Proofs.PrTypeOK` is NOT
  inductive from an arbitrary symbolic pre-state (the Proofs module never proved
  it so; it is the module's own type-safety obligation). The flow property does
  not need it: the inductive **STEP** [3] carries `PrTypeOK` as the lineage-typing
  **hypothesis** (`IndInvInit` asserts `IndInv ⊇ PrTypeOK` on the generated
  pre-state, so `Next`'s `C(...)` guards evaluate over a well-shaped lineage) and
  checks that **`ObsInv`** — the observer invariant — is preserved. `PrTypeOK`
  itself is NOT required to be preserved here; it is `module/Proofs.tla`'s
  responsibility, and the bounded check [1] confirms it holds along reachable
  `Init`/`Next` to depth 8. This is the audit's compositional contract: P4 proves
  the FLOW gate, conditioned on the lineage being type-correct, which is Proofs'
  guarantee. No strengthening conjunct beyond the typing was required.
- **`IndInvInit` (assignment form via `Gen`).** The lineage state is
  RECURSIVELY typed (a `coinId` carries a `prevAsh` account state), so there is
  no closed finite enumeration to write a literal `\in` assignment form against.
  We use Apalache's symbolic generator `Gen(n)`: it ASSIGNS each variable an
  arbitrary value of its inferred type (bounded by `n` on collection sizes — the
  standard over-approximation of the type-correct pre-state), then `IndInv`
  constrains it. `n = 4` covers the smoke instance; a larger-`n` / larger-
  instance confirmation is recorded below.

## Commands and outcome

See [`certificate.txt`](./certificate.txt) for the full transcript. Summary
(runner: [`verify.sh`](./verify.sh); [1] ≈ 42 s, the rest < 4 s each on the host
above):

| # | Check | Command shape | Outcome |
|---|---|---|---|
| 1 | bounded sanity | `--init=Init --next=Next --inv=IndInv --length=8` | NoError |
| 2 | inductive base | `--init=Init --next=Next --inv=IndInv --length=0` | NoError |
| 3 | inductive step | `--init=IndInvInit --next=Next --inv=ObsInv --length=1` | NoError |
| 4 | implication | `--init=IndInvInit --next=Next --inv=INV_P4_flow --length=0` | NoError |

Checks 2 + 3 + 4 together are the unbounded proof of the dynamic flow half. All
runs use `--cinit=ConstInit`.

### Uniformity confirmation

Checks 2/3/4 were re-run at a larger instance — `Accounts = {1,2,3}` (via a local
`ConstInit` override) — all three report **NoError**. The flow argument is
per-transition local (the gate is evaluated fresh on each publish), so the result
is uniform in the instance size; the committed `ConstInit` (`= PrConstInit`,
`Accounts={1,2}`) fixes a fast default run.

## Vacuity probe and negative control (the model earns its keep)

**(V) / (V2) Reachability / vacuity probes.** A throwaway `probe.tla` (EXTENDS
`property`, `/tmp`, not committed):

- `ObserverStaysEmpty == (obsPublic = {}) /\ (obsLearnt = {})`,
  `--inv=ObserverStaysEmpty --length=4` → **Error** at State 1 (`obsPublic` grew
  with a published `ProofData`). The observable state is not vacuously empty.
- `LearntStaysEmpty == obsLearnt = {}`, `--inv=LearntStaysEmpty --length=4` →
  **Error** at State 1 with `obsLearnt = { [chan |-> "owner", val |-> 1] }` and
  `obsTainted = FALSE`. The adversary genuinely pulls a **public-channel** item;
  `~obsTainted` holds precisely BECAUSE that learned item is public-channel, not
  because the leak sink is unreachable.

So `INV_P4_flow` is satisfied by a non-trivially-exercised observer.

**(NC) Negative control — the clause-9 gate is load-bearing.** In a `/tmp` copy
of `property.tla` the committed gate was WIDENED to expose a witness-channel item:
```
CommittedGate(w, pd) == PubItems(w, pd) \union { Item("nk", w.nk) }
```
and run with `--init=Init --next=Next --inv=INV_P4_flow --length=4`. Outcome:
**Error** — `INV_P4_flow` violated at State 1:
```
State0: obsTainted = FALSE, obsLearnt = {}
State1: obsLearnt = { [chan |-> "nk", val |-> 1] }, obsTainted = TRUE
        => ~obsTainted is FALSE      [witness datum reached the observer]
```
With the gate widened to expose `nk`, the adversarial `Observe` pulls a
witness-channel item, the leak flag flips, and the flow invariant breaks —
exactly the Pass-3 P4 "leakage through a witness channel" win the clause-9
discipline rules out. With the committed gate (public channels only), all four
`verify.sh` checks return NoError; the gate is genuinely load-bearing. The
committed `property.tla` and the module files are unchanged; the `/tmp` copy and
its `_apalache-out` were discarded.

## Cross-check vs Pass-3 (Phase-4 input)

Pass-3 label: **HIGH** (sound under A2, A10).

| P4 aspect | Pass-3 | Apalache verdict (this cert) |
|---|---|---|
| Composition-level FLOW/containment — published artifacts carry no witness datum except via the four roots | covered by "Leakage through the public-input set itself" + the metadata/envelope classes | **VERIFIED — unbounded** (dynamic, [2]+[3]+[4]); the clause-9 gate is machine-checked and load-bearing (negative control) |
| Typed disjointness of the published record shapes | implicit in the §2.1/§3.5/§4.2 record definitions | **structural** (stated, labelled; not machine-claimed — value-level disjointness is a vacuity trap) |
| Indistinguishability hyperproperty (two equal-`ProofData` witnesses) | "A2 dependency" (first attack class) | **A2 AXIOM** — out of single-trace scope, quoted + scoped, NOT machine-verified |
| Side-channel via proof size/timing | constant-size proofs (§2.2), constant-time verification | out of scope (timing/size is not a functional state property) |
| Cross-transition `Pkᵢ` correlation; NIP-44 padding | A9 (rotating key unlinkability); A10/A11 | **A9 / A10 / A11 AXIOMs** — quoted + scoped |

**Verdict at the composition level: confirmed HIGH.** The machine-checked half
confirms the clause-9 flow gate — no published artifact reachable in the
observable state carries a witness-channel datum — as an unbounded inductive
invariant, with a real negative control. The package does NOT over-claim: the
indistinguishability hyperproperty remains the A2 axiom, the typed-disjointness
is labelled structural, and the transport/envelope/key-unlinkability primitives
are quoted axioms (A10/A11/A3/A9). Full reconciliation across all properties is
deferred to Phase 4.

**Oracle/baseline provenance.** The Pass-3 P4 prose was written against the
develop snapshot; the baseline here (`ed7fdece`, spec-v1.1) carries the same
§2.1 clause-9 public-input binding, the §3.5 constant-per-batch metadata note,
and the §4.2 delivery-payload minimisation, so the audit remains a valid oracle.
The `docs#47` ZBE chunked framing (§4.2.1) is a thin AEAD wrapper that does not
change what a verifier may learn from a proof (still only its public inputs, A2),
so the zero-knowledge claim is unchanged by the v1.1 bump.

## Scope / what is deliberately NOT modelled

- **The A2 indistinguishability hyperproperty** is the headline; it is an
  ideal-functionality axiom (`Assumptions.PublicProjection`), out of single-trace
  Apalache scope. This package machine-checks only the composition-level FLOW
  containment that A2's premise rests on.
- **Pre-image hiding / one-wayness of the four Poseidon/SMT roots** is A2/A4: a
  root exposes its committed KEY SET (coin ids, account-state identity) but not
  the scalar witness fields that produced it. Modelled as the `PubItems` gate, not
  re-derived at the byte level.
- **NIP-44 v2 ciphertext + NIP-59 gift-wrap** (A10/A11) and **detect_tag / key
  unlinkability** (A3/A9) bound the transport + detection channels; the transport
  FLOW is machine-checked separately in
  [`P08`](../P08_TransportConfAuth/) (the relay/Eve confidentiality invariant
  `TrAvailabilityNotSafety`). Here they are quoted axioms.
- **Proof size / verification timing side-channels** (§2.2 constant-size,
  constant-time) are not functional state properties and are out of scope.
- **Anonymity-set quality / usage density** (the rotating-`Pkᵢ` cross-transition
  correlation class) is acknowledged by the audit as `risks.md` material
  (statistical, not a safety invariant) and is not modelled.
- **The `module/Onchain.tla` BatchInscription fields and `module/Transport.tla`
  delivery-event plaintext** are the two other observable surfaces; their
  witness-freedom is the STRUCTURAL companion (record shapes), recorded above and
  cross-referenced to P02 (on-chain admission) and P08 (transport flow). The
  dynamic flow proof here is over the `ProofData` publication surface, the one
  surface where a genuinely dynamic, gated adversary action has real content.
