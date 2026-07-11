---
type: analysis
status: active
area: neben
tags: [crypto, bitcoin, privacy, data-availability, zkcoins, sicherheit]
updated: 2026-07-11
---

# Data-Availability-Problem in zkCoins v1 — Analyse

Zurück zu [[da-paper|ePrint 2025/569]] · Auslöser: Kritik der Paper-Autoren an der Landing-Page-Formulierung „goes further … beyond the paper" (Fix: landing-page PR #31)

---

## Kernbefund

Das DA-Problem ist für zkCoins v1 **real und kein Randthema**. Das Shielded-CSV-Paper schreibt jeden Nullifier (64 B, selbst-authentifizierend via Half-Aggregated-Signatur) auf Bitcoin — dadurch ist die komplette Double-Spend-Datenbasis chain-garantiert verfügbar. zkCoins v1 ersetzt das durch eine konstante 231-B-Inscription plus off-chain `BatchBundle` (k=3-Replikation). Damit hängt die Verifizierbarkeit jedes Batches an Off-chain-Verfügbarkeit — mit drei Eskalationsstufen:

## Drei Szenarien

### 1. Akzidenteller Bundle-Verlust (dokumentiert, operativ beherrschbar)
Spec §4.6/§4.8 (store-everything, k=3) + risks.md decken das ab. Universeller Verlust erfordert Simultanausfall aller ehrlichen Scanner. Restrisiko: Retention-Free-Rider (nichts bezahlt Scanner für fremde Bundles). Einstufung: echt, aber unwahrscheinlich.

### 2. Publish-and-Withhold — Liveness-DoS (NICHT adressiert, billig)
§3.6 Step 5 (Bundle-Fetch) liegt **vor** den Verifikationssteps 6–7, und nur Steps 2–4/6/7 können zu `failed` führen. Eine Inscription mit gültiger Struktur, gültiger BIP-340-Signatur, `prev_root` = aktueller Tip und einem **Locator auf ein nie existierendes Bundle** kann daher nie `failed` werden — sie hängt ewig in `pending`. Wegen des seriellen Accumulators (§3.4 Sequential Commitment) kann kein Scanner deterministisch entscheiden, ob eine spätere Inscription auf demselben `prev_root` stale ist, solange die frühere pending ist → strikte Auslegung: **netzweiter Anchoring-Freeze**. Kosten des Angriffs: ~318 vB (wenige Dollar), kein Proving, keine Coins, beliebig wiederholbar, permissionless.

### 3. Selective Serving — Konsens-Split mit Double-Credit-Potenzial (schwerste Stufe)
Ein Publisher mit *gültigem* Batch served das Bundle nur einem Teil des Netzes. Teil A admittiert r0→r1, Teil B bleibt bei r0 und admittiert später r0→r2. Beide folgen der Spec; §3.6-Determinismus („identical state") setzt uniforme Bundle-Verfügbarkeit voraus — genau die verletzt der Angreifer. Ergebnis: permanenter Accumulator-Fork; ein nur auf Seite A nullifizierter Coin ist auf Seite B weiter ausgebbar → **Cross-View-Double-Credit** bei Empfängern der B-Seite. risks.md nennt den Fork („soft fork between nodes") nur als Randnotiz.

---

## Zwei Achsen — und was davon lösbar ist

Wichtige Trennung, die in der öffentlichen Kritik verwischt: das DA-Problem hat **zwei getrennte Achsen**, und nur eine ist mit protokoll-eigenen Mitteln entfernbar.

- **Live-Progress-Achse (Szenarien 2 + 3 oben):** Verfügbarkeit des *aktuellen* Bundles. Withhold-DoS und Selective-Serving-Fork. Braucht eigene Fixes (Fail-closed-Timeout auf unfetchbare Locator; On-chain-`member_root`-Commitment). **Nicht** durch Checkpointing gelöst.
- **Retention-/Fresh-Sync-Achse (Szenario 1 + `R-D7-3`/`P17`):** ewige, unbelohnte Aufbewahrung *aller* historischen Bundles + O(N)-Genesis-Replay für neue trustless-Verifier. Der eigentliche Langzeit-Schaden ist nicht Diebstahl, sondern **schleichende Zentralisierung des Verifier-Sets**, weil frische Full-Verification unbegrenzt teurer wird.

Die Retention-Achse ist **mit zkCoins' eigenem PCD-Werkzeugkasten lösbar**, ohne Hilfskette, Token oder Trusted Setup — Konzept ausgearbeitet in [`../zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md`](../zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md): ein rollender rekursiver Beweis der Akkumulator-Progression + selbst-verifizierender Nullifier-Snapshot lässt das Netz Pre-Checkpoint-Bundles verwerfen. Damit verschiebt sich der Concept-Review-Befund zu `R-D7-3` von „nur aufgeschoben" zu „für die Historie entfernbar, ohne DA-Layer". Der eigene Review listet „epoch checkpoints to drop pre-checkpoint bundles; accumulator snapshotting" bereits als Stichpunkt — dort ist es ausgearbeitet und mit dem bestehenden `C_batch`/Anchors-MMR-Stack verbunden.