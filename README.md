# zkCoins Research

Research, upstream references, protocol analysis, and primary sources for the [Shielded CSV](https://eprint.iacr.org/2025/068) protocol that [zkCoins](https://zkcoins.app) is built on.

## Contents

```
research/
├── shieldedcsv-paper.pdf          # The paper (ePrint 2025/068, 914 KB)
├── glock-paper.pdf                # Glock: Garbled Locks for Bitcoin (ePrint 2025/1485, Aug 2025)
├── argo-mac-paper.pdf             # Argo MAC: Garbling with Elliptic Curve MACs (ePrint 2026/049, Jan 2026)
├── bitvm-paper.pdf                # BitVM: Quasi-Turing Complete Computation (ePrint 2024/1995)
├── bitvm2-bridge-paper.pdf        # BitVM2: Bridging Bitcoin to Second Layers
├── bitvm-bridge-research.md       # Historical Glock-path note (superseded: zk-coins/zkbtc, BitVM2 + R-09)
├── primary-sources/               # Archived full-text articles
│   ├── blockstream-blog.md        # "Bitcoin's Shielded CSV Protocol Explained" (Dec 2024)
│   ├── mailing-list.md            # Bitcoin-Dev thread: Nick, Riard, Chen (Sep 2024)
│   ├── eliel-blog.md              # "My Thoughts on the Shielded CSV Protocol" (Apr 2025)
│   ├── bitcoin-optech.md          # Bitcoin Optech: Client-Side Validation
│   └── da-paper.md                # ePrint 2025/569: Data Availability in CSV
├── upstream/                      # Git submodules of original repositories
│   ├── ShieldedCSV/               # Paper reference code (Rust, MIT)
│   ├── ZeroSync-ZKCoins/          # Functional prototype (our primary upstream)
│   ├── rust-bitcoincore-rpc/      # Bitcoin Core RPC fork for ZKCoins
│   └── BitVM-zkCoins/             # Historical Plonky2 experiments
├── zkcoins-design/                # Design drafts archived from zk-coins/node (see its README)
├── benchmarks/                    # Plonky3 spike benchmark results archived from zk-coins/node
├── spikes/                        # Throwaway research crates
│   └── plonky3-recursion-spike/   # Plonky3 recursion feasibility spike (from node staging, PRs #212/#214)
├── community-content/             # Community/research pages archived from zk-coins/docs
├── operations/                    # Backend/deployment ops notes archived from zk-coins/docs
└── audit/                         # Dated internal cryptographic reviews
    └── 2026-06-06.03.md           # Pass-3 v1 spec review (snapshot; do not rewrite)
```

## Imported Working Content (2026-06-07)

This repository is the **catch-all for everything research-, design-, and ops-flavoured**
across the zkCoins project. As part of a repo-hygiene pass, design drafts, the Plonky3
recursion spike, benchmark write-ups, and community/ops documentation were moved here out
of `zk-coins/node` and `zk-coins/docs` so those repos can stay focused (node = shippable
software only; docs = the target-design specification only). Each imported directory has a
`README.md` documenting its exact provenance and where any relocated cross-references now
live. Nothing was rewritten — the files are archived verbatim.

## Protocol Status

See **[PROTOCOL_STATUS.md](PROTOCOL_STATUS.md)** for a detailed comparison of the Shielded CSV paper against our current implementation, including what's done, what's missing, and the roadmap.

## The Paper

**Shielded CSV: Private and Efficient Client-Side Validation**

- Authors: Jonas Nick (Blockstream), Liam Eagen (Alpen Labs), Robin Linus (ZeroSync)
- Published: January 2025
- ePrint: [2025/068](https://eprint.iacr.org/2025/068)
- Local copy: [shieldedcsv-paper.pdf](shieldedcsv-paper.pdf)

## Bridge Construction (zkBTC path)

**Normative zkBTC is [`zk-coins/zkbtc`](https://github.com/zk-coins/zkbtc), not this archive.** zkBTC is token standard 3 on BitVM2 with a cumulative, growth-only operator set (R-09). It is **effectively trustless**: the holder is an operator; nobody else is trusted with their bitcoin; a gatekeeper is optional and only gates new mints. The June-2026 Glock-only / "no BitVM2 intermediate" note in [bitvm-bridge-research.md](bitvm-bridge-research.md) is **historical** and superseded. Glock / BitVM3 remain possible future efficiency upgrades in that specification, not the launch path. There is no federation V0.

| Paper | Authors | Date | Local copy |
|---|---|---|---|
| **Glock: Garbled Locks for Bitcoin** | Liam Eagen (Alpen Labs) | Aug 2025 | [glock-paper.pdf](glock-paper.pdf) · [ePrint 2025/1485](https://eprint.iacr.org/2025/1485) |
| **Argo MAC: Garbling with Elliptic Curve MACs** | Liam Eagen, Ying Tong Lai | Jan 2026 | [argo-mac-paper.pdf](argo-mac-paper.pdf) · [ePrint 2026/049](https://eprint.iacr.org/2026/049) |
| **BitVM2: Bridging Bitcoin to Second Layers** | BitVM team | 2024 | [bitvm2-bridge-paper.pdf](bitvm2-bridge-paper.pdf) · [bitvm.org/bitvm_bridge.pdf](https://bitvm.org/bitvm_bridge.pdf) |
| **BitVM: Quasi-Turing Complete Computation** | Lukas Aumayr et al. | 2024 | [bitvm-paper.pdf](bitvm-paper.pdf) · [ePrint 2024/1995](https://eprint.iacr.org/2024/1995) |

Glock and Argo are kept side by side because Robin Linus co-authored Argo and the two constructions are sister directions in the same research line; Glock is the closer-to-mainnet path. BitVM and BitVM2 are kept as the comparison baseline even though we are not building on them.

## Upstream Repositories

| Directory | Source | Description |
|---|---|---|
| `upstream/ShieldedCSV/` | [ShieldedCSV/ShieldedCSV](https://github.com/ShieldedCSV/ShieldedCSV) | Paper reference code. PCD Compliance Predicate in Rust — the protocol specification in code form. All crypto primitives are `unimplemented!()`. 44 stars, MIT. |
| `upstream/ZeroSync-ZKCoins/` | [ZeroSync/ZKCoins](https://github.com/ZeroSync/ZKCoins) | **Our primary upstream.** Functional prototype: SP1 zkVM proofs, WASM client, Axum server, Taproot Inscriptions. Our server/shared/program crates are derived from this. |
| `upstream/rust-bitcoincore-rpc/` | [ZeroSync/rust-bitcoincore-rpc](https://github.com/ZeroSync/rust-bitcoincore-rpc) | Fork with `submitpackage` RPC for Bitcoin Core integration. |
| `upstream/BitVM-zkCoins/` | [BitVM/zkCoins](https://github.com/BitVM/zkCoins) | Historical Plonky2 recursive circuit experiments. Predecessor to ZeroSync. Last commit: "Recursive proving kinda works" (Feb 2024). |

## Primary Sources (Archived)

Full-text copies of key articles, archived locally for reference:

| File | Source | Date |
|---|---|---|
| [blockstream-blog.md](primary-sources/blockstream-blog.md) | [Blockstream Blog](https://blog.blockstream.com/bitcoins-shielded-csv-protocol-explained/) | Dec 2024 |
| [mailing-list.md](primary-sources/mailing-list.md) | [Bitcoin-Dev Mailing List](https://gnusha.org/pi/bitcoindev/b0afc5f2-4dcc-469d-b952-03eeac6e7d1b@gmail.com/) | Sep 2024 |
| [eliel-blog.md](primary-sources/eliel-blog.md) | [Eliel Blog](https://eliel.nfinic.com/2025/04/07/my-thoughts-on-the-shielded-csv-protocol/) | Apr 2025 |
| [bitcoin-optech.md](primary-sources/bitcoin-optech.md) | [Bitcoin Optech](https://bitcoinops.org/en/topics/client-side-validation/) | Ongoing |
| [da-paper.md](primary-sources/da-paper.md) | [ePrint 2025/569](https://eprint.iacr.org/2025/569) | Mar 2025 |

## Key External Links

| Resource | URL |
|---|---|
| Shielded CSV paper | [eprint.iacr.org/2025/068](https://eprint.iacr.org/2025/068) |
| shieldedcsv.org | [shieldedcsv.org](https://shieldedcsv.org) |
| zkCoins original gist | [gist.github.com/RobinLinus](https://gist.github.com/RobinLinus/d036511015caea5a28514259a1bab119) |
| DA paper (2025/569) | [eprint.iacr.org/2025/569](https://eprint.iacr.org/2025/569) |
| Jonas Nick announcement | [x.com/n1ckler](https://x.com/n1ckler/status/1837194004552655077) |
| Bitcoin Takeover Podcast S15 E58 | [podtail.com](https://podtail.com/en/podcast/bitcoin-takeover-podcast/s15-e58-liam-eagen-robin-linus-jonas-nick-on-shiel/) |
| Blockstream YouTube | [youtube.com](https://www.youtube.com/watch?v=aZa2zXp1Q2A) |
| Robin Linus "Make Bitcoin Cypherpunk Again" | [youtube.com](https://www.youtube.com/watch?v=XIZ3bTZ4VpE) |
| TABConf 6 Slides | [slides.com](https://slides.com/iamjon/deck-d58045) |
| Stacker News AMA (Robin Linus) | [stacker.news](https://stacker.news/items/316211) |

## Cloning with Submodules

```bash
git clone --recurse-submodules https://github.com/zk-coins/research.git

# Or if already cloned:
git submodule update --init --recursive
```

## Related Repos

| Repo | Purpose |
|---|---|
| [zk-coins/app](https://github.com/zk-coins/app) | Web application (zkcoins.app) |
| [zk-coins/node](https://github.com/zk-coins/node) | Rust backend / node (api.zkcoins.app) |
| [zk-coins/docs](https://github.com/zk-coins/docs) | Documentation (docs.zkcoins.com) |

## License

MIT
