import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/json.dart';
import 'staff_auth.dart';

/* Misma consulta que usa TicketsWeb/app_tickets para saber qué pasarelas
   están activas y su comisión configurada (global o por evento). */

class MetodoPagoActivo {
  final String metodo;
  final bool activo;
  final double comisionPorcentaje;
  /* Si el admin restringió por evento en qué métodos se cobra la comisión
     de la ticketera (comision_boleto). Sin restricción viene en true. */
  final bool aplicaComisionBoleto;

  MetodoPagoActivo(this.metodo, this.activo, this.comisionPorcentaje, this.aplicaComisionBoleto);

  factory MetodoPagoActivo.fromJson(Map<String, dynamic> j) => MetodoPagoActivo(
        str(j['metodo']),
        truthy(j['activo']),
        dbl(j['comision_porcentaje']),
        j['aplica_comision_boleto'] == null ? true : truthy(j['aplica_comision_boleto']),
      );
}

Future<List<MetodoPagoActivo>> obtenerMetodosPagoActivos([String? codigoEvento]) async {
  try {
    /* Con el JWT del vendedor: el backend aplica la restricción por usuario
       (usuario_metodos_pago) si el admin le asignó un subconjunto. */
    final r = await dio.get('$urlBase/metodos_pago_activos',
        queryParameters: (codigoEvento != null && codigoEvento.isNotEmpty) ? {'codigoEvento': codigoEvento} : null,
        options: hdr(staffAuthHeaders()));
    return asMapList(asMap(r.data)['data']).map(MetodoPagoActivo.fromJson).toList();
  } catch (e) {
    debugPrint('[metodosPago] error: $e');
    return [];
  }
}

class ListaMetodosAdmin {
  final bool success;
  final List<MetodoPagoActivo> data;
  final bool sesionExpirada;
  ListaMetodosAdmin(this.success, this.data, this.sesionExpirada);
}

/* Para Admin > Métodos de pago: acá sí se necesita saber SI falló y por qué
   (con el JWT vencido el switch parecía "no hacer nada"). */
Future<ListaMetodosAdmin> listarMetodosPagoAdmin() async {
  try {
    final r = await dio.get('$urlBase/metodos_pago_activos', options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return ListaMetodosAdmin(
        data['success'] == true, asMapList(data['data']).map(MetodoPagoActivo.fromJson).toList(), false);
  } catch (e) {
    final s = statusDe(e);
    return ListaMetodosAdmin(false, [], s == 401 || s == 403);
  }
}

Future<({bool success, String? message})> toggleMetodoPagoActivo(String metodo, bool activo) async {
  try {
    final r = await dio.patch('$urlBase/configuracion_pagos/${Uri.encodeComponent(metodo)}/activo',
        data: {'activo': activo}, options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return (success: data['success'] == true, message: strN(data['message']));
  } catch (e) {
    final s = statusDe(e);
    return (
      success: false,
      message: (s == 401 || s == 403)
          ? 'Tu sesión expiró. Cierra sesión y vuelve a iniciar sesión para poder activar/desactivar métodos.'
          : 'No se pudo cambiar el estado (error de conexión).',
    );
  }
}

enum CategoriaMetodo { gateway, local, transferencia }

class MetodoConfigurable {
  final String key;
  final String label;
  final double pctDefault;
  final CategoriaMetodo categoria;
  const MetodoConfigurable(this.key, this.label, this.pctDefault, this.categoria);
}

/* Mismo set de métodos que ofrece la web para venta presencial. */
const metodosConfigurables = <MetodoConfigurable>[
  MetodoConfigurable('Efectivo-Local', 'Efectivo', 0, CategoriaMetodo.local),
  /* 0.15 -- mismo respaldo que la web si el backend no devuelve el %. */
  MetodoConfigurable('Tarjeta-Local', 'Tarjeta física (POS)', 0.15, CategoriaMetodo.local),
  MetodoConfigurable('Efectivo-QR', 'Efectivo (QR recaudación)', 0, CategoriaMetodo.local),
  MetodoConfigurable('Efectivo', 'Efectivo (Speed/Comnet)', 0.08, CategoriaMetodo.local),
  MetodoConfigurable('PagoPlux', 'Link de pago (Tarjeta)', 0.11, CategoriaMetodo.gateway),
  MetodoConfigurable('Payphone', 'Payphone', 0.11, CategoriaMetodo.gateway),
  MetodoConfigurable('Duna', 'Duna / Banco Pichincha', 0.11, CategoriaMetodo.gateway),
  MetodoConfigurable('Transferencia', 'Transferencia / Depósito', 0.08, CategoriaMetodo.transferencia),
];

String etiquetaFormaPago(String? forma) {
  for (final m in metodosConfigurables) {
    if (m.key == forma) return m.label;
  }
  return (forma == null || forma.isEmpty) ? '—' : forma;
}

class DesgloseTotal {
  final double subtotal;
  final double comisionServicio;
  final double ivaImporte;
  final double comisionBancaria;
  final double total;
  DesgloseTotal(this.subtotal, this.comisionServicio, this.ivaImporte, this.comisionBancaria, this.total);
}

/* subtotal = precio*cantidad; iva y comisión bancaria sobre el subtotal --
   misma fórmula que la venta real (compartida con la vista previa de
   "Sumar comisiones" en Vender). */
DesgloseTotal calcularTotalConComision(
  double precioUnitario,
  int cantidad,
  double comisionBoletoUnitario,
  double ivaRate,
  double pctComisionBancaria, [
  bool aplicaComisionBoleto = true,
]) {
  final subtotal = precioUnitario * cantidad;
  final comisionServicio = aplicaComisionBoleto ? comisionBoletoUnitario * cantidad : 0.0;
  final ivaImporte = subtotal * ivaRate;
  final comisionBancaria = (subtotal + ivaImporte) * pctComisionBancaria;
  return DesgloseTotal(
      subtotal, comisionServicio, ivaImporte, comisionBancaria, subtotal + comisionServicio + ivaImporte + comisionBancaria);
}

/* eventos.iva guarda el multiplicador legado ("1.15" = 15%) -> 0.15. */
double ivaRateDe(String? iva) => dbl((iva == null || iva.isEmpty ? '1.00' : iva).replaceFirst('1.', '0.'));
