# zkCoins Design Drafts (archived from `zk-coins/node`)

These are protocol/design drafts that previously lived at the root of
[`zk-coins/node`](https://github.com/zk-coins/node). They are **design research**, not
shippable software, so they were moved here on **2026-06-07** to keep the node repo limited
to code, build, and standard project files. Files are archived **verbatim** — no content
was rewritten.

## What's here

| File / dir | Origin (in `zk-coins/node`) | Scope |
|---|---|---|
| `ARKADE_INTEGRATION.md` | `ARKADE_INTEGRATION.md` (develop) | Arkade integration design draft |
| `BITVM_BRIDGE.md` | `BITVM_BRIDGE.md` (develop) | BTC↔zkCoins trustless bridge landscape (BitVM2 / Glock / Mosaic) |
| `BRIDGE_MVP.md` | `BRIDGE_MVP.md` (develop) | Engineering spec for the bridge MVP |
| `LIGHTNING_ATOMIC_SWAP.md` | `LIGHTNING_ATOMIC_SWAP.md` (develop) | Trustless LN↔zkCoins atomic-swap design |
| `MIGRATION_RESEARCH.md` | `MIGRATION_RESEARCH.md` (develop) | SP1→Plonky2 (and onward) migration analysis |
| `MULTI_ASSET.md` | `MULTI_ASSET.md` (develop) | Multi-asset extension design |
| `ALIASING.md` | `zk-coins/docs` (`docs/architecture/aliasing.md`, moved 2026-06-21) | Superseded v0.2 `name@host` aliasing/addressing UX proposal. The normative model is the LNURL design in the public protocol spec §4.3. |
| `SPEC.md` | `SPEC.md` (develop) | zkCoins **circuit / single-asset** spec — the implementation-level spec the design drafts reference. Distinct from the public protocol spec (see below). |
| `ROADMAP.md` | `ROADMAP.md` (develop) | The node's Plonky2-migration roadmap/status tracker (the canonical implementation roadmap). |
| `program-plonky2-sessions/` | `program-plonky2/SESSION_STATE.md`, `STAGE_5D_NEXT_4_DESIGN.md`, `STEP4_REVIEW.md`, `STEP7_PREP.md` (develop) | Per-step migration session notes |
| `plonky3-migration/` | `MIGRATION_PLONKY3*.md` + `docs/migration/PLONKY3_*.md` (staging, PRs [#211](https://github.com/zk-coins/node/pull/211) / [#212](https://github.com/zk-coins/node/pull/212) / [#214](https://github.com/zk-coins/node/pull/214)) | Plonky3 migration plan, audit, cutover playbook |

> Path note: the node subdirectory `docs/migration/` was imported as
> `plonky3-migration/docs-migration/` (flattened to avoid a misleading top-level `docs/`
> here). File contents are untouched.

## Relocated cross-references

These drafts cross-reference files that did **not** move here. When you read a relative
link like `./ROADMAP.md` inside these documents, resolve it as follows:

| Reference in the drafts | Now lives at |
|---|---|
| `ROADMAP.md` | `./ROADMAP.md` (archived in this directory; the canonical implementation roadmap) |
| public protocol spec | [docs.zkcoins.com/specification](https://docs.zkcoins.com/specification) |
| `SPEC.md` (circuit/single-asset spec) | `./SPEC.md` (in this directory) |
| `CONTRIBUTING.md` | [zk-coins/node CONTRIBUTING.md](https://github.com/zk-coins/node/blob/develop/CONTRIBUTING.md) |
| `program-plonky2/src/...` | [zk-coins/node program-plonky2](https://github.com/zk-coins/node/tree/develop/program-plonky2) |

> Note: `SPEC.md` here is the node *circuit* specification (it names concrete
> `program-plonky2/src/...` files). It is **not** a byte-for-byte copy of the public
> protocol spec at `docs.zkcoins.com/specification`; the two are different documents at
> different altitudes, so both are kept.
