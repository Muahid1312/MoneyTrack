import 'package:sqflite/sqflite.dart';

const managedFundTables = [
  'managed_funds',
  'managed_events',
  'managed_purchase_items',
  'managed_receipts',
  'managed_requests',
];

Future<void> migrateManagedFundsV8(Database db) async {
  await db.execute('''CREATE TABLE managed_funds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
    provider TEXT NOT NULL CHECK(length(trim(provider)) BETWEEN 1 AND 120),
    currency TEXT NOT NULL CHECK(currency IN ('AFN','USD','EUR','PKR','JPY','KWD')),
    opened_at INTEGER NOT NULL,
    description TEXT NOT NULL,
    purpose TEXT NOT NULL,
    expected_at INTEGER,
    notes TEXT NOT NULL,
    icon TEXT NOT NULL CHECK(icon IN ('fund','groceries','repairs','shopping','event')),
    status TEXT NOT NULL DEFAULT 'active'
      CHECK(status IN ('active','settlementPending','completed','cancelled'))
  )''');
  await db.execute('''CREATE TABLE managed_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    fund_id INTEGER NOT NULL REFERENCES managed_funds(id),
    kind TEXT NOT NULL CHECK(kind IN (
      'funding','fundingReversal','purchase','purchaseReversal','refund','refundReversal',
      'reimburseDirect','reimburseCash','reimbursementReversal')),
    target_id INTEGER,
    cash_minor INTEGER NOT NULL CHECK(cash_minor BETWEEN 0 AND 99999999999),
    personal_minor INTEGER NOT NULL CHECK(personal_minor BETWEEN 0 AND 99999999999),
    occurred_at INTEGER NOT NULL,
    party TEXT NOT NULL,
    method TEXT NOT NULL,
    note TEXT NOT NULL,
    UNIQUE(fund_id,id),
    FOREIGN KEY(fund_id,target_id) REFERENCES managed_events(fund_id,id),
    CHECK(cash_minor+personal_minor BETWEEN 1 AND 99999999999)
  )''');
  await db.execute(
    'CREATE INDEX idx_managed_event_fund ON managed_events(fund_id,id)',
  );
  await db.execute(
    '''CREATE UNIQUE INDEX idx_managed_event_replacement
    ON managed_events(target_id) WHERE kind IN ('funding','purchase') AND target_id IS NOT NULL''',
  );
  await db.execute('''CREATE TABLE managed_purchase_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL REFERENCES managed_events(id),
    name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
    category TEXT NOT NULL,
    quantity_milli INTEGER CHECK(quantity_milli BETWEEN 1 AND 999999999),
    unit TEXT NOT NULL,
    unit_minor INTEGER CHECK(unit_minor BETWEEN 1 AND 99999999999),
    total_minor INTEGER NOT NULL CHECK(total_minor BETWEEN 1 AND 99999999999),
    CHECK((quantity_milli IS NULL AND unit_minor IS NULL AND unit='')
       OR (quantity_milli IS NOT NULL AND unit_minor IS NOT NULL AND length(trim(unit))>0))
  )''');
  await db.execute(
    'CREATE INDEX idx_managed_item_event ON managed_purchase_items(event_id,id)',
  );
  await db.execute('''CREATE TABLE managed_receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id INTEGER NOT NULL REFERENCES managed_events(id),
    name TEXT NOT NULL,
    data TEXT NOT NULL CHECK(length(data) BETWEEN 4 AND 2796204),
    sha256 TEXT NOT NULL CHECK(length(sha256)=64),
    UNIQUE(event_id,sha256)
  )''');
  await db.execute('''CREATE TABLE managed_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_key TEXT NOT NULL UNIQUE CHECK(length(request_key) BETWEEN 1 AND 128),
    fingerprint TEXT NOT NULL CHECK(length(fingerprint)=64),
    fund_id INTEGER NOT NULL,
    event_id INTEGER NOT NULL,
    FOREIGN KEY(fund_id,event_id) REFERENCES managed_events(fund_id,id)
  )''');
  await db.execute('''CREATE TRIGGER managed_currency_fixed
    BEFORE UPDATE OF currency ON managed_funds WHEN OLD.currency<>NEW.currency
    BEGIN SELECT RAISE(ABORT,'Managed fund currency is fixed'); END''');
  await db.execute(
    '''CREATE TRIGGER managed_event_no_update BEFORE UPDATE ON managed_events
    BEGIN SELECT RAISE(ABORT,'Append a correction to the managed journal'); END''',
  );
  await db.execute(
    '''CREATE TRIGGER managed_event_no_delete BEFORE DELETE ON managed_events
    BEGIN SELECT RAISE(ABORT,'Reverse the managed event and keep its history'); END''',
  );
  await db.execute(
    '''CREATE TRIGGER managed_item_no_update BEFORE UPDATE ON managed_purchase_items
    BEGIN SELECT RAISE(ABORT,'Record a replacement purchase to correct items'); END''',
  );
  await db.execute(
    '''CREATE TRIGGER managed_item_no_delete BEFORE DELETE ON managed_purchase_items
    BEGIN SELECT RAISE(ABORT,'Reverse the purchase and keep its items'); END''',
  );
}
