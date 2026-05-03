# zkCoins Research

Research, upstream references, protocol analysis, and primary sources for the [Shielded CSV](https://eprint.iacr.org/2025/068) protocol that [zkCoins](https://zkcoins.app) is built on.

## Contents

```
research/
├── shieldedcsv-paper.pdf          # The paper (ePrint 2025/068, 914 KB)
├── primary-sources/               # Archived full-text articles
│   ├── blockstream-blog.md        # "Bitcoin's Shielded CSV Protocol Explained" (Dec 2024)
│   ├── mailing-list.md            # Bitcoin-Dev thread: Nick, Riard, Chen (Sep 2024)
│   ├── eliel-blog.md              # "My Thoughts on the Shielded CSV Protocol" (Apr 2025)
│   ├── bitcoin-optech.md          # Bitcoin Optech: Client-Side Validation
│   └── da-paper.md                # ePrint 2025/569: Data Availability in CSV
└── upstream/                      # Git submodules of original repositories
    ├── ShieldedCSV/               # Paper reference code (Rust, MIT)
    ├── ZeroSync-ZKCoins/          # Functional prototype (our primary upstream)
    ├── rust-bitcoincore-rpc/      # Bitcoin Core RPC fork for ZKCoins
    └── BitVM-zkCoins/             # Historical Plonky2 experiments
```

## The Paper

**Shielded CSV: Private and Efficient Client-Side Validation**

- Authors: Jonas Nick (Blockstream), Liam Eagen (Alpen Labs), Robin Linus (ZeroSync)
- Published: January 2025
- ePrint: [2025/068](https://eprint.iacr.org/2025/068)
- Local copy: [shieldedcsv-paper.pdf](shieldedcsv-paper.pdf)

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
| [zk-coins/server](https://github.com/zk-coins/server) | Rust backend (api.zkcoins.app) |
| [zk-coins/docs](https://github.com/zk-coins/docs) | Documentation (docs.zkcoins.app) |

## License

MIT
