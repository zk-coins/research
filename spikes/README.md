# Spikes

Throwaway research crates kept for the record — feasibility experiments, not production code.

| Spike | Origin | Outcome |
|---|---|---|
| [`plonky3-recursion-spike/`](plonky3-recursion-spike/) | `spikes/plonky3-recursion-spike/` on the `staging` branch of [`zk-coins/node`](https://github.com/zk-coins/node) (PRs [#212](https://github.com/zk-coins/node/pull/212), [#214](https://github.com/zk-coins/node/pull/214)) | Phase-0 Plonky3 recursion feasibility — gate is **GO** via carrier tables. See [`../zkcoins-design/plonky3-migration/`](../zkcoins-design/plonky3-migration/) for the write-ups and [`../benchmarks/`](../benchmarks/) for the numbers. |

Archived here on **2026-06-07**. The crate is its own Cargo workspace (it was `exclude`d from
the node workspace because of heavy git-pinned Plonky3 dependencies), so it builds standalone
from its own directory and is independent of the node build.
