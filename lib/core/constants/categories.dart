import 'package:flutter/material.dart';

import '../../data/models/transaction_type.dart';

@immutable
class TransactionCategory {
  const TransactionCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
  });

  /// Stable identifier persisted in the database. Never rename.
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final TransactionType type;
}

abstract final class Categories {
  static const expense = <TransactionCategory>[
    TransactionCategory(
        id: 'food',
        name: 'Food & Dining',
        icon: Icons.restaurant_rounded,
        color: Color(0xFFF97316),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'groceries',
        name: 'Groceries',
        icon: Icons.local_grocery_store_outlined,
        color: Color(0xFF65A30D),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'transport',
        name: 'Transport',
        icon: Icons.directions_car_outlined,
        color: Color(0xFF3B82F6),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'shopping',
        name: 'Shopping',
        icon: Icons.shopping_bag_outlined,
        color: Color(0xFFEC4899),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'bills',
        name: 'Bills & Utilities',
        icon: Icons.receipt_long_outlined,
        color: Color(0xFF8B5CF6),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'housing',
        name: 'Housing',
        icon: Icons.home_outlined,
        color: Color(0xFF0EA5E9),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'health',
        name: 'Health',
        icon: Icons.favorite_border_rounded,
        color: Color(0xFFEF4444),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'entertainment',
        name: 'Entertainment',
        icon: Icons.movie_outlined,
        color: Color(0xFFF59E0B),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'education',
        name: 'Education',
        icon: Icons.school_outlined,
        color: Color(0xFF6366F1),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'travel',
        name: 'Travel',
        icon: Icons.flight_takeoff_rounded,
        color: Color(0xFF14B8A6),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'gifts',
        name: 'Gifts',
        icon: Icons.card_giftcard_outlined,
        color: Color(0xFFD946EF),
        type: TransactionType.expense),
    TransactionCategory(
        id: 'other',
        name: 'Other',
        icon: Icons.category_outlined,
        color: Color(0xFF64748B),
        type: TransactionType.expense),
  ];

  static const income = <TransactionCategory>[
    TransactionCategory(
        id: 'salary',
        name: 'Salary',
        icon: Icons.work_outline_rounded,
        color: Color(0xFF10B981),
        type: TransactionType.income),
    TransactionCategory(
        id: 'freelance',
        name: 'Freelance',
        icon: Icons.laptop_mac_outlined,
        color: Color(0xFF06B6D4),
        type: TransactionType.income),
    TransactionCategory(
        id: 'business',
        name: 'Business',
        icon: Icons.storefront_outlined,
        color: Color(0xFF6366F1),
        type: TransactionType.income),
    TransactionCategory(
        id: 'investments',
        name: 'Investments',
        icon: Icons.trending_up_rounded,
        color: Color(0xFF8B5CF6),
        type: TransactionType.income),
    TransactionCategory(
        id: 'gift_income',
        name: 'Gifts',
        icon: Icons.redeem_outlined,
        color: Color(0xFFEC4899),
        type: TransactionType.income),
    TransactionCategory(
        id: 'other_income',
        name: 'Other',
        icon: Icons.savings_outlined,
        color: Color(0xFF64748B),
        type: TransactionType.income),
  ];

  static const all = [...expense, ...income];

  static final Map<String, TransactionCategory> _byId = {
    for (final c in all) c.id: c,
  };

  static const _unknown = TransactionCategory(
    id: 'unknown',
    name: 'Uncategorized',
    icon: Icons.help_outline_rounded,
    color: Color(0xFF64748B),
    type: TransactionType.expense,
  );

  static TransactionCategory byId(String id) => _byId[id] ?? _unknown;

  static List<TransactionCategory> forType(TransactionType type) =>
      type.isIncome ? income : expense;
}
