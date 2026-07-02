# Contributing to zkCoins Research

This repo is the **catch-all for everything research-, design-, and
ops-flavoured** across the zkCoins project: papers, primary sources, protocol
analysis, design drafts, benchmark write-ups, throwaway spikes, and upstream
reference repos. Shippable software lives in
[zk-coins/node](https://github.com/zk-coins/node) /
[zk-coins/sdk](https://github.com/zk-coins/sdk) /
[zk-coins/app](https://github.com/zk-coins/app); the target-design
specification lives in [zk-coins/docs](https://github.com/zk-coins/docs).

## What belongs where

| Material | Location |
|---|---|
| Paper PDFs (ePrint etc.) | repo root, `<topic>-paper.pdf`, referenced from `README.md` |
| Archived full-text articles / threads | `primary-sources/` |
| Original upstream repos | `upstream/` as **git submodules** (see `.gitmodules`) |
| Design drafts | `zkcoins-design/` |
| Benchmark results | `benchmarks/` |
| Throwaway research crates / experiments | `spikes/` |
| Community & research pages | `community-content/` |
| Backend/deployment ops notes | `operations/` |
| Formal analysis | `formal/` |
| Working notes | `notes/` |

## How to add material

1. Put it in the matching directory above; create a new top-level directory
   only if nothing fits.
2. Give each imported directory a short `README.md` stating its **provenance**
   (where it came from, when, and why) — archived material is kept verbatim,
   not rewritten.
3. Reference new papers and analyses from the root `README.md` contents tree.
4. Add upstream code as a submodule under `upstream/`, never as a copy.
5. Commit directly to `develop` (this repo is not branch-protected). Commit
   messages: English, concise, *what* not *how*.

## Branches & releases

- `develop` is the working branch — commit to it directly (see rule 5 above).
- `main` is the released, stable snapshot.
- On every push to `develop`, an auto-release-PR workflow opens a
  `Release: develop -> main` PR (unless one is already open). A maintainer
  merges it to cut a release.

## Related Repos

- [zk-coins/node](https://github.com/zk-coins/node) — Rust backend.
- [zk-coins/docs](https://github.com/zk-coins/docs) — specification ([docs.zkcoins.app](https://docs.zkcoins.app)).
