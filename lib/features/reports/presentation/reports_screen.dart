import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/categories.dart';
import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/transaction_type.dart';
import '../../documents/application/document_service.dart';
import '../application/report_service.dart';
import '../application/report_exporter.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override Widget build(BuildContext context,WidgetRef ref)=>Scaffold(appBar:AppBar(title:const Text('Financial reports'),actions:[IconButton(tooltip:'Refresh report',icon:const Icon(Icons.refresh),onPressed:()=>ref.invalidate(reportDataProvider))]),
    body:ref.watch(reportDataProvider).when(loading:()=>const Center(child:CircularProgressIndicator()),error:(_,_)=>Center(child:TextButton(onPressed:()=>ref.invalidate(reportDataProvider),child:const Text('Retry loading reports'))),data:(data){
      String money(int value)=>Money.format(value,data.filter.currency);final totals=data.totals;final months=data.months.entries.toList();final shown=months.length>24?months.sublist(months.length-24):months;
      return ListView(padding:const EdgeInsets.all(24),children:[
        _Filters(data:data),const SizedBox(height:20),Text('Income & expenses · ${data.filter.currency.code}',style:Theme.of(context).textTheme.titleLarge),
        _Metric('Income',money(totals.income)),_Metric('Expenses',money(totals.expense)),_Metric('Operating net cash flow',money(totals.net)),
        const Text('Operating cash flow is income minus expenses. Transfers, loan principal and savings reservations are excluded.'),
        if(totals.count==0)const Padding(padding:EdgeInsets.all(24),child:Text('No transactions match these filters.')),
        if(shown.isNotEmpty)...[
          const SizedBox(height:24),const Text('Monthly income versus expenses'),
          SizedBox(height:180,child:BarChart(BarChartData(titlesData:const FlTitlesData(show:false),gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),
            barGroups:[for(var i=0;i<shown.length;i++)BarChartGroupData(x:i,barRods:[BarChartRodData(toY:shown[i].value.income.toDouble(),color:Theme.of(context).colorScheme.primary,width:6),BarChartRodData(toY:shown[i].value.expense.toDouble(),color:Theme.of(context).colorScheme.error,width:6)])]))),
          Text('${_month(shown.first.key)} to ${_month(shown.last.key)} · Income / expenses${months.length>24?' · Last 24 active months':''}'),
          const SizedBox(height:20),const Text('Monthly operating cash-flow trend'),
          SizedBox(height:170,child:LineChart(LineChartData(minX:0,maxX:(shown.length<2?1:shown.length-1).toDouble(),titlesData:const FlTitlesData(show:false),gridData:const FlGridData(show:false),borderData:FlBorderData(show:false),
            lineBarsData:[LineChartBarData(spots:[for(var i=0;i<shown.length;i++)FlSpot(i.toDouble(),shown[i].value.net.toDouble())],isCurved:false,color:Theme.of(context).colorScheme.primary,dotData:const FlDotData(show:false))]))),
        ],
        if(data.categories.isNotEmpty)...[
          const SizedBox(height:20),Text('Spending by category',style:Theme.of(context).textTheme.titleMedium),
          SizedBox(height:180,child:PieChart(PieChartData(sections:[for(var i=0;i<data.categories.length;i++)PieChartSectionData(value:data.categories.values.elementAt(i).toDouble(),color:_colors[i%_colors.length],showTitle:false,radius:60)]))),
          for(final c in data.categories.entries)_Metric(c.key,money(c.value)),
        ],
        ExpansionTile(tilePadding:EdgeInsets.zero,title:const Text('Yearly trends'),children:[for(final y in data.years.entries)_Metric('${y.key}: income / expenses / net','${money(y.value.income)} / ${money(y.value.expense)} / ${money(y.value.net)}')]),
        const Divider(height:32),Text('Current wallet positions',style:Theme.of(context).textTheme.titleLarge),const Text('Positions reflect all recorded activity, independent of the transaction date/type/category filters. Reserved savings are already included in cash.'),
        for(final p in data.selectedPositions)...[
          Text(data.wallets.firstWhere((w)=>w['id']==p['id'])['name'] as String,style:Theme.of(context).textTheme.titleMedium),
          _Metric('Cash',money(p['balance'] as int)),_Metric('Reserved',money(p['reserved'] as int)),_Metric('Available',money((p['balance'] as int)-(p['reserved'] as int)))],
        const Divider(height:32),Text('Project reports',style:Theme.of(context).textTheme.titleLarge),
        const Text('Projects use their own selected currency and recorded historical rates. Budget and outstanding amounts are lifetime positions; period cash flow respects transaction filters.'),
        for(final p in data.selectedProjects)ExpansionTile(tilePadding:EdgeInsets.zero,title:Text(p.name),subtitle:Text('${p.type.label} · ${p.currency.code}'),children:[
          _Metric('Period receipts / payments','${money(data.period(p).receipts)} / ${money(data.period(p).expenses)}'),_Metric('Period cash surplus',money(data.period(p).cashSurplus)),
          _Metric('Planned budget',p.budgetMinor==null?'Not set':money(p.budgetMinor!)),_Metric('Lifetime expenses',money(data.lifetime(p).expenses)),_Metric('Remaining budget',data.lifetime(p).remainingBudget==null?'Not set':money(data.lifetime(p).remainingBudget!)),
          if(data.lifetime(p).usage!=null)LinearProgressIndicator(value:data.lifetime(p).usage!.clamp(0.0,1.0).toDouble()),
          if(data.lifetime(p).overspent)const Text('Over budget'),
          if(p.type.name=='business')_Metric('Outstanding client payments',data.lifetime(p).outstanding==null?'Contract not recorded':money(data.lifetime(p).outstanding!)),
          if(p.type.name=='personal')...[_Metric('Allocated funding',money(data.lifetime(p).allocated)),_Metric('Allocation remaining',money(data.lifetime(p).availableAllocation))],
          const Text('Cash surplus is not accounting profit.'),
        ]),
        const Divider(height:32),Text('Debt & savings positions',style:Theme.of(context).textTheme.titleLarge),
        _Metric('Principal owed',money(data.selectedDebts.where((d)=>d.borrowed).fold<int>(0,(s,d)=>s+d.remainingMinor))),
        _Metric('Principal receivable',money(data.selectedDebts.where((d)=>!d.borrowed).fold<int>(0,(s,d)=>s+d.remainingMinor))),
        const Text('Debt scope follows the originating wallet. Principal positions are current; repayment exports respect the selected date range.'),
        for(final g in data.selectedGoals)_Metric('${g.name} (${(g.progress*100).toStringAsFixed(1)}% reserved)',money(g.allocatedMinor)),
        const SizedBox(height:24),Text('Preview & export',style:Theme.of(context).textTheme.titleLarge),
        for(final kind in ['overview','transactions','projects','debts'])OutlinedButton.icon(icon:const Icon(Icons.ios_share),label:Text({'overview':'Financial overview','transactions':'Transaction history','projects':'Project financial reports','debts':'Debt & repayment summary'}[kind]!),
          onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ReportPreviewScreen(document:ReportDocuments.build(data,kind))))),
      ]);
    }));
  static String _month(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}';
  static const _colors=[Colors.teal,Colors.blue,Colors.orange,Colors.purple,Colors.pink,Colors.indigo];
}
class _Metric extends StatelessWidget {
  const _Metric(this.label,this.value);final String label,value;
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(label)),const SizedBox(width:12),Flexible(child:Text(value,textAlign:TextAlign.end,style:const TextStyle(fontWeight:FontWeight.w600)))]));
}
class _Filters extends ConsumerWidget {
  const _Filters({required this.data});final ReportData data;
  @override Widget build(BuildContext context,WidgetRef ref){final f=ref.watch(reportFilterProvider);
    void set({AppCurrency? currency,int? wallet,int? project,String? category,String? type,DateTime? from,DateTime? until,bool dates=false}){
      ref.read(reportFilterProvider.notifier).state=ReportFilter(currency:currency??f.currency,walletId:wallet==null?f.walletId:wallet==0?null:wallet,
        projectId:project==null?f.projectId:project==0?null:project,category:category==null?f.category:category=='all'?null:category,
        type:type==null?f.type:type=='all'?null:TransactionType.fromStorage(type),from:dates?from:f.from,until:dates?until:f.until);
    }
    return ExpansionTile(initiallyExpanded:true,tilePadding:EdgeInsets.zero,title:const Text('Report filters'),children:[
      DropdownButtonFormField<AppCurrency>(isExpanded: true, initialValue:f.currency,decoration:const InputDecoration(labelText:'Reporting currency (one at a time)'),items:[for(final c in AppCurrency.values)DropdownMenuItem(value:c,child:Text(c.code))],onChanged:(c)=>set(currency:c)),
      const SizedBox(height:12),DropdownButtonFormField<int>(initialValue:f.walletId??0,isExpanded:true,decoration:const InputDecoration(labelText:'Wallet'),items:[const DropdownMenuItem(value:0,child:Text('All wallets')),for(final w in data.wallets)DropdownMenuItem(value:w['id'] as int,child:Text('${w['name']} · ${w['currency']}'))],onChanged:(v)=>set(wallet:v)),
      const SizedBox(height:12),DropdownButtonFormField<int>(initialValue:f.projectId??0,isExpanded:true,decoration:const InputDecoration(labelText:'Project'),items:[const DropdownMenuItem(value:0,child:Text('All projects')),const DropdownMenuItem(value:-1,child:Text('Unassigned transactions')),for(final p in data.projects)DropdownMenuItem(value:p.id,child:Text(p.name,overflow:TextOverflow.ellipsis))],onChanged:(v)=>set(project:v)),
      const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:f.category??'all',isExpanded:true,decoration:const InputDecoration(labelText:'Category'),items:[const DropdownMenuItem(value:'all',child:Text('All categories')),for(final c in Categories.all)DropdownMenuItem(value:c.id,child:Text(c.name)),for(final c in data.projectCategories)DropdownMenuItem(value:'project:${c.id}',child:Text('Project category: ${c.name}'))],onChanged:(v)=>set(category:v)),
      const SizedBox(height:12),DropdownButtonFormField<String>(isExpanded: true, initialValue:f.type?.storageKey??'all',decoration:const InputDecoration(labelText:'Transaction type'),items:[const DropdownMenuItem(value:'all',child:Text('Income and expenses')),for(final t in TransactionType.values)DropdownMenuItem(value:t.storageKey,child:Text(t.label))],onChanged:(v)=>set(type:v)),
      Wrap(spacing:12,children:[TextButton.icon(icon:const Icon(Icons.date_range),label:Text(f.from==null?'All dates':'${f.from.toString().split(' ').first} → ${DateTime(f.until!.year,f.until!.month,f.until!.day-1).toString().split(' ').first}'),onPressed:() async {
        final range=await showDateRangePicker(context:context,firstDate:DateTime(1900),lastDate:DateTime(2200),initialDateRange:f.from==null?null:DateTimeRange(start:f.from!,end:DateTime(f.until!.year,f.until!.month,f.until!.day-1)));
        if(range!=null)set(from:range.start,until:DateTime(range.end.year,range.end.month,range.end.day+1),dates:true);
      }),TextButton(onPressed:()=>set(dates:true),child:const Text('All dates'))]),
    ]);
  }
}
class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key,required this.document});final ReportDocument document;
  @override State<ReportPreviewScreen> createState()=>_PreviewState();
}
class _PreviewState extends State<ReportPreviewScreen>{
  bool _busy=false;String? _message;
  Future<void> _export(bool pdf,{bool preview=false}) async {if(_busy)return;setState(()=>_busy=true);
    try {final file=await ReportExporter.write(widget.document,pdf);if(!context.mounted)return;if(preview)await DocumentBridge.open(file);else await ReportExporter.share(file,origin:Rect.fromLTWH(MediaQuery.sizeOf(context).width/2,MediaQuery.sizeOf(context).height/2,1,1));}
    catch (error){if(mounted)setState(()=>_message=error is UnsupportedError?'The PDF font cannot display some characters. CSV preserves Unicode text.':'Export unavailable. Unlock the app and try again. For PDF, limit the result to 1,000 records.');}
    finally{if(mounted)setState(()=>_busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.document.title)),body:ListView(padding:const EdgeInsets.all(24),children:[
    Text(widget.document.scope),Text('${widget.document.rows.length} records · Preview shows the first 30. Exports use the complete result.'),
    Wrap(spacing:12,children:[FilledButton(onPressed:_busy?null:()=>_export(false),child:const Text('Share CSV')),OutlinedButton(onPressed:_busy?null:()=>_export(true),child:const Text('Share PDF')),TextButton(onPressed:_busy?null:()=>_export(true,preview:true),child:const Text('Preview PDF'))]),
    if(_busy)const LinearProgressIndicator(),if(_message!=null)Text(_message!),
    SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:[for(final h in widget.document.headers)DataColumn(label:Text(h))],rows:[for(final row in widget.document.rows.take(30))DataRow(cells:[for(final cell in row)DataCell(SizedBox(width:160,child:Text(cell,maxLines:4,overflow:TextOverflow.ellipsis)))])])),
  ]));
}
