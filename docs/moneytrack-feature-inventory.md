# MoneyTrack feature inventory

Audited the Flutter Android app on main at 928377a, version 3.1.0. Material routes and Riverpod providers connect the UI to local repositories. SQLite schema 6 stores financial records in integer minor units. The generation store coordinates encrypted recovery, settings and receipt files. The redesign can reuse this boundary without a database migration.

|Existing entry|Underlying screen or service|Capability to preserve|
|---|---|---|
|Home|DashboardScreen, WalletBudgetPanel|Cash, savings reservations, spendable balance, budget status, upcoming obligations and recent entries|
|Activity|TransactionsScreen, TransactionFilter|Chronological history, note/category search, wallet, date, category, currency and type filters|
|Transaction detail|TransactionActions, AttachmentsScreen|Edit, receipt image or document, confirmed deletion and undo with original identity|
|Add|TransactionEditorScreen|Fixed-point input, original currency, optional note/date, project assignment, document after saving|
|Wallets|WalletsScreen, WalletDetailsScreen, WalletEditorScreen|Opening balance, currency, type, history, edit and archive|
|Transfers|TransferScreen, WalletRepository|Same- and cross-currency postings with explicit manual rates|
|Categories|Categories page and catalog|Built-in income and expense categories, matching records and separate project categories|
|Wallet budgets|WalletBudgetPanel|Daily/weekly/monthly/custom limits, category scope, carry-forward and overrun|
|Monthly spending limit|BudgetScreen and editor sheet|Reporting-currency limit, category spending and warnings|
|Savings goals|GoalsScreen and goal details|Targets, emergency designations, contributions, withdrawal preview, weekly plan and history|
|Debts and loans|DebtsScreen and repayment forms|Money owed in either direction, settlement, voiding and principal movements|
|Recurring, upcoming and reminders|RecurringScreen, UpcomingScreen, PlanningScreen|Automatic or reviewed occurrences, history, pause, cancellation and local notifications|
|Projects|ProjectsScreen, assignment and allocation forms|Project details, categories, links to existing transactions, client receipts and project-currency results|
|Insights and monthly overview|StatisticsScreen, MonthlyOverviewScreen|Period totals, category distribution, historical trends, contributing entries and reconstructed wallet cash|
|Reports and exports|ReportsScreen, ReportExporter, DataExportService|Filtered reporting, PDF and CSV export, full ledger CSV|
|Backup and recovery|BackupScreen, BackupCodec, GenerationStore|Authenticated encryption, financial tables, receipt bytes, settings and staged replacement|
|Security|SecuritySettingsScreen, lock gate|PIN, biometrics and timed lock|
|Settings|SettingsScreen|Reporting currency, appearance, profile, version and confirmed ledger clearing|
|Explore|MoneyFeature and local preferences|Feature aliases, recent tools, ordered pins, separate record matches and quick guide|

Android hardware and document-provider interactions require device testing. Personal tags and editable personal subcategories have no backing ledger representation. Recurrence has its own schedule and occurrence identity.
