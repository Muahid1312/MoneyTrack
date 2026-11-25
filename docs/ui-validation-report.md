# MoneyTrack UI validation

The captured screens use the real Flutter application with seeded records and bundled fonts. The fixture includes separate AFN and USD wallets, personal spending, and a group fund with a 650 AFN surplus. The captures exclude Android system bars.

- [Home in Emerald](screenshots/v4/home-emerald.png)
- [Add Expense](screenshots/v4/add-expense.png)
- [Budgets](screenshots/v4/budgets.png)
- [Appearance in Ocean Blue](screenshots/v4/appearance-ocean.png)
- [Home in dark Royal Purple](screenshots/v4/home-purple-dark.png)
- [Dari Home with right-to-left layout](screenshots/v4/home-dari-rtl.png)
- [Accounts by currency](screenshots/v4/accounts.png)
- [Group settlement with enlarged text](screenshots/v4/group-large-dark.png)
- [Managed Funds overview](screenshots/v4/managed-fund.png)

The visual review led to a larger empty amount display, stronger contrast for chart bars, and left-to-right formatting within money amounts on the right-to-left screen. The three reference images described in the brief were unavailable, so visual comparisons used the description and these renders.

The verification suite checks accent and brightness changes, six-digit HEX validation, preference persistence and portable restore, all 12 presets and extreme custom colors, transaction entry and navigation, budget behavior, wallet counts and transfers, group settlement, Managed Fund balances and English and Dari PDF generation. Appearance tests check that changing the theme preserves personal transaction records.

## Results

- The full Flutter test suite passed 157 tests. The appearance walkthrough also checks day-level spending drill-down in the reporting currency.
- Flutter analysis reported zero errors and four pre-existing warnings.
- The Flutter debug bundle compiled. Direct SQLite checks verified upgrades from schemas 1 through 7 and 11 rollback, receipt and history cases.
- Gradle could not build the APK because the environment returned HTTP 403 from Flutter’s Android engine artifact host. The workspace lacks an Android emulator. The screen review used Flutter widget captures, and Android sharing and device behavior remain unchecked here.
