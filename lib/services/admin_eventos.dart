import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api.dart';
import '../core/json.dart';
import 'staff_auth.dart';

/* Módulo de administración de eventos y localidades (solo admin/super_admin).
   Mismos endpoints que usa TicketsWeb. */

class EventoAdmin {
  final int id;
  final String nombreConcierto;
  final String fechaConcierto;
  final String horaConcierto;
  final String lugarConcierto;
  final String cuidadConcert;
  final String descripcionConcierto;
  final String imagenConcierto;
  final String mapaConcierto;
  final String codigoEvento;
  final String estado;
  final String iva;

  EventoAdmin({
    required this.id,
    required this.nombreConcierto,
    required this.fechaConcierto,
    required this.horaConcierto,
    required this.lugarConcierto,
    required this.cuidadConcert,
    required this.descripcionConcierto,
    required this.imagenConcierto,
    required this.mapaConcierto,
    required this.codigoEvento,
    required this.estado,
    required this.iva,
  });

  factory EventoAdmin.fromJson(Map<String, dynamic> j) => EventoAdmin(
        id: ent(j['id']),
        nombreConcierto: str(j['nombreConcierto']),
        fechaConcierto: str(j['fechaConcierto']),
        horaConcierto: str(j['horaConcierto']),
        lugarConcierto: str(j['lugarConcierto']),
        cuidadConcert: str(j['cuidadConcert']),
        descripcionConcierto: str(j['descripcionConcierto']),
        imagenConcierto: str(j['imagenConcierto']),
        mapaConcierto: str(j['mapaConcierto']),
        codigoEvento: str(j['codigoEvento']),
        estado: str(j['estado']),
        iva: str(j['iva'], '1.00'),
      );

  EventoAdmin conEstado(String nuevo) => EventoAdmin(
        id: id,
        nombreConcierto: nombreConcierto,
        fechaConcierto: fechaConcierto,
        horaConcierto: horaConcierto,
        lugarConcierto: lugarConcierto,
        cuidadConcert: cuidadConcert,
        descripcionConcierto: descripcionConcierto,
        imagenConcierto: imagenConcierto,
        mapaConcierto: mapaConcierto,
        codigoEvento: codigoEvento,
        estado: nuevo,
        iva: iva,
      );
}

class LocalidadAdmin {
  final int id;
  final String localidad;
  final String precioNormal;
  final String precioDiscapacidad;
  final String precioTarjeta;
  final String precioDescuento;
  final String habilitarCortesia;
  final String comisionBoleto;
  final String? mensajePromocion;
  /* Del catálogo físico: solo con id_localidad + tipo fila/mesa se pueden
     editar asientos uno por uno. */
  final int? idLocalidad;
  final String? tipoLocalidad;

  LocalidadAdmin(this.id, this.localidad, this.precioNormal, this.precioDiscapacidad, this.precioTarjeta,
      this.precioDescuento, this.habilitarCortesia, this.comisionBoleto, this.mensajePromocion, this.idLocalidad,
      this.tipoLocalidad);

  factory LocalidadAdmin.fromJson(Map<String, dynamic> j) => LocalidadAdmin(
        ent(j['id']),
        str(j['localidad']),
        str(j['precio_normal']),
        str(j['precio_discapacidad']),
        str(j['precio_tarjeta']),
        str(j['precio_descuento']),
        str(j['habilitar_cortesia'], '0'),
        str(j['comision_boleto']),
        strN(j['mensaje_promocion']),
        entN(j['id_localidad']),
        strN(j['tipo_localidad']),
      );

  bool get esNumerada => idLocalidad != null && idLocalidad != 0 && (tipoLocalidad == 'fila' || tipoLocalidad == 'mesa');
}

class Resultado {
  final bool success;
  final String? message;
  const Resultado(this.success, [this.message]);
  factory Resultado.fromData(dynamic data) {
    final m = asMap(data);
    return Resultado(m['success'] == true, strN(m['message']));
  }
  factory Resultado.fromError(Object e) => Resultado(false, mensajeBackend(e));
}

/* Lanzada cuando el backend responde 401 (JWT del admin vencido). */
class SesionExpiradaError implements Exception {}

/* No hay un "TODOS" real en el backend -- se piden los estados conocidos en
   paralelo y se fusionan. */
const _estadosEvento = ['ACTIVO', 'PROCESO', 'PROXIMO', 'CANCELADO', 'FINALIZADO'];

