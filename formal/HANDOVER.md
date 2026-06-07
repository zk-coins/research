# Handover: zkCoins 100% Logical Verification Initiative

**You** (the receiving agent session) are about to execute a formal-verification initiative against the zkCoins v1 specification. This document is your **complete bootstrap** — you should be able to start from zero conversational context and execute end-to-end. The prior session that planned this work is now closed; everything that session knew is here.

**Project lead (the user):** communicates in German, expects German responses; code/commits/PRs in English. Has full context — do not over-explain zkCoins to them, but do confirm before any irreversible action.

---

## 1 · The job, in one paragraph

The zkCoins specification (`docs.zkcoins.app/specification`, source repo `zk-coins/docs`) claims ten security properties P1–P10 (No-Forgery, No-Double-Spend, Balance Conservation, Zero-Knowledge, On-chain Privacy, Client-Side Validation, Issuance Authenticity v1, Transport Confidentiality + Authentication, Recovery Completeness, Capability Discipline). Three manual audit passes (`zk-coins/research/audit/2026-06-06.0{1,2,3}.md`) reach HIGH confidence on every property at the spec composition level using game-style human arguments. The project lead has declared this insufficient: *"ich will nicht 'richtung 100%'. ich will volle 100%."* The job is to replace every manual argument with a machine-checked Apalache (TLA+ SMT-backed unbounded model checker) certificate. The plan is in [`100-percent-verification-plan.md`](./100-percent-verification-plan.md). Cryptographic primitives are axiomatized as ideal functionalities (A1–A17 in [`README.md`](./README.md)). Four meta-assumptions (M1–M4) are out of scope by construction. When every property in `formal/property/Pn_<Name>/` has a passing `certificate.txt` and every divergence from Pass-3 is reconciled, the work is done.

---

## 2 · What you must read before doing anything

In this order:

1. **[`README.md`](./README.md)** — Initiative framing, three classes of "100%", what's in/out of scope, the A1–A17 axiom table with which-property-consumes-which, the M1–M4 meta-assumptions, the directory layout. (This is canonical.)
2. **[`100-percent-verification-plan.md`](./100-percent-verification-plan.md)** — The operational plan. Phase 0–6 deliverables and time targets, risk inventory, hard dependency on `docs#40`, progress table.
3. **[Pass-3 audit `audit/2026-06-06.03.md`](../audit/2026-06-06.03.md)** — Game-style manual arguments for every property. Read §4 (per-property analysis) carefully — this is what you are mechanizing.
4. **The spec itself**, pinned at commit `a7a9f97`: `git show a7a9f97 -- docs/specification.md` in a clone of `zk-coins/docs`. Or web: `https://github.com/zk-coins/docs/blob/a7a9f97/docs/specification.md`.

Do not start TLA+ work until you have read all four.

---

## 3 · Current state when you pick this up

### 3.1 Repositories

| Repo | URL | Your role |
|---|---|---|
| `zk-coins/docs` | `https://github.com/zk-coins/docs` | spec source, read-only for this work |
| `zk-coins/research` | `https://github.com/zk-coins/research` | **your workspace** — every TLA+ module, every certificate, every audit doc lands here |

### 3.2 Branches and PRs

