import 'package:sqflite/sqflite.dart';

Future<void> migratePlanningV4(Database db) async {
  await db.execute('''CREATE TABLE debts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, contact TEXT NOT NULL CHECK(length(trim(contact)) BETWEEN 1 AND 100),
    type TEXT NOT NULL CHECK(type IN ('borrowed','lent')),
    principal_minor INTEGER NOT NULL CHECK(principal_minor>0 AND principal_minor<=99999999999),
    currency TEXT NOT NULL, created_at INTEGER NOT NULL, due_date TEXT,
    note TEXT NOT NULL DEFAULT ''
  )''');
  await db.execute('''CREATE TABLE debt_postings (
    id INTEGER PRIMARY KEY AUTOINCREMENT, debt_id INTEGER NOT NULL REFERENCES debts(id),
    wallet_id INTEGER NOT NULL REFERENCES wallets(id), kind TEXT NOT NULL CHECK(kind IN ('origin','repayment')),
    wallet_minor INTEGER NOT NULL CHECK(wallet_minor>0 AND wallet_minor<=99999999999),
    principal_minor INTEGER NOT NULL CHECK(principal_minor>0 AND principal_minor<=99999999999),
    currency TEXT NOT NULL, rate TEXT NOT NULL, direction INTEGER NOT NULL CHECK(direction IN (-1,1)),
    reference TEXT NOT NULL CHECK(length(trim(reference)) BETWEEN 1 AND 100),
    occurred_at INTEGER NOT NULL, voided INTEGER NOT NULL DEFAULT 0 CHECK(voided IN (0,1)),
    UNIQUE(debt_id,reference COLLATE NOCASE), UNIQUE(wallet_id,reference COLLATE NOCASE)
  )''');
  await db.execute("CREATE UNIQUE INDEX idx_debt_origin ON debt_postings(debt_id) WHERE kind='origin'");
  await db.execute('''CREATE TABLE savings_goals (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
    wallet_id INTEGER NOT NULL REFERENCES wallets(id), currency TEXT NOT NULL,
    target_minor INTEGER NOT NULL CHECK(target_minor>0 AND target_minor<=99999999999),
    target_date TEXT, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','completed','archived')),
    color INTEGER NOT NULL DEFAULT 4279282049, icon TEXT NOT NULL DEFAULT 'savings', created_at INTEGER NOT NULL
  )''');
  await db.execute('''CREATE TABLE savings_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, goal_id INTEGER NOT NULL REFERENCES savings_goals(id),
    delta_minor INTEGER NOT NULL CHECK(delta_minor!=0 AND abs(delta_minor)<=99999999999),
    reference TEXT NOT NULL CHECK(length(trim(reference)) BETWEEN 1 AND 100),
    occurred_at INTEGER NOT NULL, UNIQUE(goal_id,reference)
  )''');
  await db.execute('''CREATE TABLE recurring_rules (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
    type TEXT NOT NULL CHECK(type IN ('income','expense')), amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=99999999999),
    currency TEXT NOT NULL, wallet_id INTEGER NOT NULL REFERENCES wallets(id), category_id TEXT NOT NULL,
    project_id INTEGER REFERENCES projects(id), project_rate TEXT,
    frequency TEXT NOT NULL CHECK(frequency IN ('daily','weekly','monthly','yearly')),
    start_date TEXT NOT NULL, end_date TEXT, next_date TEXT NOT NULL, next_index INTEGER NOT NULL DEFAULT 0 CHECK(next_index>=0),
    state TEXT NOT NULL DEFAULT 'active' CHECK(state IN ('active','paused','cancelled')),
    automatic INTEGER NOT NULL DEFAULT 0 CHECK(automatic IN (0,1)),
    created_at INTEGER NOT NULL, CHECK(end_date IS NULL OR end_date>=start_date)
  )''');
  await db.execute('ALTER TABLE transactions ADD COLUMN recurring_rule_id INTEGER REFERENCES recurring_rules(id)');
  await db.execute('ALTER TABLE transactions ADD COLUMN occurrence_date TEXT');
  await db.execute('''CREATE UNIQUE INDEX idx_recurring_transaction ON transactions(recurring_rule_id,occurrence_date)
    WHERE recurring_rule_id IS NOT NULL''');
  await db.execute('''CREATE TABLE recurring_occurrences (
    id INTEGER PRIMARY KEY AUTOINCREMENT, rule_id INTEGER NOT NULL REFERENCES recurring_rules(id),
    due_date TEXT NOT NULL, payload TEXT NOT NULL, automatic INTEGER NOT NULL CHECK(automatic IN (0,1)),
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','recorded','skipped')),
    transaction_id INTEGER UNIQUE REFERENCES transactions(id) ON DELETE SET NULL,
    error TEXT, UNIQUE(rule_id,due_date)
  )''');
  await db.execute('CREATE INDEX idx_recurring_due ON recurring_rules(state,next_date)');
  await db.execute('CREATE INDEX idx_occurrence_pending ON recurring_occurrences(status,due_date)');
  await db.execute('CREATE INDEX idx_debt_postings ON debt_postings(debt_id,voided)');
  await db.execute('CREATE INDEX idx_savings_goal ON savings_events(goal_id)');
  await db.execute('''CREATE VIEW wallet_positions AS SELECT w.id,
    w.opening_minor +
    COALESCE((SELECT SUM(CASE WHEN type='income' THEN amount_minor ELSE -amount_minor END) FROM transactions WHERE wallet_id=w.id),0) +
    COALESCE((SELECT SUM(destination_minor) FROM transfers WHERE destination_id=w.id),0) -
    COALESCE((SELECT SUM(source_minor) FROM transfers WHERE source_id=w.id),0) +
    COALESCE((SELECT SUM(direction*wallet_minor) FROM debt_postings WHERE wallet_id=w.id AND voided=0),0) AS balance,
    COALESCE((SELECT SUM(e.delta_minor) FROM savings_events e JOIN savings_goals g ON e.goal_id=g.id WHERE g.wallet_id=w.id),0) AS reserved
    FROM wallets w''');
  await db.execute('''CREATE TRIGGER debt_posting_validate BEFORE INSERT ON debt_postings BEGIN
    SELECT CASE WHEN NEW.voided!=0 OR NOT EXISTS(SELECT 1 FROM wallets WHERE id=NEW.wallet_id AND archived=0 AND currency=NEW.currency)
      OR NOT EXISTS(SELECT 1 FROM debts WHERE id=NEW.debt_id AND NEW.direction=CASE
        WHEN (type='borrowed' AND NEW.kind='origin') OR (type='lent' AND NEW.kind='repayment') THEN 1 ELSE -1 END)
      OR (NEW.kind='origin' AND NOT EXISTS(SELECT 1 FROM debts WHERE id=NEW.debt_id AND currency=NEW.currency
        AND principal_minor=NEW.principal_minor AND NEW.principal_minor=NEW.wallet_minor AND NEW.rate='1'))
      OR (NEW.kind='repayment' AND (NOT EXISTS(SELECT 1 FROM debt_postings WHERE debt_id=NEW.debt_id AND kind='origin')
        OR NEW.principal_minor>(SELECT principal_minor FROM debts WHERE id=NEW.debt_id)-
          COALESCE((SELECT SUM(principal_minor) FROM debt_postings WHERE debt_id=NEW.debt_id AND kind='repayment' AND voided=0),0)))
      OR (NEW.direction=-1 AND NEW.wallet_minor>(SELECT balance-reserved FROM wallet_positions WHERE id=NEW.wallet_id))
      THEN RAISE(ABORT,'Invalid debt posting, insufficient available funds or overpayment') END;
    END''');
  await db.execute('''CREATE TRIGGER debt_posting_void BEFORE UPDATE ON debt_postings BEGIN
    SELECT CASE WHEN OLD.kind!='repayment' OR OLD.voided!=0 OR NEW.voided!=1
      OR NEW.debt_id!=OLD.debt_id OR NEW.wallet_id!=OLD.wallet_id OR NEW.kind!=OLD.kind
      OR NEW.wallet_minor!=OLD.wallet_minor OR NEW.principal_minor!=OLD.principal_minor
      OR NEW.currency!=OLD.currency OR NEW.rate!=OLD.rate OR NEW.direction!=OLD.direction
      OR NEW.reference!=OLD.reference OR NEW.occurred_at!=OLD.occurred_at
      OR (OLD.direction=1 AND OLD.wallet_minor>(SELECT balance-reserved FROM wallet_positions WHERE id=OLD.wallet_id))
      THEN RAISE(ABORT,'Debt postings are immutable; void only an affordable repayment') END;
    END''');
  await db.execute('''CREATE TRIGGER debt_financial_immutable BEFORE UPDATE ON debts
    WHEN NEW.type!=OLD.type OR NEW.principal_minor!=OLD.principal_minor OR NEW.currency!=OLD.currency OR NEW.created_at!=OLD.created_at
    BEGIN SELECT RAISE(ABORT,'Debt principal and type are immutable'); END''');
  await db.execute('''CREATE TRIGGER savings_goal_wallet BEFORE INSERT ON savings_goals BEGIN
    SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM wallets WHERE id=NEW.wallet_id AND currency=NEW.currency AND archived=0)
      THEN RAISE(ABORT,'Choose an active wallet in the goal currency') END;
    END''');
  await db.execute('''CREATE TRIGGER savings_goal_update BEFORE UPDATE ON savings_goals BEGIN
    SELECT CASE WHEN NEW.wallet_id!=OLD.wallet_id OR NEW.currency!=OLD.currency
      OR (NEW.status='completed' AND NEW.target_minor>COALESCE((SELECT SUM(delta_minor) FROM savings_events WHERE goal_id=OLD.id),0))
      THEN RAISE(ABORT,'Goal wallet/currency are fixed; fund the target before completion') END;
    END''');
  await db.execute('''CREATE TRIGGER savings_event_validate BEFORE INSERT ON savings_events BEGIN
    SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM savings_goals g JOIN wallets w ON w.id=g.wallet_id
      WHERE g.id=NEW.goal_id AND g.status!='archived' AND w.archived=0)
      OR COALESCE((SELECT SUM(delta_minor) FROM savings_events WHERE goal_id=NEW.goal_id),0)+NEW.delta_minor<0
      OR (NEW.delta_minor>0 AND NEW.delta_minor>(SELECT balance-reserved FROM wallet_positions
        WHERE id=(SELECT wallet_id FROM savings_goals WHERE id=NEW.goal_id)))
      THEN RAISE(ABORT,'Insufficient available or reserved savings funds') END;
    END''');
  await db.execute('''CREATE TRIGGER savings_reopen AFTER INSERT ON savings_events BEGIN
    UPDATE savings_goals SET status='active' WHERE id=NEW.goal_id AND status='completed'
      AND target_minor>COALESCE((SELECT SUM(delta_minor) FROM savings_events WHERE goal_id=NEW.goal_id),0);
    END''');
  await db.execute('''CREATE TRIGGER savings_event_immutable BEFORE UPDATE ON savings_events
    BEGIN SELECT RAISE(ABORT,'Savings history is immutable; record a withdrawal instead'); END''');
  await db.execute('''CREATE TRIGGER reserve_tx_insert BEFORE INSERT ON transactions
    WHEN (SELECT reserved FROM wallet_positions WHERE id=NEW.wallet_id)>0
      AND (SELECT balance-reserved FROM wallet_positions WHERE id=NEW.wallet_id)+CASE WHEN NEW.type='income' THEN NEW.amount_minor ELSE -NEW.amount_minor END<0
    BEGIN SELECT RAISE(ABORT,'Transaction would spend reserved savings'); END''');
  await db.execute('''CREATE TRIGGER reserve_tx_update BEFORE UPDATE ON transactions BEGIN
    SELECT CASE WHEN ((SELECT reserved FROM wallet_positions WHERE id=OLD.wallet_id)>0
      AND (SELECT balance-reserved FROM wallet_positions WHERE id=OLD.wallet_id)-CASE WHEN OLD.type='income' THEN OLD.amount_minor ELSE -OLD.amount_minor END+
        CASE WHEN NEW.wallet_id=OLD.wallet_id THEN CASE WHEN NEW.type='income' THEN NEW.amount_minor ELSE -NEW.amount_minor END ELSE 0 END<0)
      OR (NEW.wallet_id!=OLD.wallet_id AND (SELECT reserved FROM wallet_positions WHERE id=NEW.wallet_id)>0
        AND (SELECT balance-reserved FROM wallet_positions WHERE id=NEW.wallet_id)+CASE WHEN NEW.type='income' THEN NEW.amount_minor ELSE -NEW.amount_minor END<0)
      THEN RAISE(ABORT,'Edit would spend reserved savings') END;
    END''');
  await db.execute('''CREATE TRIGGER reserve_tx_delete BEFORE DELETE ON transactions
    WHEN OLD.type='income' AND (SELECT reserved FROM wallet_positions WHERE id=OLD.wallet_id)>0
      AND (SELECT balance-reserved FROM wallet_positions WHERE id=OLD.wallet_id)<OLD.amount_minor
    BEGIN SELECT RAISE(ABORT,'Release reserved savings before deleting this income'); END''');
  await db.execute('''CREATE TRIGGER reserve_wallet_update BEFORE UPDATE ON wallets
    WHEN (SELECT reserved FROM wallet_positions WHERE id=OLD.id)>0 AND
      (NEW.archived=1 OR (SELECT balance-reserved FROM wallet_positions WHERE id=OLD.id)+NEW.opening_minor-OLD.opening_minor<0)
    BEGIN SELECT RAISE(ABORT,'Release reserved savings before changing this wallet'); END''');
  await db.execute('''CREATE TRIGGER reserve_transfer_insert BEFORE INSERT ON transfers
    WHEN NEW.source_minor>(SELECT balance-reserved FROM wallet_positions WHERE id=NEW.source_id)
    BEGIN SELECT RAISE(ABORT,'Insufficient available funds for transfer'); END''');
  await db.execute('''CREATE TRIGGER reserve_transfer_delete BEFORE DELETE ON transfers
    WHEN (SELECT reserved FROM wallet_positions WHERE id=OLD.destination_id)>0
      AND OLD.destination_minor>(SELECT balance-reserved FROM wallet_positions WHERE id=OLD.destination_id)
    BEGIN SELECT RAISE(ABORT,'Release reserved savings before reversing transfer'); END''');
  await db.execute('''CREATE TRIGGER transfer_immutable BEFORE UPDATE ON transfers
    BEGIN SELECT RAISE(ABORT,'Transfers are immutable; reverse and record a replacement'); END''');
  await db.execute('''CREATE TRIGGER recurring_link_insert BEFORE INSERT ON transactions
    WHEN (NEW.recurring_rule_id IS NULL)!=(NEW.occurrence_date IS NULL)
      OR (NEW.recurring_rule_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM recurring_occurrences
        WHERE rule_id=NEW.recurring_rule_id AND due_date=NEW.occurrence_date
          AND status IN ('pending','recorded') AND transaction_id IS NULL))
    BEGIN SELECT RAISE(ABORT,'Recurring entries require a rule and stable occurrence date'); END''');
  await db.execute('''CREATE TRIGGER recurring_link_update BEFORE UPDATE ON transactions
    WHEN NEW.recurring_rule_id IS NOT OLD.recurring_rule_id OR NEW.occurrence_date IS NOT OLD.occurrence_date
    BEGIN SELECT RAISE(ABORT,'Recurring occurrence identity is immutable'); END''');
}
