# MoneyTrack 4.0 implementation plan

## Repository audit

Baseline is `42a24c6` on `Muahid1312/MoneyTrack:main`. Flutter builds the Android UI. Riverpod exposes repositories through the active application runtime. Sqflite stores integer minor units in schema 7. Personal reports aggregate wallet transactions and related personal postings. Projects link to existing personal transactions. Wallet budgets derive spending from qualifying transactions and savings reservations have their own ledger. Group Funds replay their own event journal and store receipts independently. Reports already have PDF and Dari font infrastructure. Backups capture a logical snapshot, authenticate it with AES-GCM, validate it in an isolated generation and activate it only after preparation succeeds.

Managed Funds has no existing schema or route. There is no individual fund provider, purchase-line model or provider-direct reimbursement in the Group Funds ledger. Schema 7 is referenced explicitly in the backup compatibility branches, so those version checks need to be updated together with a schema migration. Existing transaction IDs, wallet currencies and group data are migration fixtures.

## Phase 1

Add schema 8 tables and an isolated append-only journal. Create a fund and its first deposit atomically. Record additional funding, itemized purchases, advances, refunds and reimbursements. Record corrections by reversing and replacing an entry in one transaction. Reuse fixed-point currency input, the runtime lock checks, theme controls and Android camera/gallery picker. Give the module a working entry in More to exercise the foundation from the normal app. Keep portable snapshots safe across the schema change and preserve any Managed Fund records and receipts they contain. Verify the accounting and migration before asking for Phase 2 approval.

## Phase 2

Add shopping lists and templates, money returns and settlement, carry-forward, status transitions, and English and Dari report previews and exports. Extend the journal with settlement operations before completing acceptance scenarios A–C.

## Phase 3

Add personal transaction templates and wallet and group reconciliation. Complete navigation organization, localization, accessibility, and the combined encrypted backup, migration and release verification. Prepare the versioned Android release after checking every workflow against the complete specification.
