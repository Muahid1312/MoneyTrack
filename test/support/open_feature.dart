import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/features/explore/explore_screen.dart';

Future<void> openFeature(WidgetTester tester, MoneyFeature feature) async {
  await tester.tap(find.widgetWithText(NavigationDestination, 'More'));
  await tester.pumpAndSettle();
  final search = find.descendant(
    of: find.byType(ExploreScreen),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(search);
  await tester.enterText(search, feature.title);
  await tester.pumpAndSettle();
  final tile = find.byKey(ValueKey('feature-${feature.name}'));
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}
