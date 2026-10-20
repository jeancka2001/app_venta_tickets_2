import '../core/api.dart';
import '../core/json.dart';

/* Tipos de descuento (%) por evento que ESTE vendedor puede aplicar a mano.
   El backend revalida y recalcula al registrar la compra. */

class DescuentoVendedor {
  final int id;
  final String nombre;
  final double porcentaje;
  final String? mensajeMotivo;
  /* 'base' = el % se resta del precio del boleto ANTES de IVA/comisión
     bancaria. 'final' (default) = el % se resta del total ya armado. */
  final String aplicaSobre;

  DescuentoVendedor(this.id, this.nombre, this.porcentaje, this.mensajeMotivo, this.aplicaSobre);

  factory DescuentoVendedor.fromJson(Map<String, dynamic> j) => DescuentoVendedor(
        ent(j['id']),
        str(j['nombre']),
        dbl(j['porcentaje']),
        strN(j['mensaje_motivo']),
        j['aplica_sobre'] == 'base' ? 'base' : 'final',
      );

  String get porcentajeTexto => porcentaje == porcentaje.roundToDouble() ? porcentaje.toStringAsFixed(0) : '$porcentaje';
}

Future<List<DescuentoVendedor>> obtenerDescuentosVendedor(String? codigoEvento, int? idOperador) async {
  if (codigoEvento == null || codigoEvento.isEmpty || idOperador == null || idOperador == 0) return [];
  try {
    final r = await dio.get('$urlBase/evento_descuentos',
        queryParameters: {'codigoEvento': codigoEvento, 'id_operador': idOperador}, options: hdr(apiHdr()));
    return asMapList(asMap(r.data)['data']).map(DescuentoVendedor.fromJson).toList();
  } catch (_) {
    return [];
  }
}

double _redondear2(double n) => (n * 100).roundToDouble() / 100;

/* Total con el % aplicado sobre el TOTAL FINAL. */
({double neto, double monto}) aplicarDescuento(double total, double porcentaje) {
  final neto = _redondear2(total * (1 - porcentaje / 100));
  return (neto: neto, monto: _redondear2(total - neto));
}
