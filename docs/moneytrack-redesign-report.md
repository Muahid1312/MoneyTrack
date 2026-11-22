# MoneyTrack 3.2 Android redesign

MoneyTrack opens on the current month’s transactions. A day shows its income, expenses and records in one currency. Tap **+** to record something on that date, **Daily** to scan the month, or the search icon to find an older entry. Accounts is one tab away. **More → Available cash** opens the personal dashboard with spendable wallet cash, savings reservations and budget headroom.

The audited starting point was 3.1.0 on main at `928377a`. Existing SQLite repositories, integer minor units, wallet identities, recurrence reconciliation and encrypted backup format continue to handle writes. Version 3.2.0 has Android build number 6 and uses the existing schema 6.

## Daily workflows

|Task|Controls and expected result|
|---|---|
|Check a date|Select a day on the seven-column calendar. The ledger below shows that day's records, signed totals and account names. Arrows change months. Daily opens the same month's grouped history.|
|Record an expense|From the ledger tap **+**, choose a category, enter an amount and tap **Save expense**. This takes five interactions when opening the category chooser and choosing an item are counted separately. Date, type and account are visible before saving. A different account or note adds a step.|
|Reuse an entry|From the editor tap the star, choose a previous entry, check the editable details and save. Ranking uses this account, currency and transaction type. The new record receives its own ID.|
|Transfer or schedule|Transfer uses two wallets and previews the receiving amount. A foreign-currency transfer requires a manual rate. Under More details, a recurring schedule can start from the current draft. Saving the rule closes the draft and the default mode requires occurrence confirmation.|
|Inspect spending|Statistics opens this month’s income and expenses for the selected currency. Tap a category or chart slice for the contributing records. Trends and comparisons opens the existing period controls, historical cash, projects and reports.|
|Check an account|Accounts groups wallets and totals by original currency. Open a wallet for dated history, reservations and management. Transfer and New wallet are available here.|
|Find a tool|More has 21 destinations, short descriptions, aliases, ordered pins and recent tools. Searching “borrow” opens the path to debts, “save money” to savings goals and “backup” to encrypted recovery. Results can also include matching wallets or transactions.|

Ordinary expenses and income feed the monthly and daily totals. Transfers appear once in each relevant currency's ledger and have no effect on the income or expense counters. Debt principal and reservation movements remain available in the wallet history. Setting a budget changes the plan. An emergency contribution reserves wallet cash, and a confirmed withdrawal releases it. The available-cash dashboard keeps these amounts separate. Fresh installations default to AFN and a populated installation uses its stored currencies.

## Visual comparison

The available reference was the Realbyte Android income-entry screenshot on slide 3 of a 2023 usability study. The official listing and support site returned HTTP 403 from the cloud network. No current reference image for the calendar, accounts, budgets or statistics was available. The requested navigation and calendar specifications guided those screens. The reference analysis records what could be observed. [Reference analysis and sources](realbyte-reference-analysis.md)

The MoneyTrack captures below use the actual Flutter screens and a test-only AFN ledger at 390 × 780. The February fixture includes income, expenses, a transfer and a populated leap day. These records are confined to tests.

|Screen|Capture|
|---|---|
|Calendar and selected-day ledger|[Calendar](screenshots/calendar.png)|
|Daily records|[Daily view](screenshots/daily.png)|
|Ordinary entry|[Expense form](screenshots/entry.png) · [Dark income form](screenshots/entry-dark-income.png)|
|Monthly category statistics|[Statistics](screenshots/statistics.png)|
|Wallet balances and transfer access|[Accounts](screenshots/accounts.png)|

|Aspect|Observation and resulting choice|
|---|---|
|Structure and alignment|Both income forms show a compact heading, star, three adjacent type buttons and five aligned fields in the same order. In both, the value column starts approximately one quarter of the way across the display. Date and category values were aligned to the account column after the first rendering.|
|Spacing and density|The historical capture fits those five rows in about a quarter of its height. MoneyTrack uses a minimum of 52 logical pixels per row, about a third of the 780-pixel viewport for five rows. The native text keyboard appears on demand. The action to save stays near the bottom.|
|Type and color|The working amounts and signed day totals carry more visual weight than the labels. Income is blue and expense is red. Selection in the editor was adjusted after comparing the two dark income screens. The application uses its bundled fonts and original theme.|
|Ledger and navigation|Seven columns at the captured width give each date about 56 logical pixels. A selected day shows up to two signed amounts, and full amounts appear below. One persistent row holds the four tab labels. Current reference screenshots would be needed to measure these placements against the current Realbyte app.|
|Interaction cost|A basic expense uses the five actions described above with a preselected wallet and date. The historical screenshot confirms the fields and controls. It does not document a full timed save task. No user timing or preference measurements were collected.|

## Data preservation and verification

The tests exercise leap days, short months, year transitions, per-currency summaries, same-currency wallet isolation, neutral transfers and direct chart-to-record drill-down. Widget flows cover entry and decimal precision, frequent-entry reuse, rapid repeat taps on Save, transfer balances, scheduled drafts, goal creation, feature aliases and all directory destinations. Small-screen checks run at 320 × 640 with 1.6× text in both themes.

The personal-finance regressions cover repeating and custom budget boundaries, rollover after overspending, category exclusions, emergency contributions and withdrawal previews, and encrypted backup/restore. Populated upgrade fixtures cover schemas 1 through 5. The 2.0 fixture verifies original wallet balances, currencies, transaction IDs and savings events. Separate direct SQLite checks exercise linked receipt restoration, rollback and a 25,001-entry history. A restored backup keeps the original financial identities and reservation settings.

All 128 Flutter tests passed locally on Flutter 3.35.6, following a 126-test baseline on 3.1. Flutter analysis completed with zero errors, four warnings and 45 information-level findings under the repository’s nonfatal settings. The four warnings concern nullability and dead code in backup and startup.

The Android workflow analyzes and tests the Flutter application, builds a debug-signed APK and packages it with a SHA-256 checksum. The release handoff supplies the completed run and downloadable artifact. [Android verification workflow](../.github/workflows/android-test-apk.yml)

## On-device checks still open

Try recording an expense using your keyboard, finding it on the calendar, and opening its receipt. Check TalkBack and the larger text size you use. In the personal dashboard, compare one wallet’s cash, reserved amount and available cash with your existing records. On a test installation, check camera or document access, biometric unlock, reminder delivery and restoring a copy of your encrypted backup from your preferred Android file provider. Human testing of ease of use and comparison with the current Realbyte release remain open. Personal tags and editable personal subcategories have no backing financial records in this MoneyTrack version. [Feature inventory](moneytrack-feature-inventory.md) · [Navigation map](moneytrack-navigation-map.md)
