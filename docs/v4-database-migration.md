# MoneyTrack 4.0 Phase 1 database migration

Schema 8 adds five tables. Schema 7 tables, wallet currencies, transaction IDs, savings reservations, group journals and existing attachment paths are preserved. The normal database open path runs the earlier migrations in sequence as needed and adds these tables in the same Sqflite upgrade transaction. A failed upgrade rolls back.

|Table|Contents|
|---|---|
|`managed_funds`|Fund owner, currency, metadata and status|
|`managed_events`|Posting amounts, source splits, dates, parties, methods and links to original records|
|`managed_purchase_items`|Purchase line, optional fixed-point quantity and unit price, and exact rounded line total|
|`managed_receipts`|Private purchase photos, display names and integrity digests|
|`managed_requests`|Submission keys, digests and result IDs for safe retries|

Managed Fund references are constrained to the same fund. A partial unique index allows one correction replacement per original record. Purchase lines and receipts belong to individual purchase records. Balances are derived from event data on load.

The encrypted backup reader accepts snapshot schemas 5–8. Schema 5 remains compatible with legacy savings goals. A schema 7 backup retains its existing Group Funds and adds empty Managed Fund tables in the staged database. Schema 8 carries the new rows and inline photos. Restore replays Managed Fund entries and checks line totals and receipt digests before a replacement generation becomes available. The backup format and its existing 32 MiB limit are unchanged. A schema 8 backup requires a MoneyTrack build with schema 8 support.
