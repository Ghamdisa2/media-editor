import 'package:flutter/material.dart';

final appLocale = ValueNotifier<Locale>(const Locale('ar'));

/// Pick Arabic or English text; depends on Localizations so widgets rebuild on switch.
String t(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;
