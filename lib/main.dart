import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'shell.dart';
import 'strings.dart';

void main() => runApp(const MediaEditorApp());

ThemeData _theme(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E7C86), brightness: b),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)))),
    );

class MediaEditorApp extends StatelessWidget {
  const MediaEditorApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale>(
        valueListenable: appLocale,
        builder: (_, loc, __) => MaterialApp(
          title: 'Media Editor',
          debugShowCheckedModeBanner: false,
          locale: loc,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: const Shell(),
        ),
      );
}
