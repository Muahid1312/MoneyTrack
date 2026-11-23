import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const captureDirectory = String.fromEnvironment('LEDGER_SCREENSHOTS');
Future<void> loadCaptureFonts(WidgetTester tester) async {
  if (captureDirectory.isEmpty) return;
  await tester.runAsync(() async {
    final font = FontLoader('Plus Jakarta Sans');
    for (final n in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(
        rootBundle.load('assets/google_fonts/PlusJakartaSans-$n.ttf'),
      );
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('Noto Arabic')..addFont(
          rootBundle.load('assets/report_fonts/NotoSansArabic-Regular.ttf'),
        ))
        .load();
  });
}

Future<void> captureView(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(captureDirectory).create(recursive: true);
      await File(
        '$captureDirectory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
