import '../storage/access_guard.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/currency.dart';
import '../../features/wallets/domain/exchange_rate.dart';
import '../database/app_database.dart';
import '../models/transaction.dart';

abstract interface class TransactionRepository {
  Future<List<TransactionModel>> fetchAll();
  Future<TransactionModel> insert(TransactionModel tx);
  Future<void> update(TransactionModel tx);
  Future<void> delete(int id);
  Future<void> clear();
}

class SqfliteTransactionRepository implements TransactionRepository {
  SqfliteTransactionRepository(this._database);
  final AppDatabase _database;
  static const _table = AppDatabase.transactionsTable;
  final _undoAttachments = <int, List<Map<String, Object?>>>{};

  @override
  Future<List<TransactionModel>> fetchAll() async {
    final rows = await _database.db.query(_table, orderBy: 'occurred_at DESC, id DESC');
    return rows.map(TransactionModel.fromMap).toList(growable: false);
  }

  /// Snapshot the explicit rate and rounded project amount on the canonical
  /// wallet transaction. Wallet accounting always uses its original amount.
  Future<TransactionModel> _prepare(DatabaseExecutor db, TransactionModel tx) async {
    if (tx.amountMinor <= 0 || tx.amountMinor > AppInfo.maxAmountMinor) {
      throw ArgumentError('Invalid transaction amount');
    }
    if (tx.projectId == null) {
      if (tx.clientReceipt) throw ArgumentError('Choose a business project for a client receipt');
      return tx.copyWith(projectCategoryId: () => null, projectAmountMinor: () => null,
        projectCurrency: () => null, projectRate: () => null, paymentReference: () => null,
        clientReceipt: false);
    }
    final rows = await db.query('projects', where: 'id=?', whereArgs: [tx.projectId]);
    if (rows.isEmpty || rows.single['status'] == 'archived') {
      throw ArgumentError('Choose an unarchived project');
    }
    final project = rows.single;
    final currency = AppCurrency.requireCode(project['currency'] as String);
    if (tx.clientReceipt && (project['type'] != 'business' || !tx.type.isIncome ||
        ((tx.paymentReference?.trim().isEmpty ?? true) || (tx.paymentReference?.trim().length ?? 0)>100))) {
      throw ArgumentError('Client receipts require a business project, income and a unique payment reference');
    }
    final rate = currency == tx.currency ? ExchangeRate.parse('1')
        : ExchangeRate.parse(tx.projectRate ?? '');
    final converted = rate.convert(tx.amountMinor, tx.currency, currency);
    return tx.copyWith(projectAmountMinor: () => converted,
      projectCurrency: () => currency, projectRate: () => rate.text,
      paymentReference: () => tx.clientReceipt ? tx.paymentReference!.trim().toLowerCase() : null);
  }

  @override
  Future<TransactionModel> insert(TransactionModel tx) async {
    final attachments = _undoAttachments[tx.id];
    final saved = await _database.db.transaction((txn) async {
      final entry = await insertInto(txn, tx, preserveId: attachments != null);
      for (final attachment in attachments ?? <Map<String, Object?>>[]) {
        await txn.insert('attachments', {...attachment, 'transaction_id': entry.id});
      }
      return entry;
    });
    _undoAttachments.remove(tx.id);
    return saved;
  }

  Future<TransactionModel> insertInto(DatabaseExecutor txn, TransactionModel tx, {bool preserveId = false}) async {
    AccessGuard.writable();
    final prepared = await _prepare(txn, tx);
    final map = prepared.toMap();
    if (!preserveId) map.remove('id');
    final id = await txn.insert(_table, map);
    if (prepared.recurringRuleId != null) {
      await txn.update('recurring_occurrences', {'status':'recorded','transaction_id':id,'error':null},
        where:'rule_id=? AND due_date=?',whereArgs:[prepared.recurringRuleId,prepared.occurrenceDate]);
    }
    return prepared.copyWith(id: id);
  }

  @override
  Future<void> update(TransactionModel tx) => _database.db.transaction((txn) async {
    AccessGuard.writable();
    if (tx.id == null) throw ArgumentError('Transaction ID required');
    final prepared = await _prepare(txn, tx);
    final count = await txn.update(_table, prepared.toMap(), where: 'id=?', whereArgs: [tx.id]);
    if (count != 1) throw StateError('Transaction no longer exists');
  });

  @override
  Future<void> delete(int id) async {
    final attachments = await _database.db.transaction((txn) async {
      AccessGuard.writable();
      final rows = await txn.query('attachments', where: 'transaction_id=?', whereArgs: [id]);
      await txn.delete(_table, where: 'id=?', whereArgs: [id]);
      return rows;
    });
    // Bounded, short-lived undo metadata. Private files remain until orphan cleanup.
    _undoAttachments[id] = attachments;
    while (_undoAttachments.length > 32) { _undoAttachments.remove(_undoAttachments.keys.first); }
  }

  @override
  Future<void> clear() => _database.db.transaction((txn) async {
    AccessGuard.writable();
    await txn.delete('savings_events');
    await txn.delete('debt_postings');
    await txn.delete('project_allocations');
    await txn.delete('transfers');
    await txn.delete(_table);
    await txn.delete('recurring_occurrences');
    await txn.delete('recurring_rules');
    await txn.delete('debts');
    await txn.delete('savings_goals');
    await txn.update('wallets', {'opening_minor': 0});
  });
}
