import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/json.dart';

/* Cómo se configuró cada fila en el editor del admin (alineación y orden de
   sillas) -- sin esto el mapa no coincide con lo que se ve en la web. Solo
   aplica a localidades tipo "fila". */

class ConfiguracionLocalidad {
  final Map<String, String> alineacion;
  final Map<String, bool> ordenSillas;
  final int? idEspacio;
  ConfiguracionLocalidad(this.alineacion, this.ordenSillas, this.idEspacio);
}

Future<ConfiguracionLocalidad> obtenerConfiguracionLocalidad(Object idLocalidad) async {
  try {
    final r = await dio.get('$urlBase/listar_localidades/$idLocalidad', options: hdr(msLoginAuthHeaders));
    final data = asMap(r.data)['data'];
    final row = data is List ? asMap(data.isNotEmpty ? data[0] : null) : asMap(data);
    final ma = asMap(jsonDecode(str(row['mesas_array'], '{}')));
    return ConfiguracionLocalidad(
      asMap(ma['alineacion']).map((k, v) => MapEntry(k, str(v))),
      asMap(ma['ordenSillas']).map((k, v) => MapEntry(k, truthy(v))),
      entN(row['id_espacio']),
    );
  } catch (_) {
    return ConfiguracionLocalidad({}, {}, null);
  }
}

class ItemAsiento {
  final String fila;
  final String? mesa;
  final String silla;
  final String estado;
  final int idsilla;
  final String? cedula;
  final String idRegistraCompra;
  /* Fila cruda del backend (se reenvía tal cual al reservar). */
  final Map<String, dynamic> raw;

  ItemAsiento({
    required this.fila,
    this.mesa,
    required this.silla,
    required this.estado,
    required this.idsilla,
    this.cedula,
    required this.idRegistraCompra,
    this.raw = const {},
  });
}

class ResumenLocalidad {
  final int total;
  final int disponibles;
  final int ocupadas;
  const ResumenLocalidad(this.total, this.disponibles, this.ocupadas);
}

Future<({List<ItemAsiento> items, ResumenLocalidad resumen})> obtenerMapaLocalidad(
    int idEspacio, Object idLocalidad) async {
  try {
    final r = await dio.get('$urlBase/listar_localidades_id_espacio/$idEspacio/$idLocalidad',
        options: hdr(msLoginAuthHeaders));
    final items = asMapList(asMap(r.data)['data'])
        .map((m) => ItemAsiento(
              fila: str(m['fila']),
              mesa: strN(m['mesa']),
              silla: str(m['silla']),
              estado: str(m['estado']).toLowerCase(),
              idsilla: ent(m['id']),
              cedula: strN(m['cedula']),
              idRegistraCompra: str(m['id_registra_compra']),
              raw: m,
            ))
        .toList();
    final disp = items.where((i) => i.estado == 'disponible').length;
    return (items: items, resumen: ResumenLocalidad(items.length, disp, items.length - disp));
  } catch (_) {
    return (items: <ItemAsiento>[], resumen: const ResumenLocalidad(0, 0, 0));
  }
}

MainAxisAlignment alineacionDe(Map<String, String> alineacion, String fila) {
  if (alineacion[fila] == 'izquierda') return MainAxisAlignment.start;
  if (alineacion[fila] == 'derecha') return MainAxisAlignment.end;
  return MainAxisAlignment.center;
}

List<T> enOrdenVisual<T>(Map<String, bool> ordenSillas, String fila, List<T> items) =>
    (ordenSillas[fila] ?? false) ? items.reversed.toList() : items;
