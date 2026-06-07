# Benchmarks (archived from `zk-coins/node`)

Benchmark write-ups produced during the **Plonky3 recursion spike** (PR
[#214](https://github.com/zk-coins/node/pull/214)). They previously lived under
`scripts/bench/results/` on the `staging` branch of
[`zk-coins/node`](https://github.com/zk-coins/node) and were moved here on **2026-06-07**
so the node repo carries no Plonky3-migration research artifacts. Archived **verbatim**.

| File | What it measures |
|---|---|
| `plonky3-spike-m5-max-2026-06-06.md` | Headline Plonky3 recursion-spike numbers (M5 Max) |
| `plonky3-recursion-reduction-m5-max-2026-06-06.md` | Recursion-depth / proof-count reduction results |
| `plonky3-probe-t-real-circuit-m5-max-2026-06-06.md` | Probe T — real-circuit benchmark |
| `plonky3-probe-u-e2e-projection-m5-max-2026-06-06.md` | Probe U — end-to-end cost projection |
| `plonky3-vs-plonky2-fair-m5-max-2026-06-06.md` | Fair Plonky3-vs-Plonky2 comparison |

The spike crate that produced these numbers is archived at
[`../spikes/plonky3-recursion-spike/`](../spikes/plonky3-recursion-spike/). The
hardware-comparison benchmark data that is part of the node's own benchmarking
infrastructure (`scripts/bench/results/*.csv|*.json`, `m5-max-vs-m3-ultra-*.md`) stays in
the node repo and was **not** moved.
