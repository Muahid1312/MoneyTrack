import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/constants/currency.dart';
import 'planning_migration.dart';
import 'documents_migration.dart';
import 'project_migration.dart';

class AppDatabase {
  AppDatabase._(this.db);
  final Database db;
  static const schemaVersion = 5;
  static const transactionsTable = 'transactions';

  /// sqflite runs onCreate/onUpgrade in a transaction. A failed migration
  /// rolls back both the data changes and user_version; the old file survives.
  static Future<AppDatabase> open({DatabaseFactory? factory, String? path,
      AppCurrency legacyCurrency = AppCurrency.usd}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? p.join(await f.getDatabasesPath(), 'moneytrack.db');
    final db = await f.openDatabase(file, options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createLegacy(db);
        await _upgradeV2(db, legacyCurrency);
        await migrateProjectsV3(db);
        await migratePlanningV4(db);
        await migrateDocumentsV5(db);
      },
      onOpen: (db) => db.execute('CREATE INDEX IF NOT EXISTS idx_tx_history_order ON transactions(occurred_at DESC,id DESC)'),
      onUpgrade: (db, old, next) async {
        if (old < 1 || old > 4) throw StateError('Unsupported database version: $old');
        if (old < 2) await _upgradeV2(db, legacyCurrency);
        if (old < 3) await migrateProjectsV3(db);
        if (old < 4) await migratePlanningV4(db);
        if (old < 5) await migrateDocumentsV5(db);
      },
    ));
    return AppDatabase._(db);
  }

  static Future<void> _createLegacy(Database db) => db.execute('''
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
      category_id TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
      occurred_at INTEGER NOT NULL, created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  static Future<void> _upgradeV2(Database db, AppCurrency currency) async {
    await db.execute('''CREATE TABLE wallets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL CHECK (length(trim(name)) > 0),
      type TEXT NOT NULL CHECK(type IN ('cash','bank','mobileMoney','savings','other')),
      currency TEXT NOT NULL,
      opening_minor INTEGER NOT NULL CHECK(abs(opening_minor) <= 99999999999),
      archived INTEGER NOT NULL DEFAULT 0 CHECK(archived IN (0,1))
    )''');
    await db.insert('wallets', {'id': 1, 'name': 'Main wallet', 'type': 'cash',
      'currency': currency.code, 'opening_minor': 0});
    // Keep the original table and every original ID, note, category and date.
    // SQLite forbids a non-null REFERENCES default when existing rows exist.
    // Backfill first; the validation triggers below enforce a wallet on every write.
    await db.execute('ALTER TABLE transactions ADD COLUMN wallet_id INTEGER REFERENCES wallets(id)');
    await db.execute('UPDATE transactions SET wallet_id = 1');
    await db.execute('ALTER TABLE transactions ADD COLUMN currency TEXT NOT NULL DEFAULT \'${currency.code}\'');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_tx_occurred_at ON transactions (occurred_at DESC)');
    await db.execute('CREATE INDEX idx_tx_wallet ON transactions(wallet_id, occurred_at DESC)');
    await db.execute('''CREATE TABLE transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id INTEGER NOT NULL REFERENCES wallets(id),
      destination_id INTEGER NOT NULL REFERENCES wallets(id),
      source_minor INTEGER NOT NULL CHECK(source_minor > 0 AND source_minor <= 99999999999),
      destination_minor INTEGER NOT NULL CHECK(destination_minor > 0 AND destination_minor <= 99999999999),
      source_currency TEXT NOT NULL, destination_currency TEXT NOT NULL,
      rate TEXT NOT NULL CHECK(length(rate) > 0),
      note TEXT NOT NULL DEFAULT '', occurred_at INTEGER NOT NULL,
      CHECK(source_id != destination_id)
    )''');
    for (final event in ['INSERT', 'UPDATE']) {
      await db.execute('''CREATE TRIGGER tx_validate_${event.toLowerCase()}
        BEFORE $event ON transactions BEGIN
        SELECT CASE WHEN NEW.amount_minor <= 0 OR NEW.amount_minor > 99999999999
          OR NOT EXISTS(SELECT 1 FROM wallets WHERE id=NEW.wallet_id
            AND currency=NEW.currency AND archived=0)
          THEN RAISE(ABORT, 'Invalid transaction wallet, currency or amount') END;
        END''');
      await db.execute('''CREATE TRIGGER transfer_validate_${event.toLowerCase()}
        BEFORE $event ON transfers BEGIN
        SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM wallets
          WHERE id=NEW.source_id AND currency=NEW.source_currency AND archived=0)
          OR NOT EXISTS(SELECT 1 FROM wallets
          WHERE id=NEW.destination_id AND currency=NEW.destination_currency AND archived=0)
          THEN RAISE(ABORT, 'Invalid transfer wallets or currencies') END;
        END''');
    }
    await db.execute('''CREATE TRIGGER wallet_currency_immutable
      BEFORE UPDATE OF currency ON wallets WHEN NEW.currency != OLD.currency
      BEGIN SELECT RAISE(ABORT, 'Wallet currency cannot change'); END''');
  }

  Future<void> close() => db.close();
}
