# Managed Funds architecture

From More, search for **Managed Funds**, **entrusted** or **پول امانتی**. The normal flow is **New fund → Add purchase → purchase details**. Purchase details contains receipt actions, corrections, merchant refunds and reimbursements. The fund overview calculates the balances and shows searchable funding, purchase and reimbursement history.

The app runtime supplies the active SQLite database to a Riverpod provider. The repository loads each fund's journal in posting ID order and replays it through `ManagedLedger`. Currency belongs to the fund. The posting date is part of the transaction record. Backdated entries replay in the order in which they were recorded, so historical dates cannot bypass current balance checks.

Each operation uses one SQLite transaction. The repository checks the storage lock again inside the transaction. A submission key and payload digest identify retries. A matching retry returns the previously stored ID. Reusing a key with different data raises a validation error. SQLite serializes simultaneous cash writes.

`DocumentBridge` launches the Android camera or gallery. For managed receipts it preserves suitable images and downsizes oversized images on a worker thread, with a 2 MiB output limit and a 2,400-pixel longest edge. The managed receipt store keeps up to five JPEG or PNG photos per purchase in the private SQLite database. Each image is checked against its SHA-256 digest on read and during restore. Replacing a receipt updates it atomically. Purchase corrections retain the original record and its receipts and copy the current receipts to the replacement.

The fund overview and forms use MoneyTrack's existing themes, amount input conventions and feature search. Phase 1 has an English interface with the Dari feature name and support for Persian and Arabic digits in amount and quantity entry.
