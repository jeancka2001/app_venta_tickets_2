import 'package:flutter/material.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

NavigatorState get nav => navigatorKey.currentState!;

Future<T?> ir<T>(Widget pagina) => nav.push<T>(MaterialPageRoute(builder: (_) => pagina));

Future<T?> irReemplazando<T>(Widget pagina) =>
    nav.pushReplacement<T, Object?>(MaterialPageRoute(builder: (_) => pagina));

/* Equivalente a navigate(ruta, { replace: true }) a una pantalla raíz:
   limpia toda la pila (no queda nada a qué "volver"). */
Future<T?> irComoRaiz<T>(Widget pagina) =>
    nav.pushAndRemoveUntil<T>(MaterialPageRoute(builder: (_) => pagina), (_) => false);

/* Mensajes cortos (equivalente a IonToast). */
void toast(String mensaje, {Color? color, int segundos = 3}) {
  if (mensaje.isEmpty) return;
  final m = scaffoldMessengerKey.currentState;
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(mensaje),
    backgroundColor: color,
    duration: Duration(seconds: segundos),
  ));
}
