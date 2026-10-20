import 'dart:convert';

import 'package:app_venta_tickets/core/formato.dart';
import 'package:app_venta_tickets/core/prefs.dart';
import 'package:app_venta_tickets/main.dart';
import 'package:app_venta_tickets/services/descuentos.dart';
import 'package:app_venta_tickets/services/mapa_asientos.dart';
import 'package:app_venta_tickets/services/localidad_config.dart';
import 'package:app_venta_tickets/services/metodos_pago.dart';
import 'package:app_venta_tickets/services/staff_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(Map<String, dynamic> payload) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64(payload)}.firma';
}

void main() {
  group('Cálculo de totales (misma fórmula que la app Ionic)', () {
    test('subtotal + comisión de boleto + IVA + comisión bancaria', () {
      final t = calcularTotalConComision(10, 2, 1, 0.15, 0.08);
      expect(t.subtotal, 20);
      expect(t.comisionServicio, 2);
      expect(t.ivaImporte, closeTo(3, 1e-9));
      expect(t.comisionBancaria, closeTo(1.84, 1e-9));
      expect(t.total, closeTo(26.84, 1e-9));
    });

    test('sin comisión de boleto cuando el método no la aplica', () {
      final t = calcularTotalConComision(10, 2, 1, 0, 0, false);
      expect(t.comisionServicio, 0);
      expect(t.total, 20);
    });

    test('IVA desde el multiplicador legado del evento', () {
      expect(ivaRateDe('1.15'), closeTo(0.15, 1e-9));
      expect(ivaRateDe('1.12'), closeTo(0.12, 1e-9));
      expect(ivaRateDe('1.00'), 0);
      expect(ivaRateDe(null), 0);
    });

    test('descuento sobre el total final redondea a centavos', () {
      final d = aplicarDescuento(26.84, 10);
      expect(d.neto, 24.16);
      expect(d.monto, 2.68);
    });
  });

  group('Sesión', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();
    });

    test('decodifica el JWT de personal', () {
      final s = decodificarJWT(_jwt({'id': 7, 'name': 'Ana Pérez', 'perfil': 'vendedores', 'exp': 9999999999}));
      expect(s?.id, 7);
      expect(s?.name, 'Ana Pérez');
      expect(s?.perfil, 'vendedores');
      expect(puedeVender(s?.perfil), isTrue);
      expect(esAdmin(s?.perfil), isFalse);
    });

    test('un token vencido se descarta solo', () {
      Prefs.set('staffToken', _jwt({'id': 1, 'perfil': 'admin', 'exp': 1000}));
      expect(obtenerStaffData(), isNull);
      expect(Prefs.get('staffToken'), isNull);
    });
  });

  group('Formato y mapa de asientos', () {
    test('formatFecha', () {
      expect(formatFecha('2026-10-20'), '20 Oct 2026');
      expect(formatFecha('2026-10-20 14:35:00', conHora: true), '20 Oct 2026 · 14:35');
      expect(formatFecha(''), '—');
    });

    test('agrupa por fila y numera las sillas', () {
      final items = [
        ItemAsiento(fila: 'A', silla: 'A-s-1', estado: 'disponible', idsilla: 1, idRegistraCompra: ''),
        ItemAsiento(fila: 'A', silla: 'A-s-2', estado: 'ocupado', idsilla: 2, cedula: '0912345678', idRegistraCompra: 'X'),
        ItemAsiento(fila: 'B', silla: 'B-s-1', estado: 'ocupado', idsilla: 3, idRegistraCompra: ''),
      ];
      final filas = agruparFilas(items);
      expect(filas.keys, ['A', 'B']);
      expect(sillaNum(items[1], 1), '2');
      expect(estiloAsiento(items[1]), EstiloAsiento.ocupado);
      expect(estiloAsiento(items[2]), EstiloAsiento.bloqueado);
      expect(etiquetaAsiento(items[0], false), 'Fila A · Silla 1');
    });
  });

  testWidgets('sin sesión la app arranca en el login', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await tester.pumpWidget(const VentasApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Iniciar Sesión'), findsWidgets);
    expect(find.text('Acceso de personal de venta'), findsOneWidget);
  });
}
