# Verification status — zkCoins 100% Logical Verification Initiative

**Spec baseline:** [`zk-coins/docs@ed7fdece`](https://github.com/zk-coins/docs/commit/ed7fdece) (spec-v1.1 = `b6972b8` + `docs#46`/`#47`/`#48`).
**Tool:** Apalache 0.58.0 (Z3 4.14.1.0). Reproduce all: [`../verify-all.sh`](../verify-all.sh).

| Property | Verdict | Unbounded? | Certificate |
|---|---|---|---|
| **P1** No-Forgery | VERIFIED | provenance unbounded; signature-level bounded + reduction | [`P01_NoForgery/`](./P01_NoForgery/certificate.txt) |
| **P2** No-Double-Spend | VERIFIED | safety unbounded (abstract + full `Onchain`); continuity bounded; **+ spec-v1.1 member_root ORDER-binding unbounded** | [`P02_NoDoubleSpend/`](./P02_NoDoubleSpend/certificate.txt) |
| **P3** Per-Asset Balance Conservation | VERIFIED | unbounded; **+ spec-v1.1 fee-coin ATOMICITY unbounded** | [`P03_BalanceConservation/`](./P03_BalanceConservation/certificate.txt) |
| **P4** Zero-Knowledge | VERIFIED | flow invariant unbounded; indistinguishability = A2 (axiom) | [`P04_ZeroKnowledge/`](./P04_ZeroKnowledge/certificate.txt) |
| **P5** On-chain Privacy | VERIFIED | publisher-only-link unbounded; network half out of scope | [`P05_OnchainPrivacy/`](./P05_OnchainPrivacy/certificate.txt) |
| **P6** Client-Side Validation | VERIFIED | unbounded | [`P06_ClientSideValidation/`](./P06_ClientSideValidation/certificate.txt) |
| **P7** Issuance Authenticity v1 | VERIFIED | unbounded | [`P07_IssuanceAuthenticity/`](./P07_IssuanceAuthenticity/certificate.txt) |
| **P8** Transport Confidentiality + Auth | VERIFIED | unbounded; **+ spec-v1.1 ZBE anti-truncation unbounded** | [`P08_TransportConfAuth/`](./P08_TransportConfAuth/certificate.txt) |
| **P9** Recovery Completeness | VERIFIED | safety unbounded; liveness = enabledness surrogate | [`P09_RecoveryCompleteness/`](./P09_RecoveryCompleteness/certificate.txt) |
| **P10** Capability Discipline | VERIFIED | unbounded (spend-escalation = structural) | [`P10_CapabilityDiscipline/`](./P10_CapabilityDiscipline/certificate.txt) |

**spec-v1.1 (docs#47) re-verification.** Every P01–P10 verdict re-confirms against
the `ed7fdece` baseline (diff-confirm: the models abstract exactly what #47
concretized). The three genuinely new #47 guarantees are added as load-bearing,
unbounded-inductive invariants, each with a vacuity probe and a negative control:
P2 `member_root.tla` (locator binds member SET + ORDER), P3 `fee_atomicity.tla`
(§3.8 fee-coin all-or-none under one `ocr`), P8 `zbe.tla` (§4.2.1 chunk (N,i)-AAD
anti-truncation). `docs#46` is verification-neutral; `docs#48` touched no spec.

Every certificate is conditional on the named cryptographic axioms (A1–A17) and the
four meta-assumptions (M1–M4); see [`../CERTIFICATE.md`](../CERTIFICATE.md) for the
full reconciliation against the Pass-3 manual audit and the honest residual.
