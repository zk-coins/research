# Benchmarks (archived from `zk-coins/node`)

Benchmark artifacts moved out of the node repo so it carries no benchmark output.
Two sets:

## Plonky3 recursion spike

Write-ups produced during the **Plonky3 recursion spike** (PRs
[#212](https://github.com/zk-coins/node/pull/212) and
[#214](https://github.com/zk-coins/node/pull/214): `plonky3-spike-*.md` landed in #212, the
other four in #214). They previously lived under `scripts/bench/results/` on the `staging`
branch of [`zk-coins/node`](https://github.com/zk-coins/node) and were moved here on
**2026-06-07**. Archived **verbatim**.

| File | What it measures |
|---|---|
| `plonky3-spike-m5-max-2026-06-06.md` | Headline Plonky3 recursion-spike numbers (M5 Max) |
| `plonky3-recursion-reduction-m5-max-2026-06-06.md` | Recursion-depth / proof-count reduction results |
| `plonky3-probe-t-real-circuit-m5-max-2026-06-06.md` | Probe T — real-circuit benchmark |
| `plonky3-probe-u-e2e-projection-m5-max-2026-06-06.md` | Probe U — end-to-end cost projection |
| `plonky3-vs-plonky2-fair-m5-max-2026-06-06.md` | Fair Plonky3-vs-Plonky2 comparison |

The spike crate that produced these numbers is archived at
[`../spikes/plonky3-recursion-spike/`](../spikes/plonky3-recursion-spike/).

## Node runtime / hardware (`node-runtime/`)

The node's MVP runtime/hardware benchmark output: warm/cold prove times and `/api/*`
HTTP round-trips, M3 Ultra vs M5 Max. Previously under `scripts/bench/results/` on
`develop`; moved here on **2026-06-07** (re-audit) so the node repo keeps only code/build/
standard files. The bench **harness** stays in the node repo (`node/src/bin/probe_r2.rs`);
only the **output** moved. Archived **verbatim**.

| File | What it measures |
|---|---|
| [`node-runtime/README.md`](node-runtime/README.md) | Wall-time per proof type per hardware target (the write-up) |
| `node-runtime/m5-max-vs-m3-ultra-2026-06-02.md` | M3 Ultra vs M5 Max comparison |
| `node-runtime/m5-max-2026-06-02-http-mint-sweep.csv` | Raw `/api/mint` HTTP sweep data (M5 Max) |
| `node-runtime/m5-max-2026-06-02-probe_r2.json` | Raw synthetic `probe_r2` data (M5 Max) |
