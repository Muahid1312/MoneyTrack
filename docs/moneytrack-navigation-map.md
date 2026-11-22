# MoneyTrack navigation

|Destination|First question|Next action|
|---|---|---|
|Home|How much cash can I spend?|Read available cash, select a wallet, record expense or income, transfer, open recent activity.|
|Activity|Where is my transaction?|Search the ledger in one currency, narrow by wallet/type/date/category, open details, edit, attach or delete.|
|Add|What did I pay or receive?|Enter an amount, review the visible type, category and wallet, save. Transfer opens its own two-wallet form. Back returns to the originating tab.|
|Insights|Where did my money go?|Choose a period and reporting currency, inspect spending, cash flow and the contributing entries.|
|Explore|Where can I find a feature?|Search local names and synonyms or browse a group. Pin frequently used destinations. Back from a feature returns to the directory.|

## Directory

|Group|Destinations and child routes|
|---|---|
|My money|Wallets → account and history, transfers, categories → matching Activity, transactions → details and receipts, Add → editor.|
|Planning|Budgets → currency-wide monthly and wallet limits, savings goals → emergency designation and contribution history, recurring transactions → schedules and occurrences.|
|Obligations|Debts and loans → outstanding principal, repayments and history. Upcoming payments → dated obligations. Local reminders → Android notification preferences.|
|Advanced finance|Projects → assignments, allocations and categories. Insights → chart periods. Detailed reports → filters, PDF and CSV. Reporting currency → original-currency reporting selection.|
|Tools and security|Backup and restore → encrypted export or reviewed restore. Security → PIN and biometrics. Data export → transaction CSV. Settings → name, appearance, clear ledger and version.|

## Design system

Use a blue primary action (#2563EB) with a deeper pressed shade (#1D4ED8), paper surfaces on #F8FAFC and a #0B1220 dark canvas. Income, expense and warnings have their own semantic tokens. Direction, labels, signs and progress text carry meaning independently of hue. Use the bundled Jakarta typeface, an Arabic-script fallback, tabular monetary figures, the shared spacing scale, Material tap feedback and touch targets of at least 48 logical pixels for primary actions. Sheets and routed forms retain Android back behavior. Device-only discovery preferences are independent of financial backup data.

The directory searches feature names, descriptions and synonyms first. A query of two or more characters also checks wallet names and transaction notes/categories. Up to three matching wallets and three transactions appear under separate headings. Record amounts retain their original currency. Pins, their order and the three most recently opened tools are stored locally. An optional getting-started sheet is available from an empty Home and from Explore at any time.
