import 'package:flutter/material.dart';

/* Colores de marca -- los mismos que usaban los .css de la app Ionic. */
class C {
  static const azul = Color(0xFF2D358C);
  static const azulOscuro = Color(0xFF1A1E52);
  static const azulMedio = Color(0xFF1B2A4A);
  static const lila = Color(0xFF7B8FDC);
  static const gris = Color(0xFF6B7A90);
  static const grisClaro = Color(0xFF9DA5B4);
  static const borde = Color(0xFFE8ECF5);
  static const fondo = Color(0xFFF4F6FB);
  static const verde = Color(0xFF27AE60);
  static const verdeClaro = Color(0xFF4ADE80);
  static const rojo = Color(0xFFE74C3C);
  static const rojoOscuro = Color(0xFFC0392B);
  static const rojoFondo = Color(0xFFFDE8E8);
  static const naranja = Color(0xFFF08121);
  static const naranjaFondo = Color(0xFFFEF3E2);
  static const ambar = Color(0xFFF59E0B);
  static const fondoOscuro = Color(0xFF101624);
  static const tarjetaOscura = Color(0xFF1E2540);
}

ThemeData temaClaro() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.azul,
    primary: C.azul,
    secondary: C.lila,
    surface: Colors.white,
    error: C.rojo,
  );
  return _base(scheme, C.fondo, Brightness.light);
}

ThemeData temaOscuro() {
  final scheme = ColorScheme.fromSeed(
    seedColor: C.azul,
    brightness: Brightness.dark,
    primary: C.lila,
    secondary: C.lila,
    surface: C.tarjetaOscura,
    error: const Color(0xFFF87171),
  );
  return _base(scheme, C.fondoOscuro, Brightness.dark);
}

ThemeData _base(ColorScheme scheme, Color fondo, Brightness b) {
  final oscuro = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: fondo,
    appBarTheme: AppBarTheme(
      backgroundColor: oscuro ? const Color(0xFF151B30) : C.azulOscuro,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: oscuro ? const Color(0xFF2A3050) : C.borde),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: oscuro ? C.lila : C.azul,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: oscuro ? C.lila : C.azul,
        minimumSize: const Size(0, 42),
        side: BorderSide(color: oscuro ? C.lila : C.azul),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: oscuro ? const Color(0xFF151B30) : Colors.white,
      indicatorColor: (oscuro ? C.lila : C.azul).withValues(alpha: 0.15),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: oscuro ? Colors.white70 : C.azulOscuro),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
