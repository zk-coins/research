# Papers as Typst

Typst rebuilds of the two upstream documents that anchor zkCoins.
Sources and prebuilt PDFs sit side by side; rebuild with
`typst compile`.

## Files

| Typst source | Rendered PDF | Origin |
|---|---|---|
| `shielded-csv.typ` | `shielded-csv.pdf` (~42 pp) | [ePrint 2025/068](https://eprint.iacr.org/2025/068) — Nick / Eagen / Linus, Sept 2024 — local copy at `../shieldedcsv-paper.pdf` |
| `zkcoins.typ` | `zkcoins.pdf` (~3 pp) | [Robin Linus gist](https://gist.github.com/RobinLinus/d036511015caea5a28514259a1bab119) (2023) — local copy at `../primary-sources/zkcoins-gist.md` |

The Typst rebuild of zkCoins's own protocol specification lives in
[`zk-coins/docs`](https://github.com/zk-coins/docs) under
`papers-typst/` (single-source from `docs/specification.md`); the two
files here are the typographic reference it is matched against.

## Build

```bash
typst compile shielded-csv.typ
typst compile zkcoins.typ
```

Live preview while editing:

```bash
typst watch shielded-csv.typ
```

## Scope

Faithful text reproduction. Math rendered as native Typst math (not
images), tables as `#table`, Figures 1–4 of the Shielded CSV paper as
ASCII-bordered code blocks, numbered references with inline hyperlinks.
Layout is not pixel-exact to the originals — content + structure + math
fidelity are the bar.

## Tooling

- `typst` ≥ 0.14
- Default `New Computer Modern` font (bundled with Typst on most
  platforms)
