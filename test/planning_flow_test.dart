import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneytrack/core/constants/currency.dart';
import 'package:moneytrack/data/models/planning.dart';
import 'package:moneytrack/data/models/wallet.dart';
import 'package:moneytrack/data/repositories/wallet_repository.dart';
import 'package:moneytrack/features/planning/application/planning_providers.dart';
import 'package:moneytrack/features/planning/presentation/planning_forms.dart';
import 'package:moneytrack/features/planning/presentation/planning_screens.dart';
import 'package:moneytrack/features/wallets/application/wallet_providers.dart';

void main(){
  testWidgets('savings UI distinguishes reservations from wallet money', (tester) async {
    final data=PlanningSnapshot(debts:const[],postings:const[],goals:[SavingsGoal({'id':1,'name':'Emergency fund','wallet_id':1,'currency':'USD','target_minor':10000,'target_date':null,'status':'active','color':0xFF10B981,'icon':'savings'},4000)],savingsEvents:const[],rules:const[],occurrences:const[]);
    const wallet=Wallet(id:1,name:'Cash',type:WalletType.cash,currency:AppCurrency.usd);
    await tester.pumpWidget(ProviderScope(overrides:[planningProvider.overrideWith((ref) async=>data),
      walletsProvider.overrideWith((ref) async=>const WalletSnapshot([wallet],{1:10000},[],reserved:{1:4000}))],child:const MaterialApp(home:GoalsScreen())));
    await tester.pumpAndSettle();await tester.tap(find.text('Emergency fund'));await tester.pumpAndSettle();
    expect(find.text(r'$40.00 reserved'),findsOneWidget);expect(find.text(r'Wallet cash: $100.00'),findsOneWidget);
    expect(find.text(r'Available wallet cash: $60.00'),findsOneWidget);
    expect(find.text('Allocations stay inside this wallet and do not increase net worth.'),findsOneWidget);
  });
  testWidgets('debt creation requires contact and a real principal reference',(tester) async {
    const wallet=Wallet(id:1,name:'Cash',type:WalletType.cash,currency:AppCurrency.usd);
    await tester.pumpWidget(ProviderScope(overrides:[walletsProvider.overrideWith((ref) async=>const WalletSnapshot([wallet],{1:10000},[]))],child:const MaterialApp(home:DebtForm())));
    await tester.pumpAndSettle();await tester.scrollUntilVisible(find.text('Save debt'),300,
      scrollable:find.byWidgetPredicate((w)=>w is Scrollable && w.axisDirection==AxisDirection.down).first);
    await tester.tap(find.text('Save debt'));await tester.pumpAndSettle();
    expect(find.text('This field is required'),findsWidgets);
  });
}