| Branch | PR | State | What's in it |
|---|---|---|---|
| `zk-coins/research:formal/100-percent-plan` | [#8](https://github.com/zk-coins/research/pull/8) | Draft | This handover, README, plan. **You extend this branch with Phase-0 onward.** |
| `zk-coins/research:audit/spec-2026-06-06-03` | [#6](https://github.com/zk-coins/research/pull/6) | Draft | Pass-3 audit (snapshot; do not modify) |
| `zk-coins/research:feat/formal-nullifier-chaining-model` | [#3](https://github.com/zk-coins/research/pull/3) | Draft (legacy) | Bounded TLC model of `FirstSpendWins` — **superseded** by Phase 0 unbounded port. Do not merge; do not delete. |

### 3.3 Spec snapshot

`zk-coins/docs@a7a9f97` — develop tip after all 2026-06-06 hygiene work merged:
- F1 DetectKey (#34), F16 rollback semantics (#35), F17 ACK nonce-binding (#36), F9 addr_sig+pk0 (#38), F12 latest-state selection (#39), anchor-polish + onBrokenAnchors:throw + profile preimage pin (#37)
- Spec is **single-page** at `docs/specification.md` (consolidated in #33; not eight separate files).

### 3.4 Open spec PR you must coordinate with

[`docs#40`](https://github.com/zk-coins/docs/pull/40) — "spec: redesign on-chain layer to constant-per-batch footprint" (Variant-2). +342/-255. Structural rewrite of §3.5/§3.6. **Your `Onchain.tla` model must target the post-docs#40 form.** Three options for handling, decision is the project lead's (see §6 below).

### 3.5 What does NOT exist yet

- No TLA+ modules in `formal/module/`
- No properties in `formal/property/`
- No Apalache certificates
- No Apalache installation on the user's host (you set this up in Phase 0)

---

## 4 · Hard rules (do not violate)

These come from the project lead's global working-agreement and from incidents earlier in this initiative. Internalize them.

### 4.1 Language

- **Communication with user: German.** Always.
- **Code, commits, PRs, branches: English.** Always.

### 4.2 Git workflow

- **NEVER push directly to `main`, `master`, or `develop`** on `zk-coins/*` repos. Always feature branch + PR.
- **Always file PRs as Draft:** `gh pr create --draft --repo zk-coins/<repo> ...`. Never `gh pr create` without `--draft` and `--repo`.
- **No force-push without explicit user authorization.** If you need to rewrite history, ASK FIRST. If a rebase produces conflicts, prefer a merge-commit or new top-commit over `--force-with-lease`. (A prior force-push happened in this initiative without authorization — do not repeat.)
- **No `git rebase -i` or `git add -i`** (interactive flags don't work in this environment).
- **No `--amend`, no `--no-verify`, no `--no-gpg-sign`** unless the user explicitly says so.
- **Commit-message convention:**
  - First line: `<scope>: <imperative summary>` (e.g. `formal: model Onchain admission state machine`)
  - Body: explain the why + the what (multi-line OK)
  - **No AI-authorship footer** (no `Co-Authored-By` trailer). No AI-tool/vendor mention anywhere in commits or PRs.

### 4.3 Before every commit

For the docs repo (when you propose spec changes derived from a verification finding):
1. `npm run lint` (or `yarn lint`)
2. `npm run build` — must be clean
3. Only then commit

For the research repo (your main workspace):
- `formal/` is markdown + TLA+ + Apalache config. Markdown lints are fine; TLA+ should `apalache-mc parse` cleanly before you commit.
- Run Apalache on each property *before* you commit its certificate.

### 4.4 Secrets

- Never commit `.env`, credentials, seed phrases, anything that looks like a key.
- Never hardcode seed phrases in commands. If you need wallet creds, ask the user to put them in a local `.env`.

### 4.5 Self-check first, ask user second

- Anything you can verify via `gh`, `git`, build, `Read` — verify it yourself. Don't ask the user "did this merge?" — `gh pr view N` answers it.
- Only ask the user about: open design decisions, big architectural pivots, anything irreversible (delete, force-push, mainnet deploy, send email, etc.).

### 4.6 Cosmetic

- No emojis in code, commits, or files unless the user explicitly asks for them.
- Don't create documentation files beyond what the work requires. Don't write a README for the sake of it.
- Don't add `# what this does` comments — well-named identifiers self-document. Only comment WHY when it's non-obvious.

---

## 5 · Tools you will use

### 5.1 Apalache

**Apalache** ([apalache.informal.systems](https://apalache.informal.systems)) — TLA+ SMT-backed model checker. Github: `https://github.com/informalsystems/apalache`.

Install (Phase 0):

```bash
# Option A: download release binary (recommended for pinned version)
APALACHE_VERSION="0.45.7"   # or latest as of Phase-0 start; PIN this
mkdir -p ~/tools/apalache && cd ~/tools/apalache
curl -L -o apalache.tgz "https://github.com/informalsystems/apalache/releases/download/v${APALACHE_VERSION}/apalache-${APALACHE_VERSION}.tgz"
tar -xzf apalache.tgz
echo "export PATH=\$HOME/tools/apalache/apalache/bin:\$PATH" >> ~/.zshrc
# Verify:
apalache-mc version
```

**Pin the Apalache version.** Every certificate records the version used. If a future verification produces a different result on a newer version, the certificate fingerprints which version produced it.

**Apalache invocation pattern:**

```bash
# Parse-only (smoke test):
apalache-mc parse module/Onchain.tla

# Type-check (catches most modeling errors before verification):
apalache-mc typecheck module/Onchain.tla

# Verify an invariant (unbounded, by default):
apalache-mc check --inv=NoDoubleSpend property/P02_NoDoubleSpend/property.tla

# Verify with explicit inductive invariant:
apalache-mc check --inv=NoDoubleSpend --init=Init --next=Next --length=100 property/P02_NoDoubleSpend/property.tla
```

For unbounded proofs, the `--length` parameter sets the diameter Apalache searches for counter-examples. You strengthen the inductive invariant (`IndInv_Pn`) until Apalache returns "no error found" at sufficient length, OR you use `apalache-mc check --inv=INV --init=Init --next=Next --inductive=IndInv`.

### 5.2 TLA+ ecosystem

- **TLA+ Toolbox** — heavy IDE, optional. Most work fits in plain text editing.
- **TLC** — classical TLA+ model checker, bounded. Useful for sanity checks on small instances; not the primary tool here.

### 5.3 `gh` CLI

You will use `gh` extensively. Common commands:

```bash
gh pr create --draft --repo zk-coins/research --base develop --head <branch> --title "..." --body "..."
gh pr view <N> --repo zk-coins/<repo> --json state,mergeable,mergeStateStatus
gh pr checks <N> --repo zk-coins/<repo>
gh pr list --repo zk-coins/<repo> --state open
```

### 5.4 Workspace

- Your CWD for this work: a local clone of `zk-coins/research` in the session workspace.
- A sibling clone of `zk-coins/docs` — read-only for this initiative (you reference the spec; you don't modify it unless a verification surfaces a finding that warrants a docs PR).

---

## 6 · Open decisions you must resolve with the user before Phase 1

**Do not start Phase 1 until these are decided.** Phase 0 (Apalache install + nullifier-chaining port) can run in parallel.

### Decision D1 — `docs#40` strategy

`docs#40` (Variant-2 on-chain redesign, +342/-255) is OPEN and not yet merged. `Onchain.tla` must target the post-docs#40 form because retrofitting later wastes 3-5 days.

| Option | Trade-off |
|---|---|
| **(a) Wait for `docs#40` to merge** before starting Phase 1 modeling of §3 | Clean baseline. Idle Phase-1 time until then. |
| **(b) Model `Onchain.tla` against the `docs#40` branch tip from the start** | Earliest start. Requires rebase if `docs#40` evolves. |
| **(c) Model `Onchain.tla` against current develop, retrofit after `docs#40` merge** | Fastest Phase-1 start. 3-5 days throwaway work later. |

Ask the user. Recommend (b) if `docs#40` is stable, (a) otherwise.

### Decision D2 — Phase 0 host

Apalache needs a host with enough RAM (≥ 8 GB recommended for the larger properties). Options:

- **A local Apple Silicon workstation** (ample RAM for the larger properties) — interactive iteration. Reasonable.
- **A remote always-on host** — for long-running verification (nightly runs).

Ask the user where Apalache goes.

### Decision D3 — Acceptance of A15–A17

A15 (half-aggregation soundness), A16 (Merkle/SMT CR lifting), A17 (`serialize` injectivity) were proposed and accepted by the project lead in the prior session (added to the plan in commit `e92c86d`). They are derived-primitive axioms; each follows from a published reduction to A1–A14. If the project lead reaffirms acceptance, no action; if they want to retract any of them, the affected modules grow and time estimates extend.

Default: confirm with one short message; assume accepted.

---

## 7 · Execution: per-phase work instructions

### Phase 0 — Setup (target: 0.5–1 day)

**Goal:** Apalache running on the chosen host, legacy `FirstSpendWins.tla` ported and verified unbounded as a smoke test that the toolchain works end-to-end.

**Steps:**

1. Install Apalache per §5.1. Pin version. Record in `formal/property/P02_NoDoubleSpend/notes.md`:
   ```
   Apalache version: X.Y.Z
   Z3 version: A.B.C
   Host: <hostname>, <RAM>, <OS>
   ```
2. Read `formal/nullifier-chaining/FirstSpendWins.tla` (legacy branch `feat/formal-nullifier-chaining-model`). Translate the bounded TLC model to Apalache.
3. Replace `Bound = 5` with an unbounded inductive invariant.
4. Place the result at `formal/property/P02_NoDoubleSpend/property.tla` + `apalache.cfg`.
5. Run Apalache. Record stdout in `certificate.txt`. Record decisions in `notes.md`.
6. Commit on branch `formal/100-percent-plan` (extend PR #8). Message: `formal: Phase 0 — port FirstSpendWins to Apalache unbounded (P02 verified)`.
7. Update the Progress table in [`100-percent-verification-plan.md`](./100-percent-verification-plan.md) §6 — mark P02 "verified".

**Done when:** `apalache-mc check --inv=NoDoubleSpend property/P02_NoDoubleSpend/property.tla` reports "no error found" and the certificate is committed.

### Phase 1 — Formal modeling (target: 2–3 days)

**Goal:** Complete `formal/module/` — eight TLA+ files that together model the spec.

**Process:** Spawn subagents in parallel, one per module. Each subagent reads one spec section and produces one TLA+ file. Harmonize at the end (datatypes must line up across modules).

**Modules and source sections:**

| File | Spec sections | Consumes axioms |
|---|---|---|
| `module/Foundations.tla` | §1 (all subsections) | A17 |
| `module/Proofs.tla` | §2.1, §2.2 | A1, A2, A3, A16 |
| `module/Onchain.tla` | §3.5, §3.6, §3.7, §3.9, §3.10 (or post-docs#40 if D1 = b) | A7, A12, A15, A16 |
| `module/Transport.tla` | §4.2, §4.3, §4.6 | A7, A8, A9, A10, A11 |
| `module/Access.tla` | §5.1 – §5.8 | A5, A7, A14 |
| `module/Architecture.tla` | §6.3, §6.6 | A12, A13 |
| `module/Assumptions.tla` | A1–A17 as TLA+ operators with stated security properties | — |
| `module/Adversary.tla` | Pass-3 §2 adversary model | — |

**Modeling guidelines:**

- **Faithful translation.** Every normative clause in the prose spec maps to one TLA+ predicate. If a clause is too complex to model exactly, abstract it via an axiom (see A15–A17 pattern) — but only if the abstraction is defensible and recorded in the README axiom table.
- **Types first.** Use Apalache's `@type` annotations everywhere. The type-checker catches 80% of modeling bugs before verification.
- **Action-style state machine.** TLA+ idiom: `Init`, `Next == Action1 \/ Action2 \/ ...`, invariants over reachable states.
- **Don't over-model.** If a clause is purely informative or operational (e.g. "wallet SHOULD surface this to user"), skip it — it's not a security property.

**Done when:** Each `.tla` file type-checks (`apalache-mc typecheck module/<file>.tla`) clean, and a smoke `Init /\ Next` step on each is verified to produce reachable states without errors.

### Phase 2 — Property formalization (target: 1–2 days)

**Goal:** Each P1–P10 stated as a TLA+ invariant or temporal property under `formal/property/Pn_<Name>/`.

**Template per property:**

```tla
---------------- MODULE property ----------------
EXTENDS Module.Foundations, Module.Proofs, Module.Onchain  \* etc.

\* --- Property statement (faithful to Pass-3 audit §4 statement) ---
INV_Pn == ...

\* --- Inductive invariant if needed ---
IndInv_Pn == INV_Pn /\ ...

\* --- Temporal property for liveness (e.g. P9) ---
Temporal_Pn == [](...)
==================================
```

**For each property, also create `notes.md` quoting:**
- The prose spec section formalized.
- The Pass-3 §4 game-style statement (this is your M4 ground-truth).
- Any modeling decisions (e.g. "we model `nf` as an opaque element of `Nullifier`; A3 entails no collisions").

**Done when:** All 10 property directories populated. Apalache parses each cleanly.

### Phase 3 — Apalache verification (target: 3–5 days)

**Goal:** Each property has a passing `certificate.txt`.

**Procedure per property:**

1. Run `apalache-mc check --inv=INV_Pn property/Pn_<Name>/property.tla`.
2. Three possible outcomes:
   - **"No error found"** → Save stdout as `certificate.txt`. Update `notes.md` with command + time. Mark P*n* "verified" in plan §6 Progress.
   - **"Inductive invariant not strong enough"** → Strengthen `IndInv_Pn` (add more conjuncts that hold in reachable states and are preserved by `Next`). Retry. Three failed strengthenings → escalate per §4 Risk.
   - **Counter-example trace** → Investigate. Two possibilities:
     - (a) **Model bug** — the TLA+ doesn't match the spec. Fix the model, re-run. Log decision in `notes.md`.
     - (b) **Spec bug** — the spec really does have this defect. **Stop the rest of Phase 3.** File a spec finding (audit doc + docs PR). The user decides whether to fix the spec (and re-verify) or accept the finding as a known limitation.

**Time per property (realistic):**

- Easy (P10, P2): 0.5–1 day each — straightforward state-machine invariants.
- Medium (P3, P5, P6, P9): 1 day each.
- Hard (P1, P4, P7, P8): 1–2 days each — composition with primitive axioms.

**Done when:** all 10 `certificate.txt` files exist with "no error found" results.

### Phase 4 — Cross-check + reconciliation (target: 1–2 days)

**Goal:** Reconcile every Apalache verdict against Pass-3 audit §4 confidence label. Divergences are the M2/M4 trip-wire.

**Procedure:**

1. Build a table:

   | Property | Pass-3 label | Apalache verdict | Resolution |
   |---|---|---|---|
   | P1 | HIGH | verified | confirmed |
   | … | | | |

2. For each row:
   - HIGH + verified → "confirmed". Done.
   - HIGH + counter-example (and spec bug was filed and fixed) → "Pass-3 was wrong about Pn"; record in audit doc.
   - MEDIUM + verified → "Pass-3 was over-cautious about Pn"; record in audit doc.
   - HIGH + inductive-invariant-failed → "inconclusive — escalate to Phase 6".

3. **Record the Pass-4 reconciliation** (certificate paths + per-property Pass-3-label-vs-Apalache-verdict table) in `formal/CERTIFICATE.md`. The Pass-3 audit document is a read-only snapshot (§3.2) and is **not** amended; the Pass-4 cross-check lives in `formal/` alongside the certificates it references, so the snapshot stays immutable. (Resolved this way 2026-06-07; the earlier "amend the Pass-3 doc on its branch" plan contradicted the snapshot rule.)

**Done when:** Every property's row has a recorded resolution.

### Phase 5 — Documentation + sign-off (target: 1–2 days)

**Goal:** The 100% initiative is **complete** per §7 Definition of done. Ready-for-review PR to the user.

**Steps:**

1. Update `formal/property/STATUS.md` (create if not exists) — final progress table, all green.
2. Update [`100-percent-verification-plan.md`](./100-percent-verification-plan.md) §6 Progress — all rows verified, certificate links added.
3. Add a top-level `formal/CERTIFICATE.md` summarizing: properties verified, axioms used, meta-assumptions inherited, reproducibility instructions, sign-off date placeholder.
4. Verify reproducibility from a clean clone: blow away `formal/` build artifacts, re-run every Apalache command, confirm same results.
5. Add `formal/verify-all.sh` — single script that runs every certificate. Add `Makefile` if appropriate.
6. Flip the PR from Draft to Ready-for-Review. Tag the user. Write a short summary message in chat.
7. Wait for user to read and sign off.

**Done when:** The user signs off and (optionally) merges the PR.

### Phase 6 — Residual escalation (only if needed)

If a property fails to verify in Phase 3 (inductive-invariant intractable, decidability boundary, real spec defect that user doesn't want to fix):

- **TLAPS** (TLA+ Proof System) — heavier, but still mechanical. Hand-construct the proof.
- **Reduction to another property** — sometimes Pn follows from Pm; prove the reduction.
- **Stronger axiomatization** — propose a new axiom (with reduction to A1–A17 if possible) and ask user to accept.
- **Lean4 fallback** — last resort, weeks per property.

Any property reaching Phase 6 is outside the 100% guarantee until resolved. Make this explicit in `STATUS.md`.

---

## 8 · Communication protocol with the user

### 8.1 Briefings (responses to the user)

- **German**, short, direct.
- Lead with the action ("Phase 1 fertig, alle 8 Module type-checken clean") not the meta ("Ich habe nun…").
- Hyperlink every PR/issue reference: `[docs#34](https://github.com/zk-coins/docs/pull/34)`. Never naked `#34`.
- One sentence per update is almost always enough.
- End with: what's next, OR an open question.

### 8.2 Briefings to other agent sessions (hand-offs)

If you need to hand off to ANOTHER agent session (continuing this work or running something in parallel):

- **One `do script` message, not 2-5 parts.** Quote escaping is solved by putting the whole message in a heredoc rather than splitting.
- Briefing must be self-contained — the receiving session has no chat history.

### 8.3 When the user writes "merged"

The user is reporting that a PR they were reviewing has been merged. You:

1. **Self-check via `gh`** that the merge happened (don't ask the user).
2. Watch the develop CI on the merge commit.
3. Report green or red.

Do NOT relay this to another session unless the merge specifically affects that session's task.

### 8.4 What you should self-check vs ask the user

| Self-check (don't ask) | Ask the user |
|---|---|
| Did PR #X merge? `gh pr view X --json state,mergedAt` | Should I take approach (a) or (b)? |
| Is the build green? `gh pr checks X` | Do you accept axiom A18 if I propose it? |
| Does file Y exist? `Read Y` | Should I file this finding as LOW or MEDIUM? |
| Does spec mention concept Z? `grep` | Do you want me to extend scope to property Y? |

---

## 9 · The 17 axioms + 4 meta-assumptions (your trust budget)

Quoted from [`README.md`](./README.md) for at-hand reference; do not duplicate, link to README from your work.

**A1–A17:** explicit cryptographic and operational primitives — Apalache trusts these, you compose them.

**M1–M4:** unprovable inside the verification:
- M1 Apalache soundness
- M2 TLA+ ↔ spec fidelity (the load-bearing one — your translation must be faithful)
- M3 Adversary-model completeness
- M4 Property-statement correctness (also load-bearing — your INV_Pn must capture the right thing)

**Every counter-example you find in Phase 3 is potentially a spec bug, a model bug (M2), or a property-statement bug (M4). Discriminating which is the diagnostic skill.**

---

## 10 · References

| What | Where |
|---|---|
| Spec snapshot | `https://github.com/zk-coins/docs/blob/a7a9f97/docs/specification.md` |
| Open spec PR (Variant-2) | [`docs#40`](https://github.com/zk-coins/docs/pull/40) |
| Pass-1 audit | `audit/spec-2026-06-06-01` branch, `audit/2026-06-06.01.md` |
| Pass-2 audit | `audit/spec-2026-06-06-02` branch, `audit/2026-06-06.02.md` |
| Pass-3 audit | [`research#6`](https://github.com/zk-coins/research/pull/6), `audit/2026-06-06.03.md` |
| This plan | [`research#8`](https://github.com/zk-coins/research/pull/8) — `formal/README.md`, `formal/100-percent-verification-plan.md`, this `formal/HANDOVER.md` |
| Legacy TLC model | `feat/formal-nullifier-chaining-model` branch, `formal/nullifier-chaining/FirstSpendWins.tla` |
| Apalache | `https://apalache.informal.systems` · `https://github.com/informalsystems/apalache` |
| TLA+ standard reference | Leslie Lamport, "Specifying Systems" (free PDF online) |

---

## 11 · Sign-off ritual

When you believe the work is complete:

1. All 10 certificates exist and pass.
2. Pass-4 cross-check recorded in `formal/CERTIFICATE.md` (Pass-3 snapshot left read-only).
3. `formal/verify-all.sh` runs every certificate from a clean clone.
4. PR flipped from Draft to Ready-for-Review.

Then write to the user, in German:

> "Phase 5 fertig. Alle 10 Properties mechanisch verifiziert. Audit-Doc um Pass-4 ergänzt. Reproducibility verified. PR ist ready-for-review. Stand: [link to PR]. Bitte schau drüber und sign off, wenn's für dich passt."

The user then either merges, requests changes, or asks for Phase 6 escalation on specific items.

---

## 12 · If you get stuck

- **First:** re-read this handover. Most "I'm stuck" answers are here.
- **Second:** re-read `100-percent-verification-plan.md` §4 Risk inventory — your situation may be a known risk with a documented mitigation.
- **Third:** ask the user. They are the project lead. They will direct.

**Do not:**
- Silently invent axioms not in the README.
- Mark a property "verified" without a working Apalache certificate.
- Modify the spec in `zk-coins/docs` without filing a docs PR.
- Force-push or rewrite history.
- Push direct to develop.

---

## 13 · One last thing

The user has been transparent that they want **honest** verification, not happy verification. A property that fails Apalache and exposes a real spec defect is **the desired outcome** — that's why we are doing this. Manual Pass-3 was already HIGH-confidence on every property; if Apalache reproduces that, fine, but if Apalache finds something Pass-3 missed, you have done your job.

The job is not to make the spec look good. The job is to know whether it is.

— Outgoing session, 2026-06-06
