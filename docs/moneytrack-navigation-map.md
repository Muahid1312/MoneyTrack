# MoneyTrack ledger navigation

|Primary tab|Controls|Where they lead|
|---|---|---|
|Transactions|Month arrows, currency menu, search, Daily, Calendar and +|A tapped calendar day shows its records. Daily lists the month in reverse chronological order. Search spans all dates and retains date, wallet, type and category filters. Tap an entry for receipts, editing, deletion or undo.|
|Statistics|Month arrows, reporting currency, Expenses and Income|Tap a chart slice or category row for its underlying entries. Trends and comparisons opens the existing period filters, monthly overview, historical wallet cash, projects and reports.|
|Accounts|Balances grouped by currency, transfer action and New wallet|Open a wallet to inspect its transactions, transfers, debt postings and reservations or edit its definition.|
|More|Find a feature, ordered pins, recent tools and grouped rows|Search aliases such as “borrow”, “save money”, “business”, “backup” and “monthly limit”. Matching wallets and transactions appear below navigation results.|

## Entry

The transaction form opens on the selected calendar date. A Daily view in the current month starts a new entry today. Review the visible type, date and account, choose a category, enter an amount and save. Notes are optional. The star opens past entries for the current account, currency and type. Choosing one fills a draft. Only Save writes the new transaction. Transfer opens the existing two-account form with its own amount, date, exchange rate and confirmation.

## Directory

|Group|Tools|
|---|---|
|Financial planning|Available cash, wallet budgets, monthly spending limit, savings goals|
|Accounts and records|Wallets and accounts, transfer money, categories, transactions and receipts, add a transaction|
|Money management|Recurring transactions, debts and loans, upcoming payments, local reminders, projects, spending insights, financial reports, reporting currency|
|Tools|Encrypted backup and restore, CSV data export|
|Application|App security, settings including profile, appearance, ledger controls and version|

The shell retains visited tab state. Android Back dismisses a picker or pushed route first, then returns from a secondary tab to Transactions. The available-cash screen preserves the earlier wallet dashboard. The former Activity browser remains available from the ledger search icon.
