enum TransactionType {
  income('income', 'Income'),
  expense('expense', 'Expense');

  const TransactionType(this.storageKey, this.label);

  final String storageKey;
  final String label;

  bool get isIncome => this == TransactionType.income;
  bool get isExpense => this == TransactionType.expense;

  static TransactionType fromStorage(String value) =>
      values.firstWhere((t) => t.storageKey == value,
          orElse: () => TransactionType.expense);
}
