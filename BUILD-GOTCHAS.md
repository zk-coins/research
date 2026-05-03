# Build Gotchas

Known issues and their solutions. Collected during initial development (April-May 2026).

## Docusaurus + Node 22: webpack Pin

**Problem:** Docusaurus 3.9 + Node 22 → `ProgressPlugin` error (`name` and `color` options removed in webpack 5.98+).

**Solution:** Pin webpack in `package.json`:
```json
"overrides": {
  "webpack": "5.97.1"
}
```

Do not remove this override until Docusaurus fixes the compatibility issue.

## WASM Build: secp256k1 Requires LLVM with wasm32

**Problem:** `wasm-pack build` fails with `No available targets are compatible with triple "wasm32-unknown-unknown"` — Apple's system clang doesn't support wasm32.

**Solution:** Use Homebrew LLVM:
```bash
CC="/opt/homebrew/opt/llvm/bin/clang" AR="/opt/homebrew/opt/llvm/bin/llvm-ar" \
  cargo build --target wasm32-unknown-unknown --release
```

## WASM Build: wasm-bindgen Version Must Match

**Problem:** `wasm-bindgen-cli` version must match the `wasm-bindgen` dependency in Cargo.toml. Also, latest wasm-bindgen-cli requires Rust 1.85+ (edition 2024), but the project pins Rust 1.81.

**Solution:** Pin `wasm-bindgen = "=0.2.95"` in client/Cargo.toml, install matching CLI:
```bash
cargo +stable install wasm-bindgen-cli@0.2.95
```

## Docker: SP1 Toolchain Not Available

**Problem:** The `script/` crate (prover) uses `sp1-build` which requires the `succinct` Rust toolchain. This toolchain is not available in Docker.

**Solution:** A stub prover (`script/src/lib.rs`) provides the same API surface with mock proofs. No SP1 dependencies, no succinct toolchain needed. The `program/` crate makes SP1 optional via a `zkvm` feature flag:
```toml
[features]
default = []
zkvm = ["sp1-zkvm"]
```

## Docker: minting_secret.bin Required at Compile Time

**Problem:** The server uses `include_bytes!("../minting_secret.bin")` — the file must exist at compile time.

**Solution:** A placeholder file is committed to the repo (`server/minting_secret.bin`, 32 random bytes). For production, replace with a real key.

## Docker: Server Must Bind 0.0.0.0

**Problem:** Server binds to `127.0.0.1:4242` by default — unreachable from outside the Docker container.

**Solution:** Changed to `0.0.0.0:4242` in `server/src/main.rs`:
```rust
const ACCOUNT_SERVER_ADDR: &str = "0.0.0.0:4242";
```

## Docker: Next.js Runtime Environment Variables

**Problem:** Next.js bakes `NEXT_PUBLIC_*` values at build time. Same image for DEV/PRD needs different values.

**Solution:** Build with placeholder values, replace at container start:

Dockerfile:
```dockerfile
ENV NEXT_PUBLIC_API_URL=NEXT_PUBLIC_API_URL_PLACEHOLDER
```

entrypoint.sh:
```bash
find /app/.next -name '*.js' -exec sed -i'' \
  -e "s|NEXT_PUBLIC_API_URL_PLACEHOLDER|${NEXT_PUBLIC_API_URL}|g" \
  {} +
```

**Critical:** The placeholder must be a simple string without special characters. Using the actual env var name (e.g. `NEXT_PUBLIC_API_URL`) as placeholder causes sed to corrupt JS files because the replacement value contains colons and slashes from URLs.

## Docker: Alpine Has No wget

**Problem:** Docker Compose health checks using `wget` fail in `node:20-alpine` images — Alpine doesn't include wget.

**Solution:** Install `curl` in Dockerfile:
```dockerfile
RUN apk add --no-cache curl
```

Health check: `curl -f http://localhost:3090/`

## MDX: Curly Braces and @ Signs

**Problem:** Docusaurus uses MDX which interprets `{` as JSX expressions and `@` in certain contexts as JSX member expressions.

**Solution:** For research content with code snippets: store as `.txt` files in `static/` directory (not processed by MDX). Or escape braces with `&#123;` / `&#125;`.
