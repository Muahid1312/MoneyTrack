import 'package:flutter/foundation.dart';

import '../../core/constants/categories.dart';
import '../../core/constants/currency.dart';
import '../../features/planning/domain/schedule.dart';
import 'transaction_type.dart';

/// A single income or expense entry. [amountMinor] is always a positive
/// integer in minor units of [currency]; the sign is
/// derived from [type].
@immutable
class TransactionModel {
  const TransactionModel({
    this.id,
    this.walletId = 1,
    this.currency = AppCurrency.usd,
    this.recurringRuleId, this.occurrenceDate,
    this.projectId, this.projectCategoryId, this.projectAmountMinor,
    this.projectCurrency, this.projectRate,
    this.clientReceipt = false, this.paymentReference,
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    this.note = '',
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(amountMinor > 0);

  final int? id;
  final int walletId;
  final int? recurringRuleId;
  final String? occurrenceDate;
  final AppCurrency currency;
  final int? projectId, projectCategoryId, projectAmountMinor;
  final AppCurrency? projectCurrency;
  final String? projectRate, paymentReference;
  final bool clientReceipt;
  final TransactionType type;
  final int amountMinor;
  final String categoryId;
  final String note;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get signedMinor => type.isIncome ? amountMinor : -amountMinor;
  TransactionCategory get category => Categories.byId(categoryId);

  /// Description shown in lists; falls back to the category name.
  String get title => note.trim().isEmpty ? category.name : note.trim();

  TransactionModel copyWith({
    int? id,
    int? walletId,
    AppCurrency? currency,
    int? Function()? projectId,
    int? Function()? projectCategoryId,
    int? Function()? projectAmountMinor,
    AppCurrency? Function()? projectCurrency,
    String? Function()? projectRate,
    bool? clientReceipt,
    String? Function()? paymentReference,
    TransactionType? type,
    int? amountMinor,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      TransactionModel(
        id: id ?? this.id,
        walletId: walletId ?? this.walletId,
        currency: currency ?? this.currency,
        recurringRuleId: recurringRuleId, occurrenceDate: occurrenceDate,
        projectId: projectId == null ? this.projectId : projectId(),
        projectCategoryId: projectCategoryId == null ? this.projectCategoryId : projectCategoryId(),
        projectAmountMinor: projectAmountMinor == null ? this.projectAmountMinor : projectAmountMinor(),
        projectCurrency: projectCurrency == null ? this.projectCurrency : projectCurrency(),
        projectRate: projectRate == null ? this.projectRate : projectRate(),
        clientReceipt: clientReceipt ?? this.clientReceipt,
        paymentReference: paymentReference == null ? this.paymentReference : paymentReference(),
        type: type ?? this.type,
        amountMinor: amountMinor ?? this.amountMinor,
        categoryId: categoryId ?? this.categoryId,
        note: note ?? this.note,
        occurredAt: occurredAt ?? this.occurredAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'wallet_id': walletId,
        'recurring_rule_id': recurringRuleId, 'occurrence_date': occurrenceDate,
        'currency': currency.code,
        'project_id': projectId, 'project_category_id': projectCategoryId,
        'project_amount_minor': projectAmountMinor,
        'project_currency': projectCurrency?.code, 'project_rate': projectRate,
        'client_receipt': clientReceipt ? 1 : 0, 'payment_reference': paymentReference,
        'type': type.storageKey,
        'amount_minor': amountMinor,
        'category_id': categoryId,
        'note': note,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory TransactionModel.fromMap(Map<String, Object?> m) => TransactionModel(
        id: m['id'] as int,
        walletId: m['wallet_id'] as int,
        recurringRuleId: m['recurring_rule_id'] as int?, occurrenceDate: m['occurrence_date'] as String?,
        currency: AppCurrency.requireCode(m['currency'] as String),
        projectId: m['project_id'] as int?, projectCategoryId: m['project_category_id'] as int?,
        projectAmountMinor: m['project_amount_minor'] as int?,
        projectCurrency: m['project_currency'] == null ? null : AppCurrency.requireCode(m['project_currency'] as String),
        projectRate: m['project_rate'] as String?, clientReceipt: m['client_receipt'] == 1,
        paymentReference: m['payment_reference'] as String?,
        type: TransactionType.fromStorage(m['type'] as String),
        amountMinor: m['amount_minor'] as int,
        categoryId: m['category_id'] as String,
        note: (m['note'] as String?) ?? '',
        occurredAt: m['occurrence_date'] == null
          ? DateTime.fromMillisecondsSinceEpoch(m['occurred_at'] as int)
          : CivilSchedule.parse(m['occurrence_date'] as String),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  @override
  bool operator ==(Object other) =>
      other is TransactionModel &&
      other.id == id &&
      other.walletId == walletId && other.recurringRuleId == recurringRuleId && other.occurrenceDate == occurrenceDate &&
      other.currency == currency &&
      other.projectId == projectId && other.projectCategoryId == projectCategoryId &&
      other.projectAmountMinor == projectAmountMinor && other.projectCurrency == projectCurrency &&
      other.projectRate == projectRate && other.clientReceipt == clientReceipt &&
      other.paymentReference == paymentReference &&
      other.type == type &&
      other.amountMinor == amountMinor &&
      other.categoryId == categoryId &&
      other.note == note &&
      other.occurredAt == occurredAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
      id, walletId, currency, type, amountMinor, categoryId, note, occurredAt, updatedAt, recurringRuleId, occurrenceDate,
      projectId, projectCategoryId, projectAmountMinor, projectCurrency, projectRate, clientReceipt, paymentReference);
}
