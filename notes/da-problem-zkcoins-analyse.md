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

Das DA-Problem ist für zkCoins v1 **real und kein Randthema**. Das Shielded-CSV-Paper schreibt jeden Nullifier (64 B, selbst-authentifizierend via Half-Aggregated-Signatur) auf Bitcoin — dadurch ist die komplette Double-Spend-Datenbasis chain-garantiert verfügbar. zkCoins v1 ersetzt das durch eine konstante 231-B-Inscription plus off-chain `BatchBundle` (`k=3`-Replikation). Damit hängt die Verifizierbarkeit jedes Batches an Off-chain-Verfügbarkeit.

Dabei müssen zwei Sicherheitsbegriffe getrennt werden:

- **Custody safety:** DA-Verlust verrät keinen Spend-Key und erlaubt niemandem, einen fremden Coin kryptographisch zu signieren.
- **Ledger safety:** partielle DA kann ehrliche Nodes zu unterschiedlichen Nullifier-Wurzeln führen. Dann kann derselbe Coin in zwei Sichten als unterschiedlich ausgegeben/unspent gelten und Empfänger können wirtschaftlich doppelt gutschreiben.

„DA ist nur Liveness, nie Safety" ist deshalb nur für den engen Custody-Begriff korrekt, nicht für die Konsistenz des zkCoins-Ledgers.

## Drei Szenarien

### 1. Akzidenteller Bundle-Verlust

Spec §4.6/§4.8 (`store everything`, `k=3`) reduziert die Wahrscheinlichkeit, beseitigt sie aber nicht. Universeller Verlust erfordert den Ausfall oder die Nichtkooperation aller verbleibenden Halter. Das Langzeitproblem ist ökonomisch: Niemand wird dafür bezahlt, fremde, monoton wachsende Batch-Daten dauerhaft zu speichern und zu servieren.

### 2. Publish-and-Withhold — billige State-Machine-Ambiguität

§3.6 Step 5 lässt eine syntaktisch gültige Inscription mit aktuellem `prev_root`, aber unerreichbarem Bundle in `pending`. Was danach mit einer späteren Inscription auf demselben `prev_root` geschieht, ist nicht vollständig spezifiziert:

- **Nicht-blockierende Auslegung:** Da das erste Bundle nicht verifiziert und der Root nicht angewendet wurde, bleibt der `current admitted root` bei `r0`; eine spätere verfügbare Inscription `r0 → r2` kann Step 4 passieren. Beim späteren Retry muss die ältere Inscription neu gegen den inzwischen aktuellen Root geprüft und stale/failed werden. Diese Rewind-/Retry-Semantik steht nicht normativ in der Spec.
- **Blockierende Auslegung:** Der Scanner wartet aus kanonischer Ordnungsstrenge auf die frühere Inscription. Dann kann ein Locator auf ein nie existierendes Bundle das Anchoring für ungefähr die Kosten eines Commit/Reveal-Paars einfrieren.

Ein garantierter netzweiter Freeze ist aus dem aktuellen Text daher **nicht bewiesen**. Bewiesen ist eine kritische, billig triggerbare Ambiguität: konforme Implementierungen können sich bei Retry, Supersession und später Bundle-Verfügbarkeit unterschiedlich verhalten. Die Spec muss festlegen, ob nachfolgende Kandidaten verarbeitet werden, wann ein DA-pending Kandidat terminal wird und ob ab diesem Punkt deterministisch replayt wird.

### 3. Selective Serving — Root-Split mit Double-Credit-Potenzial

Ein Publisher mit einem gültigen Batch serviert das Bundle nur einem Teil des Netzes. Teil A admittiert `r0 → r1`; Teil B bleibt bei `r0` und kann später `r0 → r2` admittieren. A verwirft `r0 → r2` als stale, B akzeptiert es. Beide Entscheidungen folgen ihrer lokalen §3.6-Sicht.

Solange das erste Bundle B vorenthalten wird — oder solange die Spec keinen deterministischen historischen Replay bei später Verfügbarkeit verlangt — bleiben die Ansichten gespalten. Ein in Sicht A nullifizierter Coin kann in Sicht B weiter als unspent gelten. Ein Angreifer, der seine eigenen Coins und einen Publisher kontrolliert, kann damit zwei individuell gültige, aber widersprüchliche Ausgaben platzieren und Empfänger in verschiedenen Sichten zu **Cross-View-Double-Credit** bewegen. Das ist kein Diebstahl fremder Schlüssel, aber ein Ledger-Safety- und wirtschaftlicher Verlustfall.

## Warum einfache Fixes nicht reichen

- Ein lokaler oder wall-clock-basierter **Timeout** macht unterschiedliche Beobachtungen nicht objektiv: Nodes mit Bundle admittieren, Nodes ohne Bundle timeouten.
- Ein explizites on-chain **`member_root`** verbessert die Bindung, beweist aber weder Bundle-Verfügbarkeit noch die Gültigkeit von `prev_root → new_root`.
- `k=3` und ACKs sind operative Wahrscheinlichkeitsmaßnahmen. Ein bösartiger Publisher kann die vorgeschriebene Replikation behaupten/umgehen; Bitcoin erzwingt sie nicht.

Eine echte Live-DA-Lösung braucht eine **für alle Nodes objektiv identische Admission-Regel**. Mögliche Richtungen sind: ausreichend Validitäts-/Nullifier-Daten auf Bitcoin, eine explizite externe DA-Annahme mit prüfbarem Zertifikat und klarer Trust-Grenze oder ein Protokoll-Redesign, das eine nicht verfügbare Transition nicht zum globalen Sequenzpunkt macht. Ein Timeout oder Hash-Commitment allein genügt nicht.

## Zwei Achsen

- **Live-Progress/Ledger-Safety:** Verfügbarkeit des aktuellen Bundles, deterministische Admission, Selective Serving und spätes Replay. Muss vor einem trustless Checkpoint-Protokoll gelöst werden.
- **Retention/Fresh-Sync:** ewige Aufbewahrung und Genesis-Replay historischer Bundles. Rekursive Checkpoints können Proof-Verifikation und gespeicherte Daten stark komprimieren, verschieben die DA-Pflicht aber auf Snapshots, Checkpoint-Proofs, MMR-Indizes und coin-spezifische Anchoring-Witnesses.

Das überarbeitete Konzept in [`../zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md`](../zkcoins-design/RECURSIVE_ACCUMULATOR_CHECKPOINT.md) behandelt Checkpoints deshalb als **historische Kompression mit expliziten Voraussetzungen**, nicht als bereits vollständige Entfernung von `R-D7-3`/`P17`.
