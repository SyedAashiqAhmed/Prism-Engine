# 🚀 Prism Engine - Sprint Progress Tracker

> **Repository:** https://github.com/SyedAashiqAhmed/Prism-Engine  
> **Master Blueprint:** `goal.md`  
> **Guiding Principle:** Sprint-by-sprint methodical progress. Each sprint is built, verified against its Definition of Done (DoD), committed, and pushed to GitHub before moving forward.

---

## 📊 Sprint Status Overview

| Sprint | Phase / Goal | Status | Verified / Commit |
| :--- | :--- | :---: | :---: |
| **Baseline** | Clean Flutter Scaffold & App ID (`com.prism.engine`) | ✅ Complete | Commit `7df4917` (Pushed to `main`) |
| **Sprint 0** | Core Dependencies, Theme Tokens & Android Permissions | ✅ Complete | Verified (pub get & tests passed) |
| **Sprint 1** | Core Financial Ingestion & Axio Deduplicator (SQLite + Parsers) | ✅ Complete | Verified (9 tests passed) |
| **Sprint 2** | Riverpod State Layer & Real-Time Financial Dashboard | ⏳ Ready to Start | Pending user sign-off |
| **Sprint 3** | Guaranteed Placement & Priority Gmail Sync | ⏹ Planned | - |
| **Sprint 4** | Production RAG & Streaming Gemini AI Engine | ⏹ Planned | - |
| **Sprint 5** | Production Hardening, Anti-Abuse & Release APK | ⏹ Planned | - |

---

## 📝 Sprint Details & Log

### ✅ Baseline: Project Initialization
- [x] Initialized Git and connected to `https://github.com/SyedAashiqAhmed/Prism-Engine.git`
- [x] Flutter project generated at repo root
- [x] Configured `com.prism.engine` package & bundle ID across Android, iOS, macOS, Linux
- [x] Hardened `.gitignore` (ignoring `.env*`, `.jks`, `.keystore`, local properties)
- [x] Tested with `flutter analyze` (0 issues found)
- [x] Pushed to GitHub `main` (Commit `7df4917`)

---

### ✅ Sprint 0: Project Setup & System Permissions
- **Tasks Completed:**
  - [x] Configured `pubspec.yaml` with production packages (`flutter_riverpod`, `sqflite`, `google_generative_ai`, `fl_chart`, `google_sign_in`, `googleapis`, `flutter_notification_listener`, etc.)
  - [x] Configured `android/app/src/main/AndroidManifest.xml` with required Android permissions (`INTERNET`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED`, `POST_NOTIFICATIONS`) and `NotificationsListenerService`
  - [x] Created core theme design tokens:
    - `lib/core/theme/app_colors.dart` (Curated glassmorphic dark palette with neon emerald, coral crimson, royal violet)
    - `lib/core/theme/app_theme.dart` (Material 3 with GoogleFonts Outfit & Inter)
  - [x] Updated `lib/main.dart` with `ProviderScope` and smoke tested in `test/widget_test.dart`
- **Definition of Done (DoD) Verification:**
  - [x] `flutter pub get` resolved 71 packages with 0 errors
  - [x] `flutter analyze` passed with 0 issues
  - [x] `flutter test` passed all tests
  - [x] Committed and pushed to GitHub `main` (Commit `9257c0d`)

---

### ✅ Sprint 1: Core Financial Ingestion & Axio Deduplicator
- **Tasks Completed:**
  - [x] Built SQLite database engine `lib/core/database/database_helper.dart` with indexed `notifications` table and performance indexes
  - [x] Implemented domain model `lib/features/notifications/models/transaction_model.dart`
  - [x] Implemented Axio-grade anchored regex parser `lib/features/notifications/services/axio_parser.dart` (blacklist filter, balance stripping, account masking, merchant extraction)
  - [x] Implemented 10-minute sliding window deduplication service `lib/features/notifications/services/dedup_service.dart`
  - [x] Unit test suite created and verified:
    - `test/features/notifications/axio_parser_test.dart` (HDFC, SBI, ICICI, GPay, Paytm, OTP rejection, Spam rejection)
    - `test/features/notifications/dedup_service_test.dart` (In-memory SQLite multi-channel dedup & merchant enrichment)
- **Definition of Done (DoD) Verification:**
  - [x] All 9 unit tests passed with 100% precision
  - [x] Multi-channel reconciliation verified (same transaction within 2 minutes yields exactly 1 row with enriched merchant)
  - [x] `flutter analyze` passed with 0 issues
  - [x] Committed and pushed to GitHub `main`

---

### ⏳ Sprint 2: Riverpod State Layer & Real-Time Financial Dashboard
- **Upcoming Tasks:**
  - [ ] Implement SQL aggregation queries `lib/core/database/queries/financial_queries.dart` (monthly debits, monthly credits, category breakdown)
  - [ ] Implement currency formatter `lib/core/utils/currency_formatter.dart` (₹ Indian Rupee) and date formatter
  - [ ] Implement Riverpod dashboard state notifier `dashboard_provider.dart`
  - [ ] Build presentation widgets:
    - `spend_card.dart` (Monthly debits and credits summary cards)
    - `spend_chart.dart` (`fl_chart` dynamic category pie/bar breakdown)
    - `txn_list_tile.dart` (Glassmorphic transaction tile with merchant, time, category icon, debit/credit color)
  - [ ] Assemble `dashboard_screen.dart`
  - [ ] Wire real-time notification listener event callback in `main.dart`
  - [ ] Unit & widget tests for dashboard state and UI components

