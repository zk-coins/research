# Self-Publishing and the Accumulator Trilemma — Design Decision

**Status:** Accepted (2026-07-12)
**Scope:** the global nullifier accumulator and the on-chain publishing layer (spec §3.1, §3.4, §3.6, §3.7, §3.10)
**Resolves:** the publisher-contention problem (`docs#56`; risks `R-D2-5`, `R-D2-8`, `R-D7-2`)
**Requirement driving this:** *every node must be able to publish its own transactions without competitive pressure* (mandatory).

---

## Decision (2026-07-12)

**Decision criterion (set by the project owner).** zkCoins follows the original papers — the zkCoins gist and *Shielded CSV* ([ePrint 2025/068](https://eprint.iacr.org/2025/068)). A deviation from the papers is acceptable **only if** it is (a) proven safe beyond reasonable doubt **and** (b) documented crystal-clearly in the [`zk-coins/docs`](https://github.com/zk-coins/docs) specification repo. Both conditions are required; neither alone suffices.

**Assessment against that bar.** The `docs#40` batched accumulator — a constant **231-byte `BatchInscription`** committing the accumulator's `prev_root → new_root` transition, with nullifiers moved off-chain into the `BatchBundle` — does **not** clear the "proven safe beyond reasonable doubt" bar today:

- `docs#62` (*fork-or-halt*: a pending-DA inscription vs. a later inscription re-using the same `prev_root`) is **open**, with no objective, availability-independent live-admission rule that keeps two honest nodes convergent under withheld bundles.
- The companion `zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md` (`research#20`, in review) is itself explicitly **"blocked on objective live-admission semantics"** — the same missing prerequisite.
- §3 of this record derives the withholding safety break **formally** (red-team finding **F2**): off-chain nullifiers plus client-side first-occurrence let a selective-withholding attacker drive two honest nodes to opposite spend decisions — a soundness break, not merely a liveness stall.

**Decision.** The recommendation of this record is **accepted as the plan of record**: revert the accumulator design to the paper model — **on-chain half-aggregated nullifiers**, **client-side first-occurrence rebuild**, and **conditional NAV** for reorg safety (see §6–§7).

**Batched design retired to research.** The batched, constant-footprint design is **retired to the research track**. It may return to the specification only via a **proven, objective admission design** — the opt-in coordinator lane of §9, and the prerequisites enumerated in `zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md` (`research#20`, in review) — and only once that design is **documented crystal-clearly in `zk-coins/docs` before any spec adoption**.

**Implementation reality already matches this decision.** No revert of shipped code is required: the node's current architecture **inscribes per transaction** and **rebuilds global state from chain data alone** (`ALIASING.md` records the current on-chain object as "a full per-transaction commitment, ~177 bytes"); **no code implements the batch model** — `BatchInscription`/`BatchBundle` appear nowhere in [`zk-coins/node`](https://github.com/zk-coins/node) — and the engineering roadmap (`ROADMAP.md` → *Current Focus: Decentralization*) already targets the paper constructs: the **nullifier accumulator** (S2), **conditional NAV** (S3), **permissionless publisher batching** (S7), and the **half-aggregate-Schnorr** nullifier work (the paper-derived suite landing with S2/S3).

**Follow-up.** The specification revert will be tracked in a `zk-coins/docs` issue; `docs#56` (publisher contention) and `docs#62` (fork-or-halt) are expected to be **closed by that revert**.

---

## 1. TL;DR / Decision

The desired ideal — **every node self-publishes, contention-free, packing arbitrarily many transactions into one inscription at constant blockspace** — is **structurally unachievable** on Bitcoin L1 without adding a new trust base (a consensus, a committee, or a coordinator): no known construction escapes it, the argument below is tight, and every real system surveyed confirms it. This is a hard trilemma, not an engineering gap.

Given the **mandatory** requirement (contention-free self-publish) and the **non-negotiable** requirement (sound double-spend protection), the professional, consistent decision is:

> **Revert the `docs#40` accumulator design and adopt the peer-reviewed Shielded CSV model: publish nullifiers (half-aggregated) on-chain and rebuild the accumulator client-side by first-occurrence. Give up constant-per-batch on-chain size — it is the only one of the three properties that can be sacrificed while keeping the other two.**

This is a **minimal-change port** (zkCoins already has the account model and the per-account authorization object), it **additionally fixes** the accumulator's off-chain data-availability dependency (`R-D2-8`), and it raises the throughput ceiling from ~0.17 tx/s (contended) toward the ~100 tx/s order. The one genuinely new construct required is a reorg-safety mechanism (conditional NAV); the one real cost is that the per-block transaction **count** becomes publicly visible.

---

## 2. Problem and requirements

`docs#40` changed the on-chain object from per-transaction nullifiers (the original Shielded CSV model) to a **constant-size `BatchInscription` that commits the global accumulator transition `prev_root → new_root`**, with nullifiers moved off-chain into a `BatchBundle`. This bought constant on-chain size and hid the per-batch transaction count — but it made the accumulator a **single sequential writer**: every inscription must declare `prev_root` = the most-recently-admitted `new_root` (spec §3.4, §3.6 step 4), so concurrent publishers race for one slot and the loser is rejected as stale and must re-prove. The prior review logged this as **`R-D2-5`** (HIGH/HIGH) and **`R-D7-2`**, and `D4.md` shows it degenerates into *"a winner-take-all serialized write lock on global state, arbitrated by the Bitcoin fee market"* — a de-facto exclusive writer.

Requirements:
- **(F) Contention-free self-publish — MANDATORY.** Any node publishes its own transactions independently; no shared sequential writer; a publish is valid unless the payment data *directly contradicts* (an actual double-spend of the same coin).
- **(S) Sound double-spend — NON-NEGOTIABLE.** Two honest nodes never disagree on the unique valid spend, even under selective withholding of off-chain data.
- **(C) Constant on-chain size per publish — DESIRABLE ("would be perfect").** Arbitrarily many transactions per inscription at constant blockspace.

---

## 3. The trilemma: (C) ⟂ (F) ⟂ (S)

**Claim.** On Bitcoin L1 with no new trust base, you can have at most **two** of {C, F, S}.

**Argument.**
- **(C) ⟹ nullifiers off-chain.** Constant size means only a *commitment* is on-chain; the nullifier values live off-chain.
- **First-occurrence (the mechanism that gives F) needs total visibility.** To know a nullifier is "first," a verifier must see *every* earlier nullifier. Off-chain storage cannot guarantee this.
- **⟹ (C)+(F) breaks (S).** An attacker who selectively withholds one batch's bundle from node *Y* (but not *X*) makes *Y* miss the legitimate first spend and accept a later double-spend, while *X* accepts the first. Two honest nodes, opposite answers — a **safety** break (not merely liveness). *Verified by red-team finding F2.*
- **Conversely, (S)+(C) ⟹ a single canonical on-chain root + total order** (so withholding only stalls, never mis-resolves — this is exactly what `docs#40` does, and why it is safe-but-serial). A single canonical root that advances deterministically **requires a single sequential writer ⟹ breaks (F).**
- **(F)+(S) ⟹ nullifiers on-chain** (total visibility, no DA trust) **⟹ not constant ⟹ breaks (C).** This is Shielded CSV.

**The validity-proof escape fails.** A SNARK proving "none of my nullifiers appeared earlier" must define "earlier" against *some prior global state* — i.e. a chained root — which reintroduces the single writer and breaks (F). (`csv-bitcoin.md` single-use-seal proof-of-publication confirms "earlier" requires the prior committed set.)

**Cross-system evidence (which leg each real system sacrifices):**

| System | C | F | S | Sacrifice / added trust |
|---|---|---|---|---|
| **Shielded CSV** | ✗ | ✓ | ✓ | gives up C: ~64 B/tx on-chain, linear (paper Table 1: *"Asymptotic to 64 bytes"*) |
| **zkCoins `#40` (current)** | ✓ | ✗ | ✓ | gives up F: single sequential writer (`R-D2-5`, `D4.md`) |
| **Intmax2 (~5 B/tx)** | ~ | ✗ | ~ | block producer/sequencer + **client-side DA** trust; 5 B is *interactive, per-sender, amortized*, not constant-per-batch |
| **UTxO Binding** | ✓ | ✓ | ✓ | adds a **second chain** (Nervos CKB) — imports another consensus/DA |
| **Ecash / Fedimint / Ark** | ✓ | — | — | a **mint / committee / coordinator** is the arbiter (not trustless) |

Every "all three" escape adds exactly the consensus / committee / coordinator the requirement excludes. **The trilemma is fundamental.** (The project's own `D4.md`/`D5.md`/`GAPS_AGAINST_P1_P10.md` independently call the sequential single-writer "intrinsic" and note that removing honest-node divergence "would require putting nullifiers back on-chain, which #40 removed.")

---

## 4. Rejected design: independent off-chain batches + first-occurrence

An earlier draft proposed keeping `#40`'s constant size but dropping the `prev_root` chain — each node inscribes a constant-size commitment to *its own* off-chain batch, and the accumulator is rebuilt client-side by first-occurrence. **This is unsound and is rejected**, for two verified reasons:

- **Selective-DA safety divergence (F2).** As in §3: off-chain nullifiers + first-occurrence ⟹ withholding one bundle makes two honest nodes disagree on the winner. This is *worse* than `#40`, where withholding only stalls.
- **It buys nothing (F7).** It removes coupling at *publish* time but reintroduces it in full at *verify* time: to know a spend's nullifier is "first," a verifier must fold **all** batches (fetch all bundles). `#40`'s on-chain root chain is a *compressed witness* that all prior nullifiers were folded; first-occurrence over off-chain data has no such compression.

The lesson: **you cannot have (C) and (F) and (S) at once.** The constant-size commitment is precisely what forbids sound contention-free first-occurrence.

---

## 5. Decision and rationale

(F) is mandatory; (S) is non-negotiable for money. By the trilemma, **(C) is the only property that can be sacrificed.** The sound, peer-reviewed, project-foundational way to keep (F)+(S) is the **Shielded CSV on-chain-nullifier model**, from which `docs#40` deviated.

Why this over the alternatives the prior review floated (e.g. *permissionless `prev_root`-leasing / coordination*): those keep the shared root and therefore keep a queue/coordination step — they do **not** deliver (F). Only removing the single canonical on-chain root delivers contention-free self-publish, and removing it forces nullifiers back on-chain to preserve (S).

---

## 6. The port to zkCoins (minimal change)

zkCoins already contains every structural piece; the change is to move one object on-chain and relocate the double-spend check from an in-circuit batch transition to client-side first-occurrence.

1. **On-chain object → an aggregated nullifier set, not an accumulator root.** Move the existing `SpendRecord` authorization object — `{ Pkᵢ (x-only), BIP-340(skᵢ, message), message = inr ‖ ocr }` (spec §1.4) — **on-chain, half-aggregated** across the publish (Schnorr half-aggregation, as Shielded CSV does to reach its ~64 B/tx). This is structurally Shielded CSV's account nullifier `(Nullifier Public Key, Signature)` with the binding `message = inr ‖ ocr` in place of a transaction hash. No `prev_root`, no `new_root`, no reference to global state — so **publishing references nothing shared and can never go stale (F).**
2. **Authorization is intrinsic.** The on-chain BIP-340 signature under `Pkᵢ = current_pubkey` proves the spend was authorized by the account that owns the coins; nobody can post a nullifier for a coin they do not own. *(This is the fix for red-team finding F1 — the on-chain object must carry this signature, exactly as Shielded CSV does; a bare hash `nf` would be forgeable/observable and is insufficient.)*
3. **Client-side first-occurrence accumulator.** Every node scans Bitcoin in canonical order, verifies the half-aggregated signatures, and folds each entry keyed by the once-only `Pkᵢ` (equivalently the per-coin `nf`), binding it to the transition's `ocr`. **First occurrence wins**: a later spend re-using the same coin with a different `ocr` is the double-spend loser and its outputs are rejected by any receiver (its stored binding will not match). The accumulator is now **fully derivable from Bitcoin alone**.
4. **Validity proof stays off-chain (client-side validation).** The recursive coin proof still travels in the `CoinProof` bundle to the recipient, who re-verifies it (spec §2.3.3 step 2). The on-chain footprint is only the nullifier + aggregated authorization.
5. **This fixes `R-D2-8`.** Because the double-spend set is reconstructable from on-chain data, the accumulator no longer depends on off-chain `BatchBundle` availability, and two honest nodes at the same tip cannot diverge on the accumulator.

The account model maps directly: Shielded CSV's `(account ID, balance, nullifier pubkey, spent accumulator)` ↔ zkCoins' `AccountState {owner, balances, current_pubkey, coin_history_root}` (spec §1.5), and zkCoins already nullifies **per transition, not per coin** (spec §2.1: *"the account's single transition signature … no per-coin key"*). **Port-with-minimal-changes, not a redesign.**

---

## 7. Required new construct: reorg safety (conditional NAV)

Today, reorg safety leans on the publisher re-batching orphaned records onto the new tip (spec §3.3/§3.7). In a self-publish model **there is no publisher to re-batch**, so a reorg that orphans a self-published nullifier while its input coins vanish could strand/burn the account. Shielded CSV solves exactly this with a **conditional nullifier-accumulator value (conditional NAV)**: the spend commits to the accumulator over its dependencies; if the dependencies survive the reorg it proceeds, otherwise it becomes an in-circuit **no-op** (neither spends nor creates coins). **zkCoins must adopt a conditional-NAV equivalent.** This is the single genuinely new in-circuit piece of the port.

---

## 8. Trade-offs

**Given up:**
- **(C) constant size.** On-chain footprint becomes ~per-tx (Shielded CSV order, half-aggregated), not constant per batch.
- **Per-block transaction count becomes public.** `#40` hid it; on-chain nullifiers expose how many spends occur per block. **Amounts, assets, parties, and the transaction graph stay hidden** (the proof is still ZK; `Pkᵢ` rotates per transition so two of an account's on-chain entries are unlinkable — Shielded CSV's own privacy basis).

**Gained:**
- **(F) contention-free self-publish for *every* node** — no shared writer, no race, no coordinator.
- **(S) preserved**, and **`R-D2-8` fixed** (accumulator independent of off-chain bundle DA).
- **Throughput** rises from the contended ~0.17 tx/s order toward ~100 tx/s (now block-space-bound, not gated by a single writer).
- **Simpler reasoning** for double-spend (first-occurrence is the formally-favored gate; the P02 invariant *does not lean on the total order* — it tests against the live set, so the safety proof survives this change).

---

## 9. The only path to constant size (if ever wanted)

If constant-size efficiency is later desired for high-volume actors, the trilemma says it can come **only** via an **opt-in coordinator lane**: a permissionless (swappable) sequencer/aggregator that produces constant-size commitments, **with the on-chain self-publish path retained as the always-available, contention-free escape hatch.** This is graceful degradation (a per-transaction choice between *{C without F}* via the lane and *{F without C}* via the hatch); it never makes a single mechanism satisfy all three. It must be presented honestly as "constant size requires accepting an optional coordinator for that lane," never as free.

---

## 10. Out of scope (not fixed by this change)

This decision resolves contention/self-publish (`R-D2-5`, `R-D2-8`, `R-D7-2`) and the throughput gate. It does **not** address the other `D7` ceilings, which are independent: off-chain `CoinProof`-bundle DA growth (`R-D7-3`), mobile detect-scan bandwidth (`R-D7-4`), the `MAX_IN_COINS` fragmentation tax (`R-D7-5`), and recursive proving cost. Note in particular that **dropping the accumulator transition does *not* make publishers lightweight** (red-team F8): the dominant proving cost is the per-member foreign-field BIP-340 + SHA-256 work, which is unchanged; only the cheap, once-per-batch Poseidon SMT transition is removed.

---

## 11. References

- Shielded CSV: Private and Efficient Client-Side Validation — `papers-typst/shielded-csv.typ` (nullifier := (pubkey, tx-hash) ~L496/L537; first-occurrence accumulator ~L500; publishers post half-aggregated nullifiers ~L604; ~64 B/tx Table 1; conditional NAV ~L840).
- `formal/concept-review/D4.md` (single-writer write-lock), `D5.md` (cross-system), `D7.md` (throughput envelope ~0.17 tx/s).
- `formal/concept-review/RISKS.md` (`R-D2-5`, `R-D2-8`), `GAPS_AGAINST_P1_P10.md` (P20 intrinsic).
- `formal/property/P02_NoDoubleSpend/` — the no-double-spend invariant does **not** rely on the total order (tests batch nullifiers against the live set), so it survives this redesign.
- `docs/docs/specification.md` §1.4, §1.5, §2.1, §2.3.3, §3.1–§3.10, §4.
- Problem issue: `zk-coins/docs#56`.
