import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final screens = Map<String, dynamic>.from(data!['screens'] as Map);
    final dir = await Directory('build/visual-review').create(recursive: true);
    for (final entry in screens.entries) {
      if (!RegExp(r'^[a-z-]+$').hasMatch(entry.key)) {
        throw StateError('Invalid screen name');
      }
      final bytes = base64Decode(entry.value as String);
      await File(
        '${dir.path}/${entry.key}.png',
      ).writeAsBytes(bytes, flush: true);
    }
    stdout.writeln('Captured ${screens.length} Android views.');
  },
);