Future<List<EventoAdmin>> listarEventosAdmin() async {
  final headers = staffAuthHeaders();
  var sesionExpirada = false;
  final resultados = await Future.wait(_estadosEvento.map((estado) async {
    try {
      final r = await dio.get('$urlMsLogin/listareventos/$estado/', options: hdr(headers));
      final data = asMap(r.data);
      return data['success'] == true ? asMapList(data['data']).map(EventoAdmin.fromJson).toList() : <EventoAdmin>[];
    } catch (e) {
      if (statusDe(e) == 401) sesionExpirada = true;
      return <EventoAdmin>[];
    }
  }));
  if (sesionExpirada) throw SesionExpiradaError();
  final mapa = <String, EventoAdmin>{};
  for (final ev in resultados.expand((l) => l)) {
    mapa[ev.codigoEvento] = ev;
  }
  final lista = mapa.values.toList()..sort((a, b) => b.fechaConcierto.compareTo(a.fechaConcierto));
  return lista;
}

Future<String?> subirImagenEvento(String rutaArchivo) => subirImagen(rutaArchivo);

Future<Resultado> crearEventoAdmin(Map<String, dynamic> payload) async {
  try {
    final staff = obtenerStaffData();
    final r = await dio.post('$urlMsLogin/crearevento',
        data: {...payload, 'idUsuario': '${staff?.id ?? 0}', 'LocalodadPrecios': []},
        options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

/* Edición de datos básicos -- mismo endpoint que el modal de edición de la
   web, NO /actualizarevento (ese exige mandar todas las localidades). */
Future<Resultado> actualizarDescripcionEvento(Map<String, dynamic> payload) async {
  try {
    final r = await dio.post('$urlBase/actualisar_descripcion_evento', data: payload, options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

const estadosCambiables = ['PROCESO', 'PROXIMO', 'ACTIVO', 'CANCELADO'];

Future<Resultado> actualizarEstadoEvento(String codigoEvento, String estado) async {
  try {
    final staff = obtenerStaffData();
    final r = await dio.put('$urlMsLogin/actualizarevento_estado/$codigoEvento',
        data: {'estado': estado, 'id_usuario': 0, 'id_operador': staff?.id ?? 0}, options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

Future<List<LocalidadAdmin>> listarLocalidadesAdmin(String codigoEvento) async {
  try {
    final r = await dio.get('$urlMsLogin/ListaPreciosLocalidades/$codigoEvento', options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return data['success'] == true ? asMapList(data['data']).map(LocalidadAdmin.fromJson).toList() : [];
  } catch (_) {
    return [];
  }
}

Future<Resultado> crearLocalidadAdmin(Map<String, dynamic> payload) async {
  try {
    final r = await dio.post('$urlMsLogin/crear_localidad_precio_evento', data: payload, options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

Future<Resultado> actualizarPrecioLocalidadAdmin(Map<String, dynamic> payload) async {
  try {
    final r = await dio.post('$urlBase/actualisar_precio_localidad', data: payload, options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

/* El backend NO valida si ya hay boletos vendidos con esa localidad -- la UI
   pide confirmación fuerte antes de llamar a esto. */
Future<Resultado> eliminarLocalidadAdmin(String codigoEvento, String localidad) async {
  try {
    final r = await dio.delete(
        '$urlMsLogin/eliminarevento/${Uri.encodeComponent(codigoEvento)}/${Uri.encodeComponent(localidad)}',
        options: hdr(staffAuthHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

/* ── Factura final del evento (resumen de cierre) ── */

class ResumenFormaPago {
  final String formaPago;
  final double total;
  final double iva;
  final int boleto;
  final int cantidad;
  ResumenFormaPago(this.formaPago, this.total, this.iva, this.boleto, this.cantidad);
}

class RegistroOrigenFactura {
  final int idRegistraCompra;
  final String cedula;
  final int cantidad;
  final double subtotalItem;
  RegistroOrigenFactura(this.idRegistraCompra, this.cedula, this.cantidad, this.subtotalItem);
}

class FacturaLocalidadItem {
  final String localidad;
  final String tarifa;
  final double precioUnitarioBase;
  final int cantidad;
  final double subtotalSinIva;
  final List<RegistroOrigenFactura> registrosOrigen;
  FacturaLocalidadItem(
      this.localidad, this.tarifa, this.precioUnitarioBase, this.cantidad, this.subtotalSinIva, this.registrosOrigen);
}

class ResumenOperador {
  final String operador;
  final String formaPago;
  final double total;
  final int boleto;
  final int cantidad;
  ResumenOperador(this.operador, this.formaPago, this.total, this.boleto, this.cantidad);
}

class FacturaFinalEvento {
  final List<ResumenFormaPago> porFormaPago;
  final List<FacturaLocalidadItem> porLocalidad;
  final List<ResumenOperador> porOperador;
  FacturaFinalEvento(this.porFormaPago, this.porLocalidad, this.porOperador);
}

Future<FacturaFinalEvento> obtenerFacturaFinalEvento(String codigoEvento) async {
  Future<List<Map<String, dynamic>>> pedir(String path) async {
    try {
      final r = await dio.post('$urlMikroti/Boleteria/$path', data: {'nombre': codigoEvento}, options: hdr(jsonHdr));
      return asMapList(asMap(r.data)['data']);
    } catch (_) {
      return [];
    }
  }

  final res = await Future.wait([pedir('evento_valor'), pedir('factura_localidades_v3'), pedir('evento_user')]);
  return FacturaFinalEvento(
    res[0]
        .map((f) => ResumenFormaPago(str(f['forma_pago']), dbl(f['total']), dbl(f['iva']), ent(f['boleto']), ent(f['cantidad'])))
        .toList(),
    res[1]
        .map((f) => FacturaLocalidadItem(
              str(f['localidad']),
              str(f['tarifa']),
              dbl(f['precio_unitario_base']),
              ent(f['cantidad']),
              dbl(f['subtotal_sin_iva']),
              asMapList(f['registros_origen'])
                  .map((r) => RegistroOrigenFactura(
                      ent(r['id_registraCompra']), str(r['cedula']), ent(r['cantidad']), dbl(r['subtotal_item'])))
                  .toList(),
            ))
        .toList(),
    res[2]
        .map((f) => ResumenOperador(
            str(f['operador']), str(f['forma_pago']), dbl(f['total']), ent(f['boleto']), ent(f['cantidad'])))
        .toList(),
  );
}

/* ── Asientos individuales (localidades numeradas: fila/mesa) ──
   - item_localidad (mikroti): BLOQUEA un asiento libre (sin venta real).
   - liberar_asientos_admin (ms_login): LIBERA un asiento Reservado/Ocupado.
   Nunca se toca un asiento con cédula real (venta genuina). */
Future<bool> cambiarEstadoAsiento(int idAsiento, String estado) async {
  try {
    final r = await dio.put('$urlMikroti/Boleteria/item_localidad',
        data: {'id_localidades': [idAsiento], 'estado': estado}, options: hdr(jsonHdr));
    return truthy(asMap(r.data)['estado']);
  } catch (_) {
    return false;
  }
}

Future<Resultado> liberarAsientosAdmin(List<int> idSillas) async {
  try {
    final r = await dio.post('$urlBase/liberar_asientos_admin', data: {'id_sillas': idSillas}, options: hdr(staffJsonHeaders()));
    return Resultado.fromData(r.data);
  } catch (e) {
    return Resultado.fromError(e);
  }
}

/* ── Discrepancias (evento): 3 reportes de solo lectura ── */
class DiscrepanciasEvento {
  final List<Map<String, dynamic>> discrepancias;
  final List<Map<String, dynamic>> discrepanciasGeneracion;
  final List<Map<String, dynamic>> comprasEvento;
  DiscrepanciasEvento(this.discrepancias, this.discrepanciasGeneracion, this.comprasEvento);
}

Future<DiscrepanciasEvento> obtenerDiscrepanciasEvento(String codigoEvento) async {
  Future<List<Map<String, dynamic>>> pedir(String path) async {
    try {
      final r = await dio.post('$urlMikroti/Boleteria/analizar/$path',
          data: {'codigo_evento': codigoEvento}, options: hdr(jsonHdr));
      return asMapList(asMap(r.data)['data']);
    } catch (_) {
      return [];
    }
  }

  final res = await Future.wait([pedir('discrepancias'), pedir('discrepancias-generacion'), pedir('compras-evento')]);
  return DiscrepanciasEvento(res[0], res[1], res[2]);
}

/* Botón "Descargar registros" de la web -- manda el codigoEvento (no el id). */
Future<Uint8List?> descargarReporteEventoExcel(String codigoEvento) async {
  try {
    final r = await dio.get<List<int>>('$urlMikrotiV2/api/reporte_evento/${Uri.encodeComponent(codigoEvento)}',
        options: Options(responseType: ResponseType.bytes));
    return r.data == null ? null : Uint8List.fromList(r.data!);
  } catch (_) {
    return null;
  }
}
