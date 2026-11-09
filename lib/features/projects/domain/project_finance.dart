import '../../../data/models/project.dart';
import '../../../data/models/transaction.dart';

class ProjectCashMonth {
  ProjectCashMonth();
  int receipts = 0;
  int payments = 0;
  int get surplus => receipts - payments;
}

class ProjectSummary {
  const ProjectSummary({required this.receipts, required this.expenses,
    required this.clientReceipts, required this.allocated,
    required this.budgetMinor, required this.contractMinor,
    required this.categoryExpenses, required this.monthly});
  final int receipts, expenses, clientReceipts, allocated;
  final int? budgetMinor, contractMinor;
  final Map<String, int> categoryExpenses;
  final Map<DateTime, ProjectCashMonth> monthly;
  int get cashSurplus => receipts - expenses;
  int get availableAllocation => allocated - expenses;
  int? get remainingBudget => budgetMinor == null ? null : budgetMinor! - expenses;
  bool get overspent => budgetMinor != null && expenses > budgetMinor!;
  // UI percentages and chart geometry only; all monetary values remain integers.
  double? get usage => budgetMinor == null || budgetMinor == 0 ? null : expenses / budgetMinor!;
  int? get outstanding => contractMinor == null ? null :
    (contractMinor! > clientReceipts ? contractMinor! - clientReceipts : 0);
  int get overpayment => contractMinor == null || clientReceipts <= contractMinor!
    ? 0 : clientReceipts - contractMinor!;
}

abstract final class ProjectFinance {
  static ProjectSummary calculate(Project project, Iterable<TransactionModel> transactions,
      Iterable<ProjectAllocation> allocations, Iterable<ProjectCategory> categories) {
    var receipts = 0, expenses = 0, clientReceipts = 0, allocated = 0;
    final categoryNames = {for (final c in categories.where((c) => c.projectId == project.id)) c.id: c.name};
    final byCategory = <String, int>{};
    final monthly = <DateTime, ProjectCashMonth>{};
    for (final t in transactions.where((t) => t.projectId == project.id)) {
      if (t.projectCurrency != project.currency || t.projectAmountMinor == null || t.projectAmountMinor! <= 0) {
        throw StateError('Missing recorded project conversion for transaction ${t.id}');
      }
      final amount = t.projectAmountMinor!;
      final month = DateTime(t.occurredAt.year, t.occurredAt.month);
      final flow = monthly.putIfAbsent(month, ProjectCashMonth.new);
      if (t.type.isIncome) {
        receipts += amount;
        flow.receipts += amount;
        if (t.clientReceipt) clientReceipts += amount;
      } else {
        expenses += amount;
        flow.payments += amount;
        final category = categoryNames[t.projectCategoryId] ?? t.category.name;
        byCategory[category] = (byCategory[category] ?? 0) + amount;
      }
    }
    for (final allocation in allocations.where((a) => a.projectId == project.id)) {
      allocated += allocation.amountMinor;
    }
    return ProjectSummary(receipts: receipts, expenses: expenses,
      clientReceipts: clientReceipts, allocated: allocated,
      budgetMinor: project.budgetMinor, contractMinor: project.contractMinor,
      categoryExpenses: byCategory, monthly: monthly);
  }
}
