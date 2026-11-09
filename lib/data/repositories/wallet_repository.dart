import '../storage/access_guard.dart';
import '../../core/constants/currency.dart';
import '../../features/wallets/domain/exchange_rate.dart';
import '../database/app_database.dart';
import '../models/planning.dart';
import '../models/wallet.dart';

class WalletSnapshot {
  const WalletSnapshot(this.wallets, this.balances, this.transfers, {this.reserved = const {}, this.debtPostings = const []});
  final List<Wallet> wallets;
  final Map<int, int> balances;
  final List<WalletTransfer> transfers;
  final Map<int,int> reserved;
  final List<DebtPosting> debtPostings;
  int available(int id) => (balances[id] ?? 0)-(reserved[id] ?? 0);
}

class WalletRepository {
  WalletRepository(this.database);
  final AppDatabase database;

  /// Read the entire ledger in one snapshot; balances are derived, never cached
  /// in the database, so financial edits/deletions cannot leave stale balances.
  Future<WalletSnapshot> fetch() => database.db.transaction((txn) async {
    final wallets = (await txn.query('wallets', orderBy: 'id'))
        .map(Wallet.fromMap).toList();
    final transfers = (await txn.query('transfers', orderBy: 'occurred_at DESC, id DESC'))
        .map(WalletTransfer.fromMap).toList();
    final positions = await txn.query('wallet_positions');
    final balances = {for(final p in positions) p['id'] as int:p['balance'] as int};
    final reserved = {for(final p in positions) p['id'] as int:p['reserved'] as int};
    final postings = (await txn.query('debt_postings',orderBy:'occurred_at DESC,id DESC')).map(DebtPosting.new).toList();
    return WalletSnapshot(wallets, balances, transfers, reserved:reserved, debtPostings:postings);
  });

  Future<void> save(Wallet wallet) async {
    if (wallet.name.trim().isEmpty || wallet.name.trim().length > 80 ||
        wallet.openingMinor.abs() > AppInfo.maxAmountMinor) {
      throw ArgumentError('Enter a wallet name and a valid opening balance');
    }
    await database.db.transaction((txn) async {
    AccessGuard.writable();
      if (wallet.id == null) {
        await txn.insert('wallets', wallet.toMap());
      } else {
        final count = await txn.update('wallets', wallet.toMap(),
            where: 'id = ?', whereArgs: [wallet.id]);
        if (count != 1) throw StateError('Wallet no longer exists');
      }
    });
  }

  Future<void> transfer({required int sourceId, required int destinationId,
      required int sourceMinor, required String rate, required DateTime occurredAt,
      String note = ''}) => database.db.transaction((txn) async {
    AccessGuard.writable();
    if (sourceId == destinationId) throw ArgumentError('Choose different wallets');
    Future<Wallet> get(int id) async {
      final rows = await txn.query('wallets', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw ArgumentError('Wallet does not exist');
      final w = Wallet.fromMap(rows.single);
      if (w.archived) throw ArgumentError('Archived wallets cannot transfer money');
      return w;
    }
    final source = await get(sourceId);
    final destination = await get(destinationId);
    final position = (await txn.query('wallet_positions',where:'id=?',whereArgs:[sourceId])).single;
    if (sourceMinor > (position['balance'] as int)-(position['reserved'] as int)) {
      throw ArgumentError('Insufficient available funds in source wallet');
    }
    final exchange = ExchangeRate.parse(rate);
    if (source.currency == destination.currency &&
        exchange.numerator != exchange.denominator) {
      throw ArgumentError('Same-currency transfers require a rate of 1');
    }
    final received = exchange.convert(sourceMinor, source.currency, destination.currency);
    await txn.insert('transfers', WalletTransfer(
      sourceId: sourceId, destinationId: destinationId,
      sourceMinor: sourceMinor, destinationMinor: received, rate: exchange.text,
      sourceCurrency: source.currency, destinationCurrency: destination.currency,
      occurredAt: occurredAt, note: note.trim(),
    ).toMap());
  });

  Future<void> deleteTransfer(int id) async {
    AccessGuard.writable();
    await database.db.delete('transfers', where: 'id = ?', whereArgs: [id]);
  }
}
