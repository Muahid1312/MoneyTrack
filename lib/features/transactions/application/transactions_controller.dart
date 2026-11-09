import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/transaction.dart';
import '../../../data/repositories/providers.dart';
import '../../../data/repositories/transaction_repository.dart';

/// Single source of truth for all stored transactions. Every screen derives
/// from this, so any change updates the dashboard, lists and charts at once.
final transactionsProvider =
    AsyncNotifierProvider<TransactionsController, List<TransactionModel>>(
        TransactionsController.new);

/// Synchronous view used by derived providers (empty while loading).
final allTransactionsProvider = Provider<List<TransactionModel>>(
  (ref) => ref.watch(transactionsProvider).valueOrNull ?? const [],
);

/// The most recently inserted/edited transaction, used to play the
/// insertion highlight animation shortly after a change.
typedef ChangeMarker = ({int id, DateTime at});

final lastChangedTransactionProvider = StateProvider<ChangeMarker?>((ref) => null);

/// Whether [id] was just inserted or edited (within the last few seconds).
bool isFreshChange(ChangeMarker? marker, int? id) =>
    marker != null &&
    id != null &&
    marker.id == id &&
    DateTime.now().difference(marker.at) < const Duration(seconds: 4);

class TransactionsController extends AsyncNotifier<List<TransactionModel>> {
  final _undoable = <int>{};
  TransactionRepository get _repo => ref.read(transactionRepositoryProvider);

  @override
  Future<List<TransactionModel>> build() async => _sorted(await _repo.fetchAll());

  List<TransactionModel> get _current => state.valueOrNull ?? const [];

  Future<TransactionModel> add(TransactionModel tx) async {
    final saved = await _repo.insert(tx);
    state = AsyncData(_sorted([..._current, saved]));
    ref.read(lastChangedTransactionProvider.notifier).state = (id: saved.id!, at: DateTime.now());
    return saved;
  }

  Future<void> edit(TransactionModel tx) async {
    await _repo.update(tx);
    // Read back normalized conversion snapshots and payment references.
    state = AsyncData(_sorted(await _repo.fetchAll()));
    ref.read(lastChangedTransactionProvider.notifier).state = (id: tx.id!, at: DateTime.now());
  }

  /// Removes and returns the deleted transaction so it can be restored.
  Future<TransactionModel?> remove(int id) async {
    final existing = _current.where((t) => t.id == id).firstOrNull;
    await _repo.delete(id);
    if (existing != null) _undoable.add(id);
    while (_undoable.length > 32) { _undoable.remove(_undoable.first); }
    state = AsyncData(_current.where((t) => t.id != id).toList());
    return existing;
  }

  /// Re-inserts a previously deleted transaction (undo).
  Future<void> restore(TransactionModel tx) async {
    if (!_undoable.contains(tx.id)) throw StateError('Undo is no longer available');
    await add(tx);
    _undoable.remove(tx.id);
  }

  Future<void> clearAll() async {
    await _repo.clear();
    _undoable.clear();
    state = const AsyncData([]);
  }

  static List<TransactionModel> _sorted(List<TransactionModel> list) =>
      [...list]..sort((a, b) {
          final c = b.occurredAt.compareTo(a.occurredAt);
          return c != 0 ? c : (b.id ?? 0).compareTo(a.id ?? 0);
        });
}
