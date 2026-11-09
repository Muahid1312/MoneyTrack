import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../data/storage/access_guard.dart';
import '../../security/application/security_service.dart';
import 'report_service.dart';

abstract final class ReportExporter {
  static String csv(ReportDocument document){String escape(String raw){var value=raw;
    if(RegExp(r'^[=+\-@\t\r]').hasMatch(value.trimLeft())&&!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value))value="'$value";
    if(value.contains(RegExp('[",\\r\\n]')))value='"${value.replaceAll('"','""')}"';return value;}
    return '\uFEFF${[document.headers,...document.rows].map((row)=>row.map(escape).join(',')).join('\r\n')}\r\n';}
  static Iterable<String> _chunks(String value) sync* {
    for(final line in value.split(RegExp(r'\r\n|\r|\n'))){
      final points=line.runes.toList();if(points.isEmpty){yield '';continue;}
      for(var i=0;i<points.length;i+=150){final text=String.fromCharCodes(points.sublist(i,(i+150).clamp(0,points.length).toInt()));
        yield text.replaceAllMapped(RegExp(r'\S{25}'),(m)=>m.group(0)!.runes.map((r)=>String.fromCharCode(r)).join('\u200b'));}
    }
  }
  static Future<Uint8List> pdf(ReportDocument document) async {
    if(document.rows.length>1000)throw StateError('For PDF, narrow the filters to 1,000 records or fewer. CSV supports the full result.');
    final font=pw.Font.ttf(await rootBundle.load('assets/report_fonts/DejaVuSans.ttf'));
    final arabic=pw.Font.ttf(await rootBundle.load('assets/report_fonts/NotoSansArabic-Regular.ttf'));
    final bold=pw.Font.ttf(await rootBundle.load('assets/report_fonts/DejaVuSans-Bold.ttf'));
    final output=pw.Document(theme:pw.ThemeData.withFont(base:font,bold:bold,fontFallback:[arabic]));
    output.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(32),maxPages:1000,
      header:(context)=>pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text('MoneyTrack · ${document.title}',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:6),pw.Text(document.scope,style:const pw.TextStyle(fontSize:8)),pw.Divider()]),
      footer:(context)=>pw.Align(alignment:pw.Alignment.centerRight,child:pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',style:const pw.TextStyle(fontSize:8))),
      build:(context){
        final faces=[font.getFont(context),arabic.getFont(context)];
        for(final text in [document.title,document.scope,...document.headers,...document.rows.expand((r)=>r)]){
          for(final rune in text.runes){if(rune>31&&!faces.any((f)=>f.isRuneSupported(rune)))throw UnsupportedError('Use CSV for characters outside the bundled PDF fonts');}
        }
        return [
        if(document.rows.isEmpty)pw.Text('No records match the selected filters.'),
        for(var i=0;i<document.rows.length;i++)...[
          pw.Padding(padding:const pw.EdgeInsets.only(top:10,bottom:5),child:pw.Text('Record ${i+1}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:10))),
          pw.TableHelper.fromTextArray(headers:['Field','Value'],data:[for(var column=0;column<document.headers.length;column++)for(final chunk in _chunks(document.rows[i][column]))[document.headers[column].replaceAll('_',' '),chunk]],
            columnWidths:{0:const pw.FlexColumnWidth(1),1:const pw.FlexColumnWidth(3)},cellAlignment:pw.Alignment.topLeft,
            headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),headerStyle:pw.TextStyle(font:font,fontWeight:pw.FontWeight.bold,fontSize:8),cellStyle:pw.TextStyle(font:font,fontSize:8),cellPadding:const pw.EdgeInsets.all(5)),
        ]
      ];}));return output.save();
  }
  static Future<File> write(ReportDocument document,bool asPdf) async {
    AccessGuard.writable();final folder=Directory(p.join((await getTemporaryDirectory()).path,'exports'));await folder.create(recursive:true);
    final name=SecureCrypto.random(12).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();final file=File(p.join(folder.path,'moneytrack-report-$name.${asPdf?'pdf':'csv'}'));
    await file.writeAsBytes(asPdf?await pdf(document):utf8.encode(csv(document)),flush:true);return file;
  }
  static Future<void> share(File file,{Rect? origin}) async {AccessGuard.writable();await SharePlus.instance.share(ShareParams(files:[XFile(file.path)],subject:'MoneyTrack export',sharePositionOrigin:origin));}
  static Future<void> cleanup({bool all=false}) async {final root=Directory(p.join((await getTemporaryDirectory()).path,'exports'));if(!await root.exists())return;
    await for(final file in root.list(followLinks:false)){if(file is File&&RegExp(r'^moneytrack-(report|backup)-[0-9a-f]+\.(pdf|csv|mtbackup)$').hasMatch(p.basename(file.path))&&(all||DateTime.now().difference(await file.lastModified()).inHours>=24))await file.delete();}}
}
