import 'package:sqflite/sqflite.dart';

/// Called inside sqflite's atomic version upgrade transaction. Additive only:
/// old transactions remain unassigned, retaining amounts, IDs and wallet links.
Future<void> migrateProjectsV3(Database db) async {
  await db.execute('''CREATE TABLE projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
    description TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL CHECK(type IN ('personal','business')),
    client_name TEXT NOT NULL DEFAULT '', currency TEXT NOT NULL,
    budget_minor INTEGER CHECK(budget_minor >= 0 AND budget_minor <= 99999999999),
    contract_minor INTEGER CHECK(contract_minor >= 0 AND contract_minor <= 99999999999),
    start_date INTEGER NOT NULL, deadline INTEGER,
    status TEXT NOT NULL CHECK(status IN ('planned','active','onHold','completed','archived')),
    archived_from TEXT CHECK(archived_from IN ('planned','active','onHold','completed')),
    color INTEGER NOT NULL DEFAULT 4279282049, icon TEXT NOT NULL DEFAULT 'folder',
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    CHECK(deadline IS NULL OR deadline >= start_date),
    CHECK(type='business' OR contract_minor IS NULL)
  )''');
  await db.execute('''CREATE TABLE project_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id),
    name TEXT NOT NULL COLLATE NOCASE CHECK(length(trim(name)) BETWEEN 1 AND 60),
    UNIQUE(project_id,name)
  )''');
  await db.execute('''CREATE TABLE project_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL REFERENCES projects(id),
    amount_minor INTEGER NOT NULL CHECK(amount_minor > 0 AND amount_minor <= 99999999999),
    note TEXT NOT NULL DEFAULT '', occurred_at INTEGER NOT NULL
  )''');
  await db.execute('ALTER TABLE transactions ADD COLUMN project_id INTEGER REFERENCES projects(id)');
  await db.execute('ALTER TABLE transactions ADD COLUMN project_category_id INTEGER REFERENCES project_categories(id)');
  await db.execute('ALTER TABLE transactions ADD COLUMN project_amount_minor INTEGER');
  await db.execute('ALTER TABLE transactions ADD COLUMN project_currency TEXT');
  await db.execute('ALTER TABLE transactions ADD COLUMN project_rate TEXT');
  await db.execute('ALTER TABLE transactions ADD COLUMN client_receipt INTEGER NOT NULL DEFAULT 0 CHECK(client_receipt IN (0,1))');
  await db.execute('ALTER TABLE transactions ADD COLUMN payment_reference TEXT');
  await db.execute('CREATE INDEX idx_tx_project ON transactions(project_id,occurred_at DESC)');
  await db.execute('CREATE INDEX idx_allocations_project ON project_allocations(project_id,occurred_at DESC)');
  await db.execute('''CREATE UNIQUE INDEX idx_client_payment_reference
    ON transactions(project_id,payment_reference COLLATE NOCASE)
    WHERE client_receipt=1''');
  await db.execute('''CREATE UNIQUE INDEX idx_wallet_client_payment_reference
    ON transactions(wallet_id,payment_reference COLLATE NOCASE)
    WHERE client_receipt=1''');
  await db.execute('CREATE INDEX idx_project_status ON projects(status,type)');
  await db.execute('''CREATE TRIGGER project_currency_immutable
    BEFORE UPDATE OF currency ON projects WHEN NEW.currency != OLD.currency
    BEGIN SELECT RAISE(ABORT, 'Project currency cannot change'); END''');
  await db.execute('''CREATE TRIGGER project_type_receipts
    BEFORE UPDATE OF type ON projects WHEN NEW.type='personal'
      AND EXISTS(SELECT 1 FROM transactions WHERE project_id=OLD.id AND client_receipt=1)
    BEGIN SELECT RAISE(ABORT, 'Keep business type while client receipts exist'); END''');
  for (final event in ['INSERT', 'UPDATE']) {
    await db.execute('''CREATE TRIGGER project_tx_validate_${event.toLowerCase()}
      BEFORE $event ON transactions BEGIN
      SELECT CASE WHEN
        (NEW.project_id IS NULL AND (NEW.project_category_id IS NOT NULL
          OR NEW.project_amount_minor IS NOT NULL OR NEW.project_currency IS NOT NULL
          OR NEW.project_rate IS NOT NULL OR NEW.client_receipt != 0
          OR NEW.payment_reference IS NOT NULL))
        OR (NEW.project_id IS NOT NULL AND (
          NOT EXISTS(SELECT 1 FROM projects WHERE id=NEW.project_id
            AND currency=NEW.project_currency AND status != 'archived')
          OR NEW.project_amount_minor IS NULL OR NEW.project_amount_minor <= 0
          OR NEW.project_amount_minor > 99999999999
          OR NEW.project_rate IS NULL OR length(NEW.project_rate)=0
          OR (NEW.currency=NEW.project_currency AND NEW.project_amount_minor != NEW.amount_minor)
          OR (NEW.project_category_id IS NOT NULL AND NOT EXISTS(
            SELECT 1 FROM project_categories WHERE id=NEW.project_category_id AND project_id=NEW.project_id))
        ))
        OR (NEW.client_receipt=1 AND (NEW.type != 'income'
          OR NEW.payment_reference IS NULL OR length(trim(NEW.payment_reference))=0
          OR NEW.payment_reference != trim(NEW.payment_reference)
          OR length(NEW.payment_reference)>100
          OR NOT EXISTS(SELECT 1 FROM projects WHERE id=NEW.project_id AND type='business')))
        OR (NEW.client_receipt=0 AND NEW.payment_reference IS NOT NULL)
        THEN RAISE(ABORT, 'Invalid project assignment or client receipt') END;
      END''');
    await db.execute('''CREATE TRIGGER allocation_validate_${event.toLowerCase()}
      BEFORE $event ON project_allocations BEGIN
      SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM projects
        WHERE id=NEW.project_id AND type='personal' AND status != 'archived')
        THEN RAISE(ABORT, 'Allocations require an active personal project') END;
      END''');
  }
  await db.execute('''CREATE TRIGGER project_type_allocations
    BEFORE UPDATE OF type ON projects WHEN NEW.type='business'
      AND EXISTS(SELECT 1 FROM project_allocations WHERE project_id=OLD.id)
    BEGIN SELECT RAISE(ABORT, 'Keep personal type while allocations exist'); END''');
  await db.execute('''CREATE TRIGGER category_project_immutable
    BEFORE UPDATE OF project_id ON project_categories WHEN NEW.project_id != OLD.project_id
    BEGIN SELECT RAISE(ABORT, 'Category project cannot change'); END''');
}
