# Matrix AI OS 🛡️⚡

> **A 100% Privacy-First, Local-First Personal AI Operating System built with Flutter.**

Matrix AI OS is designed from first principles with zero trust toward external clouds. All personal signals, interaction logs, notes, financial transactions, screen-time metrics, and visual memories are ingested, processed, indexed, and stored **locally on the physical device** under military-grade authenticated encryption.

---

## 🌟 Core Architectural Pillars

### 1. 🔒 Zero Data Leakage Guarantee
- **Hardware-Backed Keystore:** A cryptographically secure 256-bit master key is generated via `Random.secure()` on first boot and isolated inside the Android Keystore (`flutter_secure_storage`).
- **AES-256-GCM Authenticated Encryption:** Every atomic payload stored in local storage is encrypted using AES-GCM with a dynamic 96-bit nonce and 128-bit MAC tag. Even if an attacker extracts the raw database file (`.mdb`), the disk contents are completely unreadable Base64 ciphertext.

### 2. 🪶 Ultra-Lightweight & Low-Storage Target (<30MB APK)
- **Zero Heavy ML Bundling:** Heavy foundation models and bulky assets are not bundled into the binary.
- **R8 / ProGuard Optimization:** Full code stripping, resource shrinking, and dead code elimination are enforced in release builds (`isMinifyEnabled = true`, `isShrinkResources = true`).
- **Zero Asset Duplication:** Visual and gallery documents are indexed by reference URI (`fileUri`), preventing image duplicates in the database.

### 3. ⚡ Local High-Speed NoSQL Core (ObjectBox)
- Sub-millisecond ACID transactions and indexed queries using ObjectBox NoSQL.
- Native C-engine performance without the SQLite overhead.

### 4. 🧹 Rolling 30-Day Retention & Auto-Pruning
- Automatic database compaction to prevent storage creep on resource-constrained devices.
- Raw atomic memory logs older than 30 days are automatically summarized, aggregated into `DailySummary` entities, and purged from raw storage.
- **Immunity Rules:** Permanent knowledge documents (`ocr_doc`) and user-pinned memories (`isPinned == true`) are exempted from auto-pruning.

---

## 🏗️ Clean Modular Feature-First Architecture

```
lib/
├── core/
│   ├── constants/             # App constants, categories, storage budgets
│   ├── database/              # LocalDatabaseService, ObjectBox Store, Riverpod DI
│   │   ├── models/            # MemoryNode & DailySummary @Entity definitions
│   │   └── storage_pruner_service.dart # 30-day rolling compaction & retention service
│   ├── security/              # EncryptionKeyManager & AES-256-GCM CipherService
│   └── utils/                 # Formatters (byte conversions, ISO day strings)
├── features/
│   ├── ai_brain/              # PII Masking, On-Device RAG & LLM/SLM Routing
│   ├── assistant_ui/          # Dark-mode dashboard, chat UI & live cipher inspector
│   ├── device_ingestion/      # UsageStats, CallLogs, Notifications ingestion
│   └── ocr_vision/            # On-Device ML Kit OCR & gallery knowledge indexing
├── main.dart                  # Application bootstrap with ProviderScope
├── objectbox-model.json       # ObjectBox schema tracking
└── objectbox.g.dart           # Generated entity bindings
```

---

## 📊 Database Models

### `MemoryNode` (Atomic Encrypted Logs)
| Property | Type | Description |
| :--- | :--- | :--- |
| `id` | `int` | Primary key (auto-increment) |
| `category` | `String` (Indexed) | `transaction`, `screen_time`, `call_log`, `ocr_doc`, `note` |
| `content` | `String` | AES-256-GCM ciphertext |
| `metadataJson` | `String` | AES-256-GCM ciphertext |
| `timestamp` | `DateTime` (Indexed) | Event capture time |
| `fileUri` | `String?` | Optional local file path (avoids duplicate media storage) |
| `isPinned` | `bool` | Exemption flag from auto-pruner |

### `DailySummary` (Compacted Historical Knowledge)
| Property | Type | Description |
| :--- | :--- | :--- |
| `id` | `int` | Primary key (auto-increment) |
| `date` | `String` (Unique, Indexed) | ISO day string (`yyyy-MM-dd`) |
| `summaryText` | `String` | Condensed narrative of daily events |
| `totalScreenTimeMinutes` | `int` | Aggregated daily screen time |
| `totalSpent` | `double` | Aggregated daily financial spend |
| `createdAt` | `DateTime` (Indexed) | Aggregation timestamp |

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.24+ recommended, tested on 3.41+)
- Android SDK (minSdk: 24, targetSdk: 34)
- Java 17+

### Installation & Code Generation

1. Clone repository:
   ```bash
   git clone https://github.com/afthah-commits/matrix-ai-os.git
   cd matrix-ai-os
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate ObjectBox entity bindings:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. Run tests:
   ```bash
   flutter test
   ```

5. Verify static code analysis:
   ```bash
   flutter analyze
   ```

---

## 🧪 Verification & Security Audit UI

Matrix AI OS ships with an interactive on-device verification screen:
- **Live Hardware Keystore Status:** Confirms active AES-256-GCM key state.
- **Storage Budget Tracker:** Live DB size monitoring vs. the `<30MB` constraint.
- **Cipher Inspection Panel:** Demonstrates raw ciphertext stored on disk vs. decrypted runtime output to verify zero unencrypted data leakage.
- **Pruner Simulator:** Injects synthetic historical logs and runs the 30-day compaction engine on-demand.

---

## 🗺️ Roadmap
- [x] **Phase 1 (Ticket 1.1):** Clean Architecture, Hardware-Backed Keystore, Encrypted ObjectBox NoSQL, Rolling 30-day Storage Pruner, Verification Dashboard.
- [ ] **Phase 1 (Ticket 1.2):** Android UsageStatsManager & Notification Listener Background Services.
- [ ] **Phase 2:** On-Device ML Kit OCR gallery indexing & semantic embedding pipeline.
- [ ] **Phase 3:** Local AI Brain — On-device PII masking filter, offline RAG vector index, Edge/Local LLM router.
- [ ] **Phase 4:** Assistant UI — Multimodal chat interface, voice synthesis, proactive daily briefing cards.

---

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
