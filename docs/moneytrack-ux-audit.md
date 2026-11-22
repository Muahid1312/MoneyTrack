# MoneyTrack UX audit

Baseline inspection of main at f584d1b, version 3.0.1. The client is Flutter Material 3 with Riverpod, a four-page IndexedStack and a floating Add action. Details use Navigator routes and modal sheets. Most features already have a working editor and repository. The main difficulty is finding the right entry point and understanding the scope of the amounts shown.

## Inventory and route changes

Each row gives the baseline path and the proposed entry. “Implemented” means that the inspected source connects the screen to the indicated model or service. Native interactions require a compatible Android device. Verification results belong in the redesign report.

|Feature and status|Baseline path → proposed entry|What the user does and what the code uses|Discovery problem|
|---|---|---|---|
|Income and expense entry, implemented|Center plus or Home → Add or Home|Enter amount, choose category and wallet, save using TransactionEditorScreen and TransactionRepository. Date, note and project are optional.|Plus has no visible label.|
|History and search, partial filtering|Activity → Activity|Search note/category and filter date, currency, category or type using TransactionFilter and lazy date groups. Wallet filtering is missing in the baseline.|Mixed wallets can look like one account.|
|Receipt, edit, delete and undo, implemented|Tap or hold transaction → Activity detail or Explore receipts|TransactionActions opens editor, Android attachment capture/import or deletion with confirmation and undo. Undo restores canonical identity and receipt bytes.|Long press is difficult to discover.|
|Wallets and accounts, implemented|Home wallets or More → Explore wallets|Select wallet, inspect history, add/edit/archive an account through WalletRepository and WalletDetailsScreen. Wallet type, opening amount and currency are stored.|Wallet management and reporting currency look related.|
|Wallet transfers, implemented|Wallets → Home transfer or Explore transfers|Pick source and destination, enter amount, provide an explicit rate for different currencies, confirm. Transfer legs change wallet positions.|Common action inside management.|
|Income and expense categories, implemented fixed catalog|Add and Activity filter → Explore categories|Select a built-in category. Category IDs are stored on transactions. Project categories have a separate editor.|No directory entry. Personal subcategories and tags are absent.|
|Flexible wallet budgets, implemented|Home and More budget overview → Explore budgets|Choose wallet, amount, period, category and optional rollover. WalletBudgetCalculator matches expense rows. Carry, spent, remaining and overrun are derived.|Easy to confuse a plan with available cash.|
|Monthly currency-wide limit and alerts, implemented|More monthly budget → Explore budgets|Set the reporting currency limit in BudgetEditorSheet. BudgetStatusProvider calculates 80% and 100% alerts from that currency’s expenses.|Two similarly named budget settings.|
|Savings and emergency funds, implemented|Savings tab or More planning → Explore savings|Create a goal, set target and weekly plan, reserve or release money, inspect event history, confirm withdrawal. PlanningRepository records savings_events.|Reservation and cash can look like independent balances.|
|Borrowing, lending and repayments, implemented|More planning, debts → Explore debts and loans|Choose direction, record principal, repay/settle, inspect or void a posting. Debt postings change cash and outstanding principal.|Nested entry and bookkeeping terms.|
|Recurring schedules and due items, implemented|More planning → Explore recurring and upcoming|Create a schedule, choose automatic or confirmation mode, reconcile, review/skip, edit/pause/cancel. Occurrence keys prevent duplicate postings.|Upcoming entries are several taps away.|
|Local reminders, implemented with Android permission|More planning → Explore reminders|Enable notifications and reconcile schedules using ReminderService and Android notification support.|Separate from the due list.|
|Projects and assignments, implemented|More projects → Explore projects|Create project/category, view income, expense, contract balances, link existing entries, allocate/release for personal use. ProjectRepository preserves original transactions.|Hidden beside app preferences.|
|Spending analysis, implemented|More spending insights or Home overview → Insights|Select date range, inspect category shares, cash flow and comparison from FinanceCalculator and statistics providers.|Analysis is buried.|
|Financial reports and exports, implemented|More reports → Explore detailed reports|Filter original currency, wallet, project and dates. Review cash flow and project summaries. Export PDF/CSV via ReportService and ReportExporter.|Several exports with different scopes.|
|Currency tools, implemented with manual rates|More reporting currency → Explore reporting currency|Choose the report currency. Transfer conversions use a user-entered rate. Ledger rows retain original currency.|The setting can appear to revalue cash.|
|Encrypted backup and restore, implemented with native document access|More privacy → Explore backup|Enter passphrase, share encrypted snapshot, pick backup, authenticate, review and confirm replacement. GenerationStore stages and activates validated SQLite and receipt data.|No record of last successful handoff.|
|App lock, implemented with native authentication|More privacy → Explore app security|Configure PIN, biometrics and timeout via SecurityController and AccessGuard.|Buried with financial features.|
|Ledger export, implemented|More data → Explore data export|Export transaction CSV. This is separate from filtered reports and encrypted recovery.|Export is easy to confuse with backup.|
|Name, theme, version, clear ledger, implemented|More preferences/data/about → Explore settings|Edit profile and display preferences or explicitly confirm clearing the current ledger. SettingsRepository and generation services handle storage.|Destructive control beside everyday features.|
|Home privacy, implemented|Home eye → Home eye|Hide or reveal amounts through the persisted balance preference.|Keep all new summary amounts consistent with this choice.|

## Accounting and dependencies

SQLite upgrades add wallets, projects, planning, documents and wallet budgets through schema 6. Transaction IDs link receipts, projects and recurring occurrences. Wallet positions include opening cash, posted income/expenses, both sides of transfers and debt postings. Savings events reserve a portion of cash. Wallet budgets only read expense rows. The legacy monthly limit is per reporting currency. All persisted money uses integer minor units with currency-specific precision. The portable snapshot validates tables, foreign keys, sequences and receipt bytes before switching generations. Redesign work should require no ledger write during navigation.

## Gaps at inspection

Missing capabilities include editable personal subcategories, tags, bank synchronization and automatic FX rates. Receipt attachment starts from a saved transaction. Historical daily balance snapshots are absent. The Android share target and biometric hardware outcome cannot be inferred from Dart tests. No broken accounting implementation was identified by this inspection. Baseline filtering, navigation and backup feedback have the partial behaviors described above.
