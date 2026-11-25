import 'package:flutter/widgets.dart';

extension AppLanguage on BuildContext {
  bool get usesDari => Localizations.localeOf(this).languageCode == 'fa';
  String tr(String english, String dari) => usesDari ? dari : english;
}
