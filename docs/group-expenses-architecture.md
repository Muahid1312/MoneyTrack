# Groups & Trips architecture

MoneyTrack 3.2 uses Flutter, Riverpod, Material routes and SQLite. Its existing Projects module attaches personal wallet entries to projects, including business receipts and manual exchange rates. Entrusted group cash requires its own accounting boundary. A group uses one currency and represents one physical cash box or separately held pot. There is no automatic posting to personal wallets.

## Implementation plan

1. Add independent tables in schema 7, register the feature in More, and extend encrypted snapshots to accept versions 5, 6 and 7.
2. Create local groups and members. Record contributions, purchases, reimbursements and corrections in an append-only journal inside SQLite transactions.
3. Freeze proportional allocations at confirmation, record each actual payout, and retain paid amounts across explicit reopenings.
4. Connect the four group sections to the journal. Reuse the Android document picker and the existing PDF and sharing infrastructure.
5. Exercise the Paghman trip, rounding, payment retries, legacy upgrades, backup/restore and navigation before packaging the Android build.

## Storage and posting

|Schema 7 table|Purpose|
|---|---|
|trip_groups|Group identity, calendar date, fixed currency, optional location and description, expected contribution and budget.|
|trip_members|Group-local roster, display names, individual targets and safe removal.|
|trip_events|Append-only contributions, purchases, bills, payments, revisions, counts, state transitions and confirmed allocations.|
|trip_images|Project cover and expense receipt images linked to their owning group and optional journal entry.|

Schema 7 adds these tables, composite foreign keys, indexes and journal-protection triggers. It leaves the existing personal finance tables and balance views intact. Foreign keys bind both ends of a member or event reference to the same group. SQLite rejects updates and deletes against journal entries.

The repository loads a group inside one SQLite transaction and replays entries in committed ID order. It validates each posting against the resulting cash, obligations, lifecycle and previous payments. The entry carries both its financial date and its recording timestamp. The unique request key and payload fingerprint identify retries. A changed preview revision requires a fresh review. A correction and its replacement commit together. A cash count records the difference from the ledger without changing its balance.

The group screen uses Riverpod providers and existing Material routes. More exposes the tool to search, pins and recent destinations. A group has Overview, Members, Expenses and Settlement tabs. Personal transaction reporting and budget calculations use their existing repositories. The group report uses the same offline PDF fonts, CSV exporter and Android share sheet as other MoneyTrack reports.

## Photos and recovery

The Android gallery and camera use the existing document bridge. Photos over 1 MiB are resized locally. The stored JPEG or PNG is limited to 1 MiB and saved in the same database transaction as the purchase or group. The source receipt remains attached after a correction. Group images travel inside the encrypted snapshot. The application’s 32 MiB portable-backup limit applies across the whole export. The existing PDF exporter supports up to 1,000 report rows. CSV can carry a larger itemized report.

Schema 5 and 6 backups initialize an empty group module when restored. Schema 7 includes all four tables and the original IDs. Restore first checks the schema, foreign keys, image contents and financial event history in a staging database. The app selects that generation only after review and confirmation. A personal ledger clear keeps entrusted group records separate.

[Accounting rules](group-expenses-accounting-rules.md) · [Verification](group-expenses-test-report.md)
