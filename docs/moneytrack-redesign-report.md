# MoneyTrack 3.1 redesign

MoneyTrack 3.0.1 required users to know that debts were under Planning in More and that a long press revealed receipts. Two budget systems had similar labels and different scopes. The redesign gives each financial task a visible entry and puts the wallet, currency and period beside the amounts they describe.

## Daily use

Home starts with spendable wallet cash, savings reservations and the wallet selector. When multiple active wallets share the selected currency it also shows their combined available cash. Expenses, income and transfers open from the wallet card. The current month, recent entries and the next dated obligation follow. Current cash and outstanding principal are presented separately. A wallet budget can be lower than available cash because it is a spending plan.

Activity groups entries by date and supports note/category search and wallet, type, date, category and original-currency filters. Tap an entry to read its details, attach a receipt, edit or delete with confirmation. Undo retains the original ID and document links. The ledger list still builds rows on demand.

Add starts with the amount and uses the selected wallet’s history to order category shortcuts and suggest the more frequently used entry type. Ties and fresh wallets default to Expense. The editor requires a category and shows the working wallet. A transfer opens its own two-wallet form. Users can request a receipt under More details, save the entry and attach the document to its assigned ID.

Insights includes the reporting currency and period controls, contributing entries, category drill-down, current monthly spending limit, project access and dated wallet cash. Cash history uses original-currency opening balances, dated transactions, transfer legs and active principal postings. Wallet opening balances have no historical timestamps. The reconstruction uses their current values and includes reserved cash. Monthly overview retains the earlier weekly chart, comparisons and position details.

Explore groups 20 destinations by purpose. Users can search for a task, pin and reorder shortcuts or reopen a recent tool. Matching ledger entries and wallet names appear in their own sections. No search terms or financial amounts are sent to a server.

## Other changes

Wallet cards show account type, currency, cash and reservations. Wallet budgets display period, base limit, rollover, actual spending, progress and overrun. Deleting a limit requires confirmation. Savings goals show the amount still needed. Debt records are grouped by who owes whom. The upcoming list orders unpaid dated debts, scheduled entries and pending confirmations by date. Project cards show income, expenses and net result in project currency. Recurring rules retain separate automatic and review modes. Backup shows the last time Android confirmed sharing an encrypted file. A cancelled or unconfirmed share does not advance that date.

The Material theme uses a blue action color, independent cash-flow colors, bundled Jakarta and Arabic-script fonts and tabular financial amounts. Navigation and feature names have visible text. The app uses the system text scaler and native Material back navigation. The quick guide is optional.

## Task walkthroughs

Counts assume an unlocked app on Home, an existing default wallet and reachable features. A field entry or picker choice counts as one meaningful action. Keyboard digits, scrolling and system confirmation steps vary by device. These are automated task walkthroughs and interaction estimates. Human usability testing remains open.

|Task|Expected path and meaningful actions|Verified completion|
|---|---|---|
|Record an expense|Home → Add expense → enter amount → choose category → Save, 4 actions including entry|One expense appears in the selected wallet with the original currency and exact minor units.|
|Find an old transaction|Activity → enter note → tap result, 3 actions|A month-old expense opens with its receipt, edit and delete actions.|
|Transfer cash|Home → Transfer money → choose destination → enter amount → Confirm, 4 actions with the source preselected|The form test explicitly selects both wallets and checks that a USD 12.34 transfer creates one transfer and debits and credits the correct wallets. Cross-currency transfers also require a rate.|
|Find debt tracking|Explore → search “borrowed money” → Debts and loans, 3 actions|The debt register opens. Repayment and principal accounting have separate regression coverage.|
|Create a savings goal|Explore → search “saving” → Savings goals → New goal → name → target → Save, 7 actions|A USD 300 target is persisted with zero reserved until the first contribution.|
|Open project finances|Explore → search “project” → Projects → select a project, 4 actions|The directory reaches Projects. The populated project flow test opens its detail and checks the cash accounting view.|
|Find backup and restore|Explore → search “backup” → Backup and restore, 3 actions|The encrypted backup screen opens. Separate restore tests authenticate, stage, verify and roll back financial and receipt data.|

## Verification and remaining work

The baseline suite passed 122 tests before UI changes. All 126 tests passed locally on Flutter 3.35.6. Flutter analysis completed with zero errors, four warnings and 45 information-level findings. The redesigned suite covers all directory destinations, original-record actions, scoped wallet filtering, cash history across currencies, a saved goal and a posted transfer. Other tests cover a busy-day lazy ledger, empty states, small 320-pixel layouts at 1.6 text scale in both themes, period boundaries, budget rollover after overspending, emergency deposits and release, migration fixtures and encrypted restoration. The direct SQLite checks exercise populated schemas 1 through 5, transaction IDs, balances, receipts, rollback and a 25,001-entry history. No ledger schema change was required.

The Android workflow uses pinned Flutter 3.35.6, Java 17 and debug signing. Its uploaded ZIP contains the device-test APK and SHA-256 checksum. Final workflow status and the artifact link are supplied with the release handoff. The analyzer uses the repository's nonfatal warning and information settings.

Physical-device verification is still needed for screen-reader announcements, keyboard and font preferences, biometric hardware, camera/document picking, notification delivery, the chosen backup destination and restore from that file. Human observation is still needed to judge whether these paths are intuitive. Test an in-place upgrade with a matching signing key and a verified backup. Android requires a matching app signature to install over an existing copy. Tags and editable personal subcategories have no existing ledger support and were omitted.
