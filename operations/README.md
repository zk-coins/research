# Operations Notes (archived from `zk-coins/docs`)

These pages previously lived under `docs/infrastructure/` in
[`zk-coins/docs`](https://github.com/zk-coins/docs) and rendered on the public docs site.
They document the **running system** (real backend internals, Docker/CI/CD deployment,
server topology, live URLs) — operational documentation of the current software rather than
the target-design specification, so they were moved here on **2026-06-07**. Archived
**verbatim** (Docusaurus front-matter preserved).

| File | Origin (`docs/infrastructure/...`) | Scope |
|---|---|---|
| `backend.md` | `backend.md` | Rust/Axum backend architecture as deployed (components, ports, data flow) |
| `deployment.md` | `deployment.md` | Docker/GitHub-Actions/Cloudflare deployment pipeline, environments, URLs |

For the developer-facing setup of the node itself, see the
[`zk-coins/node` README](https://github.com/zk-coins/node#readme) and its
[CONTRIBUTING.md](https://github.com/zk-coins/node/blob/develop/CONTRIBUTING.md).
