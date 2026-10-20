import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/json.dart';
import 'info_boleto.dart';
import 'staff_auth.dart';

/* "Sincronizar boletos físicos" (solo admin) -- vincula un boleto impreso a
   un asiento de una localidad numerada sin pasar por una compra. El asiento
   queda Ocupado; la cédula (opcional) lo pinta en rojo y el código escaneado
   queda como su id_registra_compra. Contrato en
   APP_VENTA_TICKETS/docs/sincronizar-boletos-fisicos.md. */

class AsientoSincronizar {
  final int idLocalidadesItems;
  final String? codigoBarras;
  final String? cedula;
  final String? seccion;
  AsientoSincronizar(this.idLocalidadesItems, this.codigoBarras, this.cedula, this.seccion);
  Map<String, dynamic> toJson() => {
        'id_localidades_items': idLocalidadesItems,
        'codigo_barras': codigoBarras,
        'cedula': cedula,
        'seccion': seccion,
      };
}

class ResultadoAsientoSincronizado {
  final int idLocalidadesItems;
  final bool ok;
  final String? message;
  final String? paso;
  ResultadoAsientoSincronizado(this.idLocalidadesItems, this.ok, this.message, this.paso);
}

String _describirErrorHttp(Object err) {
  if (err is! DioException) return 'Error en la app: $err';
  final resp = err.response;
  if (resp == null) return 'Sin respuesta del servidor (${err.type.name}: ${err.message}).';
  final data = resp.data;
  String msgBack;
  if (data is String) {
    msgBack = data.length > 200 ? data.substring(0, 200) : data;
  } else {
    final m = asMap(data)['message'];
    final s = m != null ? m.toString() : data.toString();
    msgBack = s.length > 200 ? s.substring(0, 200) : s;
  }
  return 'HTTP ${resp.statusCode}${msgBack.isNotEmpty ? ' -- $msgBack' : ''}';
}

class ResultadoSincronizacion {
  final bool ok;
  final List<ResultadoAsientoSincronizado> resultados;
  final String mensaje;
  ResultadoSincronizacion.ok(this.resultados)
      : ok = true,
        mensaje = '';
  ResultadoSincronizacion.error(this.mensaje)
      : ok = false,
        resultados = const [];
}

Future<ResultadoSincronizacion> sincronizarAsientosFisicos(
    String codigoEvento, int idLocalidad, List<AsientoSincronizar> asientos) async {
  final body = {
    'codigoEvento': codigoEvento,
    'id_localidad': idLocalidad,
    'id_operador': obtenerStaffData()?.id ?? 0,
    'asientos': asientos.map((a) => a.toJson()).toList(),
  };
  debugPrint('[sincronizarAsientosFisicos] enviando $body');
  try {
    final r = await dio.post('$urlBase/boletos_fisicos/sincronizar_asientos', data: body, options: hdr(staffJsonHeaders()));
    final data = asMap(r.data);
    final resultados = asMapList(data['resultados'])
        .map((x) => ResultadoAsientoSincronizado(
            ent(x['id_localidades_items']), x['ok'] == true, strN(x['message']), strN(asMap(x['detalle'])['paso'])))
        .toList();
    if (data['success'] != true && resultados.isEmpty) {
      return ResultadoSincronizacion.error(
          'Backend: ${strN(data['message']) ?? 'No se pudo sincronizar (respuesta sin detalle).'}');
    }
    return ResultadoSincronizacion.ok(resultados);
  } catch (e) {
    final detalle = _describirErrorHttp(e);
    final s = statusDe(e);
    if (s == 404) {
      return ResultadoSincronizacion.error('Servicio de sincronización no disponible (falta desplegar el backend). $detalle');
    }
    if (s == 401) return ResultadoSincronizacion.error('Tu sesión expiró. Vuelve a iniciar sesión. $detalle');
    return ResultadoSincronizacion.error(detalle);
  }
}

class VerificacionCodigo {
  final bool ok;
  final String? seccion;
  final String? filaAsiento;
  final String? aviso;
  final String mensaje;
  VerificacionCodigo.ok({this.seccion, this.filaAsiento, this.aviso})
      : ok = true,
        mensaje = '';
  VerificacionCodigo.error(this.mensaje)
      : ok = false,
        seccion = null,
        filaAsiento = null,
        aviso = null;
}

/* Revisa un código escaneado ANTES de guardarlo: que no sea ya el QR de otro
   asiento y que en el inventario no esté vendido/anulado. */
Future<VerificacionCodigo> verificarCodigoFisico(String codigoEvento, String codigo) async {
  final res = await Future.wait<Object?>([
    obtenerInfoBoleto(codigo),
    dio
        .get('$urlBase/boletos_fisicos/buscar',
            queryParameters: {'codigoEvento': codigoEvento, 'codigo_barras': codigo}, options: hdr(staffAuthHeaders()))
        .then<Object?>((r) {
      final d = asMap(r.data);
      return d['success'] == true ? asMapList(d['data']) : <Map<String, dynamic>>[];
    }).catchError((_) => null),
  ]);
  final info = res[0] as ResultadoInfoBoleto;
  final inventario = res[1] as List<Map<String, dynamic>>?;

  /* info-boleto también busca por el id interno del asiento: solo cuenta como
     ocupado si el código ES el QR de ese asiento. */
  if (info.ok && info.tipo == 'asiento' && str(info.data['id_registra_compra']).trim() == codigo.trim()) {
    final d = info.data;
    final donde = [
      str(d['localidad_nombre']).replaceAll(RegExp(r'__+'), '').trim(),
      if (d['fila'] != null && str(d['fila']).isNotEmpty) 'Fila ${d['fila']}',
      if (d['silla'] != null && str(d['silla']).isNotEmpty) 'Silla ${d['silla']}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return VerificacionCodigo.error(
        'Ese código ya está vinculado a ${donde.isNotEmpty ? donde : 'el asiento #${d['id_item']}'}.');
  }

  if (inventario == null) {
    return VerificacionCodigo.ok(aviso: 'No se pudo revisar el inventario -- se sincroniza igual.');
  }
  final usado = inventario.where((f) => f['estado'] != null && f['estado'] != 'Disponible').toList();
  if (usado.isNotEmpty) {
    final u = usado.first;
    final motivo = u['estado'] == 'Anulado' ? 'fue anulado' : 'ya fue vendido';
    final compra = u['id_registraCompra'] != null ? ' (compra #${u['id_registraCompra']})' : '';
    return VerificacionCodigo.error('Este código $motivo$compra.');
  }
  if (inventario.length == 1) {
    final fa = strN(inventario[0]['fila_asiento']);
    return VerificacionCodigo.ok(
        seccion: strN(inventario[0]['seccion']), filaAsiento: (fa == null || fa.isEmpty) ? null : fa);
  }
  if (inventario.length > 1) {
    return VerificacionCodigo.ok(aviso: 'Existe en ${inventario.length} secciones del inventario -- no se descontará.');
  }
  return VerificacionCodigo.ok(aviso: 'No está en el inventario de boletos físicos.');
}
