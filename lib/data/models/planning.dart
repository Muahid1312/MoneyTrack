import '../../core/constants/currency.dart';
import '../../features/planning/domain/schedule.dart';

class Debt {
  const Debt(this.row, this.repaidMinor);
  final Map<String, Object?> row;
  final int repaidMinor;
  int get id => row['id'] as int;
  String get contact => row['contact'] as String;
  bool get borrowed => row['type']=='borrowed';
  int get principalMinor => row['principal_minor'] as int;
  int get remainingMinor => principalMinor-repaidMinor;
  AppCurrency get currency => AppCurrency.requireCode(row['currency'] as String);
  String? get dueDate => row['due_date'] as String?;
  String get note => row['note'] as String;
  String status(DateTime now) => remainingMinor==0 ? 'Settled'
    : dueDate!=null && dueDate!.compareTo(CivilSchedule.key(now))<0 ? 'Overdue'
    : repaidMinor>0 ? 'Partially paid' : 'Active';
}
class DebtPosting {
  const DebtPosting(this.row);
  final Map<String, Object?> row;
  int get id => row['id'] as int;
  int get debtId => row['debt_id'] as int;
  int get walletId => row['wallet_id'] as int;
  int get principalMinor => row['principal_minor'] as int;
  int get walletMinor => row['wallet_minor'] as int;
  int get signedMinor => walletMinor*(row['direction'] as int);
  AppCurrency get currency => AppCurrency.requireCode(row['currency'] as String);
  bool get origin => row['kind']=='origin';
  bool get voided => row['voided']==1;
  String get reference => row['reference'] as String;
  String get rate => row['rate'] as String;
  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(row['occurred_at'] as int);
}
class SavingsGoal {
  const SavingsGoal(this.row,this.allocatedMinor);
  final Map<String, Object?> row;
  final int allocatedMinor;
  int get id => row['id'] as int;
  String get name => row['name'] as String;
  int get walletId => row['wallet_id'] as int;
  int get targetMinor => row['target_minor'] as int;
  AppCurrency get currency => AppCurrency.requireCode(row['currency'] as String);
  String? get targetDate => row['target_date'] as String?;
  String get status => row['status'] as String;
  double get progress => allocatedMinor/targetMinor; // Display geometry only.
}
class RecurringRule {
  const RecurringRule(this.row);
  final Map<String,Object?> row;
  int get id => row['id'] as int;
  String get name => row['name'] as String;
  String get state => row['state'] as String;
  int get amountMinor => row['amount_minor'] as int;
  int get walletId => row['wallet_id'] as int;
  AppCurrency get currency => AppCurrency.requireCode(row['currency'] as String);
  String get nextDate => row['next_date'] as String;
  String? get endDate => row['end_date'] as String?;
  bool get automatic => row['automatic']==1;
  bool get finished => endDate!=null && nextDate.compareTo(endDate!)>0;
}
class RecurringOccurrence {
  const RecurringOccurrence(this.row);
  final Map<String,Object?> row;
  int get id => row['id'] as int;
  int get ruleId => row['rule_id'] as int;
  String get dueDate => row['due_date'] as String;
  String get status => row['status'] as String;
  String? get error => row['error'] as String?;
  int? get transactionId => row['transaction_id'] as int?;
}
class PlanningSnapshot {
  const PlanningSnapshot({required this.debts,required this.postings,required this.goals,
    required this.savingsEvents,required this.rules,required this.occurrences});
  final List<Debt> debts;
  final List<DebtPosting> postings;
  final List<SavingsGoal> goals;
  final List<Map<String,Object?>> savingsEvents;
  final List<RecurringRule> rules;
  final List<RecurringOccurrence> occurrences;
}
