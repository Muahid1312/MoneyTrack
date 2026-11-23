# MoneyTrack 3.4 Android redesign

MoneyTrack opens on the current month’s transactions. Tap a date to see its entries, **+** to record one, or **Daily** to scan the month. Tap the month title to jump to a different date. **Accounts** answers how much cash is available in each wallet. **More → Groups & Trips** opens shared funds, and **More → Available cash** opens the personal dashboard with wallet budgets and reserved savings.

Version 3.4.0 (Android build 8) builds on 3.3.0 at `25f47bb`. The redesign uses the existing SQLite schema 7, money parsers, repositories, posting operations, settlement calculations and encrypted backup format. All financial amounts still use integer minor units.

## Everyday tasks

|Task|Interaction|
|---|---|
|Enter an expense|Tap **+**, choose a suggested category, enter the amount and tap **Save expense**. The selected date and remembered wallet are visible. The full category picker remains available. The star reuses a previous entry as an editable draft.|
|Review income and spending|Daily, Calendar, Weekly, Monthly and Total share the selected currency. Weekly opens the transactions for a week within the selected month. Monthly shows the year. Total compares monthly spending and shows budget headroom. Tap a transaction for details, receipts or editing. In Statistics, tap a chart segment or category row to inspect its transactions. Open **Trends and comparisons** for other periods.|
|Check or move money|Accounts groups cash, reserved and available totals by currency. Tap a wallet for history or the transfer icon for two-wallet posting. A cross-currency transfer previews the receiving amount using the rate you enter.|
|Check a budget|Wallet budgets track the selected period and category. The separate monthly spending limit shows limit, spending, remaining balance, usage and category breakdown for the selected reporting currency. Setting a limit is a planning operation.|
|Manage a trip|The group list shows members, status, contributions and cash. Overview contains posting shortcuts and obligations. Members shows actual and expected contributions. Expenses identifies the payer and payment source. Settlement shows the distributable amount and each refund before confirmation.|
|Find an occasional task|The 23 destinations in More have names, descriptions and search terms. Try “trip”, “borrow”, “save”, “project” or “backup”. Appearance has a direct route to system, light and dark themes. Existing pins retain their destination IDs.|

## Visual review

The versioned PNGs are Flutter widget captures using synthetic records and bundled fonts. The calendar fixture includes a populated February leap day. The group fixture has ten contributors at 300 AFN each, five purchases totalling 2,350 AFN and a 650 AFN surplus. Each member is due 65 AFN. These records exist only in the test databases.

|Flow|Captures|
|---|---|
|Monthly ledger|[Calendar](screenshots/calendar.png) · [Daily transactions](screenshots/daily.png) · [Weekly](screenshots/weekly.png) · [Monthly](screenshots/monthly.png) · [Total](screenshots/total.png)|
|Entry|[Expense](screenshots/entry.png) · [Income in dark mode](screenshots/entry-dark-income.png) · [Open account picker](screenshots/entry-accounts-dark.png) · [Transfer](screenshots/transfer.png)|
|Personal finance|[Accounts](screenshots/accounts.png) · [Statistics](screenshots/statistics.png) · [Monthly budget](screenshots/budget.png)|
|Discovery and appearance|[More](screenshots/more.png) · [Appearance](screenshots/appearance.png)|
|Shared fund|[Group list](screenshots/groups.png) · [Overview](screenshots/group-overview.png) · [Members](screenshots/group-members.png) · [Expenses](screenshots/group-expenses.png) · [Settlement](screenshots/group-settlement.png)|
|Accessibility|[Calendar at 320 × 640](screenshots/calendar-narrow.png) · [Dark settlement at 320 × 640 and 160% text](screenshots/group-large-dark.png)|

The historical Realbyte Android entry screenshot on slide 3 measures 702 × 1600. At the same display width, both income forms place values about a quarter of the way across, below a three-way selector. Five original field rows occupy about a quarter of the reference height. MoneyTrack allows at least 52 logical pixels per row at normal text size and shows category shortcuts below the fields. Tapping Account opens actual wallets in a grid below the form. The back arrow, type-specific title, neutral field values and thin rules follow the observed form. The on-demand Android numeric keyboard handles amount entry. The Save action is visible from the initial form. The cloud network returned HTTP 403 for the reference’s current store and help pages. The entry comparison uses the historical image. For the calendar and period tabs, the separate Rico index and Google ScreenQA bounds establish positions on an actual 1080 × 1920 Realbyte Android screen. The comparison drawing marks those bounds beside MoneyTrack’s render. [Calendar geometry beside the implementation](screenshots/calendar-reference-layout.png) · [Reference mapping and sources](moneytrack-reference-mapping.md)

At 390 × 780 the calendar has roughly 56 logical pixels per day column. Underlined and filled date indicators distinguish today from the selected day. A dedicated line under the grid shows exact amounts. Comparing actual renders led to shorter weekday labels, a legible donut centre, flush-aligned amount and note fields, and right-aligned group obligations. A review of the Android renders caught a wrapped Calendar tab and a truncated year. The period tabs now keep their names on one line, and the toolbar fits the year beside the month. At widths below 380 logical pixels it abbreviates the month. At 320 × 640 with enlarged text, summary figures switch to rows and accounts place their available amount below the wallet name.

## Verification and phone testing

The 142-test regression suite covers budget boundaries and rollover after overspending, isolation by wallet and currency, emergency reservations and withdrawals, encrypted backup and restore, and a populated 2.0 upgrade retaining balances, transaction IDs and savings events. Group tests exercise partial contributions, member-paid purchases, liabilities, proportional refunds, confirmations and corrections. Navigation tests exercise all registered tools and the normal calendar, entry, transfer, search and chart flows.

The Android 11 emulator walkthrough uses a temporary ledger and captures 18 populated screens, including the calendar, Add Expense, Accounts, Statistics and group settlement. Production screenshot protection stays enabled. The testing prerelease provides a nine-screen preview, the installable APK and its checksum. Its verification link opens the build and the full screenshot archive. [Android preview](https://github.com/Muahid1312/MoneyTrack/releases/download/v3.4.0-test.2/MoneyTrack-Android-preview.jpg) · [APK, checksum and build results](https://github.com/Muahid1312/MoneyTrack/releases/tag/v3.4.0-test.2)

Flutter analysis completed with zero errors, four warnings and 46 informational findings. All 142 tests passed. Direct SQLite checks also exercised six populated schema upgrades, failed writes and recovery, receipt restoration and a 25,001-entry history. The build uses the GitHub runner’s Android debug signing certificate. The publishing step checks the signature, application ID, version and SHA-256 before making the APK available. [Android workflow](../.github/workflows/android-test-apk.yml)

On a phone, check your usual keyboard and font size, TalkBack focus and labels, receipt capture, biometric unlocking, background reminders and backup file selection. Android requires a matching signing certificate for an in-place upgrade. Use a spare Android device or an emulator if the existing installation has a different signer. Preserve an encrypted backup before testing with personal records. [Audit](moneytrack-ui-audit.md) · [Navigation map](moneytrack-navigation-map.md)
