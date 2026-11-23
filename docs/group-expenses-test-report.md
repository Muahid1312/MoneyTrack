# Group expenses verification

The tests use real SQLite repositories in temporary databases. The widget walkthrough opens the same group forms and settlement screen as the Android app. Sample trips and photos are test fixtures.

|Scenario|Verified outcome|
|---|---|
|Group creation and members|A new local group uses its selected currency, accepts a named roster and expected amounts, begins with zero cash, supports individual targets and retains every member who has financial history.|
|Collections and corrections|Full, partial and additional payments add exactly once. A reversal retains the source, and a duplicate reversal fails. An invalid replacement rolls back both sides of an edit.|
|Fund purchases|The Paghman trip records ten contributions of 300 AFN and five purchases of 700, 900, 250, 300 and 200 AFN. Cash falls from 3,000 to 650 AFN. Ten actual refunds of 65 AFN close it at zero.|
|Member purchases and other liabilities|A personally paid purchase creates a reimbursement. A supplier bill reserves its unpaid amount. Partial payments reduce the linked obligation and cash together. Overpayments and cash purchases beyond available funds fail.|
|Unequal refunds|Weights of 300, 300, 500 and 200 produce 92.31, 92.31, 153.84 and 61.54 AFN from a 400 AFN pool. Ties use member ID. Large products use integer arithmetic.|
|Quantity and pricing|The entry screen calculates ten units at 25 AFN as 250 AFN. Fractional quantities round once to the currency’s minor unit.|
|Settlement and cash custody|Empty and zero-surplus groups can close. A deficit blocks distribution. A discrepant cash count is recorded without changing balances. A reconciled count clears the discrepancy. Outstanding bills or refunds block completion.|
|Retries and reopening|Concurrent retries of a payout produce one row. Conflicting payloads, overpayments and stale previews fail. Reopening keeps old plans and partial payments. New entitlements credit earlier payouts. Excess refunds require an explicit return or correction.|
|Persistence, media and restore|A restarted database preserves partial refunds, cash, expenses and journal IDs. The encrypted backup round-trip restores member records, fixed allocations, project photo and expense receipt alongside populated personal records. A financially inconsistent backup fails during staging.|
|Wallet and currency isolation|A completed trip leaves the initial personal wallet position and personal transaction table unchanged. A member from a second group cannot post into the first. Locked writes are rejected.|
|Discoverability and usability|The existing More directory test opens the group destination. Searches include picnic, football and shared expenses. A widget test creates a trip, collects cash, calculates a purchase, confirms a plan and records a partial refund.|
|Sharing|The PDF exporter renders the completed Paghman report. Its records include categories, members, repayments and final status. Android destination selection and WhatsApp delivery require a device.|

All 141 Flutter tests passed locally on Flutter 3.35.6, including 13 group tests. The direct SQLite script passed the populated schema 1 through 6 upgrades to schema 7 and its 11 rollback, receipt and large-history checks.

## Running the checks

Use the repository’s pinned Flutter 3.35.6. Run `flutter test test/group_fund_test.dart test/group_flow_test.dart` for the module or `flutter test` for the full regression suite. Run `python3 tool/check_sqlite.py` for populated SQLite upgrades and rollback checks. The Android workflow runs analysis, SQLite checks, tests and a debug APK build. [Workflow](../.github/workflows/android-test-apk.yml)

## Device acceptance

On a test installation, open More and pin Groups & Trips. Choose an existing photo, take a receipt photo with the camera, make a partial reimbursement, and share the report through an installed Android app. Export an encrypted backup and restore a copy in a separate test installation. Verify the photo, the pending refund and an existing personal wallet balance after restoring.
