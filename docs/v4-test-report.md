# MoneyTrack 4.0 Phase 1 test report

## Implemented in Phase 1

Users can create multiple independent funds, record initial and additional funding, correct or reverse funding, enter itemized purchases, and allocate each payment between entrusted cash and personal money. The fund overview shows cash, expenses, remaining advances and recent activity. It links to purchase details and receipt previews. Merchant refunds and both reimbursement sources produce traceable entries. Purchase corrections retain the original lines and images in history.

The five new schema 8 tables hold fund metadata, journal entries, purchase lines, receipts and idempotency keys. Wallets, Group Funds, projects and personal transaction IDs retain their existing schema and records. The snapshot layer accepts older schemas and carries Phase 1 data and receipts on schema 8.

|Area|Files|
|---|---|
|Ledger, fixed-point quantities and write operations|`lib/features/managed_funds/domain/managed_fund.dart`, `lib/data/repositories/managed_fund_repository.dart`|
|Migration and backup compatibility|`lib/data/database/app_database.dart`, `lib/data/database/managed_funds_migration.dart`, `lib/data/storage/portable_snapshot.dart`, `lib/features/backup/application/backup_codec.dart`|
|Screens, routing and receipt picker|`lib/features/managed_funds/application/`, `lib/features/managed_funds/presentation/`, `lib/features/explore/explore_screen.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/documents/application/document_service.dart`, Android `DocumentBridge.kt`|
|Verification|`test/managed_fund_test.dart`, `test/managed_fund_flow_test.dart`, the existing directory, calendar, group and backup tests, the emulator screenshot selector and `tool/check_sqlite.py`|

## Acceptance

|Scenario|Verified Phase 1 checkpoint|Phase 2 checkpoint|
|---|---|---|
|A|10,000 AFN funded, 7,650 AFN spent, 2,350 AFN cash and returnable. Personal transactions, wallet positions and Group Fund rows stayed the same.|Generate the report, return 2,350 AFN and complete the fund.|
|B|800 AFN purchase used 500 AFN entrusted and 300 AFN personal. Direct reimbursement cleared the advance. Entrusted cash stayed at zero, and no duplicate personal or fund postings appeared.|Complete the fund.|
|C|7,500 AFN spent, with 3,000 AFN cash and 500 AFN unpaid. Reimbursing 500 AFN from the fund left 2,500 AFN cash and zero unpaid advances.|Return 2,500 AFN and close the fund.|

Other automated cases cover duplicate submissions, concurrent spending, funding and purchase corrections, refund and reimbursement reversals, cross-fund references, currency isolation, maintenance lock, fixed-point rounding, corrupted restore rejection, and encrypted snapshot recovery. The widget walkthrough exercises creating a fund, itemized mixed payments and reimbursement on a 320 × 720 dark viewport with 125% text.

## Verification results

- `bash tool/run_flutter_tests.sh` passed 153 tests with zero failures, including 11 new Managed Funds tests.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` completed with zero errors, four existing warnings and 46 informational diagnostics.
- `python3 tool/check_sqlite.py` passed upgrades from schemas 1 through 7 to schema 8 and 11 SQLite rollback, receipt and history checks.
- `flutter build bundle --debug --no-pub` produced the Flutter kernel and assets.

## Build and device status

Flutter 3.35.6 and Dart 3.9.2 were used. The Flutter kernel and assets built successfully. The Android receipt bridge compiled against the Android 36 SDK and the installed Flutter engine classes. Gradle reached dependency resolution for the full APK, but the environment returned HTTP 403 for Flutter engine artifacts at `storage.googleapis.com`. The workspace has no Android emulator or KVM device. Camera, gallery, image orientation, keyboard behavior and signing remain to be verified on Android.

The Phase 1 application code and tests use SQLite without a network service. Portable backups retain their existing size limit. User-facing Dari report generation, shopping, settlement and lifecycle changes belong to Phase 2. Personal templates, reconciliation, app-wide localization and device release preparation belong to Phase 3.
