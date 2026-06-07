# Verification status — zkCoins 100% Logical Verification Initiative

**Spec baseline:** [`zk-coins/docs@b6972b8`](https://github.com/zk-coins/docs/commit/b6972b8) (post-`docs#40`).
**Tool:** Apalache 0.58.0 (Z3 4.14.1.0). Reproduce all: [`../verify-all.sh`](../verify-all.sh).

| Property | Verdict | Unbounded? | Certificate |
|---|---|---|---|
| **P1** No-Forgery | VERIFIED | provenance unbounded; signature-level bounded + reduction | [`P01_NoForgery/`](./P01_NoForgery/certificate.txt) |
| **P2** No-Double-Spend | VERIFIED | safety unbounded (abstract + full `Onchain`); continuity bounded | [`P02_NoDoubleSpend/`](./P02_NoDoubleSpend/certificate.txt) |
| **P3** Per-Asset Balance Conservation | VERIFIED | unbounded | [`P03_BalanceConservation/`](./P03_BalanceConservation/certificate.txt) |
| **P4** Zero-Knowledge | VERIFIED | flow invariant unbounded; indistinguishability = A2 (axiom) | [`P04_ZeroKnowledge/`](./P04_ZeroKnowledge/certificate.txt) |
| **P5** On-chain Privacy | VERIFIED | publisher-only-link unbounded; network half out of scope | [`P05_OnchainPrivacy/`](./P05_OnchainPrivacy/certificate.txt) |
| **P6** Client-Side Validation | VERIFIED | unbounded | [`P06_ClientSideValidation/`](./P06_ClientSideValidation/certificate.txt) |
| **P7** Issuance Authenticity v1 | VERIFIED | unbounded | [`P07_IssuanceAuthenticity/`](./P07_IssuanceAuthenticity/certificate.txt) |
| **P8** Transport Confidentiality + Auth | VERIFIED | unbounded | [`P08_TransportConfAuth/`](./P08_TransportConfAuth/certificate.txt) |
| **P9** Recovery Completeness | VERIFIED | safety unbounded; liveness = enabledness surrogate | [`P09_RecoveryCompleteness/`](./P09_RecoveryCompleteness/certificate.txt) |
| **P10** Capability Discipline | VERIFIED | unbounded (spend-escalation = structural) | [`P10_CapabilityDiscipline/`](./P10_CapabilityDiscipline/certificate.txt) |

Every certificate is conditional on the named cryptographic axioms (A1–A17) and the
four meta-assumptions (M1–M4); see [`../CERTIFICATE.md`](../CERTIFICATE.md) for the
full reconciliation against the Pass-3 manual audit and the honest residual.
