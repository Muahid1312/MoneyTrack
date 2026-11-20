import 'package:sqflite/sqflite.dart';

Future<void> migratePersonalFinanceV6(Database db) async {
  await db.execute('''CREATE TABLE wallet_budgets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    period TEXT NOT NULL CHECK(period IN ('daily','weekly','monthly','custom')),
    limit_minor INTEGER NOT NULL CHECK(limit_minor BETWEEN 1 AND 99999999999),
    category_id TEXT, start_date TEXT NOT NULL, end_date TEXT,
    rollover INTEGER NOT NULL CHECK(rollover IN (0,1)),
    CHECK((period='custom' AND end_date IS NOT NULL AND end_date>=start_date AND rollover=0)
       OR (period!='custom' AND end_date IS NULL))
  )''');
  await db.execute(
    'ALTER TABLE savings_goals ADD COLUMN emergency INTEGER NOT NULL DEFAULT 0 CHECK(emergency IN (0,1))',
  );
  await db.execute(
    'ALTER TABLE savings_goals ADD COLUMN weekly_minor INTEGER NOT NULL DEFAULT 0 CHECK(weekly_minor BETWEEN 0 AND 99999999999 AND (emergency=1 OR weekly_minor=0))',
  );
}
