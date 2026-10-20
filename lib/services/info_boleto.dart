import '../core/api.dart';
import '../core/json.dart';

/* "Escanear boleto" -- consulta Boleteria/info-boleto/:codigo de
   flasapi_speed_comnet (digital Y físico). No exige autenticación. */

class ResultadoInfoBoleto {
  final bool ok;
  /* 'asiento' | 'fisico' */
  final String tipo;
  final Map<String, dynamic> data;
  final String mensaje;
  ResultadoInfoBoleto.ok(this.tipo, this.data)
      : ok = true,
        mensaje = '';
  ResultadoInfoBoleto.error(this.mensaje)
      : ok = false,
        tipo = '',
        data = const {};
}

Future<ResultadoInfoBoleto> obtenerInfoBoleto(String codigo) async {
  try {
    final r = await dio.get('$urlMikroti/Boleteria/info-boleto/${Uri.encodeComponent(codigo)}');
    final data = asMap(r.data);
    if (truthy(data['estado']) && data['data'] != null) {
      return ResultadoInfoBoleto.ok(data['tipo'] == 'fisico' ? 'fisico' : 'asiento', asMap(data['data']));
    }
    return ResultadoInfoBoleto.error(strN(data['mensaje']) ?? 'Boleto no encontrado.');
  } catch (e) {
    if (statusDe(e) == 404) return ResultadoInfoBoleto.error('No se encontró ningún boleto con ese código.');
    return ResultadoInfoBoleto.error('Error de conexión al buscar el boleto.');
  }
}
