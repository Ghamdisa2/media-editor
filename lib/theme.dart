import 'package:flutter/material.dart';
import 'tools.dart';

const kBrand = Color(0xFF0E7C86);

Color catColor(Cat c) => switch (c) {
      Cat.video => const Color(0xFFE76F51),
      Cat.image => const Color(0xFF0E9F9A),
      Cat.audio => const Color(0xFF3B82F6),
    };

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: kBrand, brightness: b);
  final surface = dark ? const Color(0xFF0F1519) : const Color(0xFFF3F6F7);
  const r14 = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Tajawal',
    colorScheme: cs,
    scaffoldBackgroundColor: surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: 'Tajawal',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF182026) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: dark ? const Color(0xFF26323A) : const Color(0xFFE2E8EB))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1D272E) : const Color(0xFFF0F4F5),
      border: OutlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: r14, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: r14, borderSide: BorderSide(color: cs.primary, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: r14),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            textStyle: const TextStyle(
                fontFamily: 'Tajawal', fontWeight: FontWeight.w700, fontSize: 15))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            shape: const RoundedRectangleBorder(borderRadius: r14),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            textStyle: const TextStyle(
                fontFamily: 'Tajawal', fontWeight: FontWeight.w600, fontSize: 15))),
    chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: dark ? const Color(0xFF1D272E) : const Color(0xFFE9EFF1),
        labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600)),
    sliderTheme: const SliderThemeData(trackHeight: 4),
    navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: cs.primaryContainer,
        selectedLabelTextStyle:
            TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF141C21) : Colors.white,
        indicatorColor: cs.primaryContainer,
        labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600, fontSize: 12))),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
  );
}
