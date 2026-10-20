import '../core/api.dart';
import '../core/json.dart';

/* Canje de entradas en puerta -- flasapi_speed_comnet (mikroti):
   1. Consulta: GET Boleteria/BoletoScan/:codigo (estado de canje del asiento).
   2. Canje: POST Boleteria/canjeticke2/:id_ticket -- canjea UNA entrada y
      responde 409 si ya estaba canjeada (dos puertas no la canjean dos veces).
   NO se usa Boleteria/canjear-qr: ese canjea TODAS las entradas de la compra. */

class BoletoCanje {
  final int? idTicket;
  final String? cedula;
  final String? localidad;
  final String? numeroEntrada;
  final String? canje;
  final String? codigoEvento;
  final String? concierto;
  final int idItem;
  final String? silla;
  final String? fila;
  final int? correlativo;
  final String idRegistraCompraCodigo;
  final String? nombreLocalidad;
  /* Completados con Boleteria/info-boleto (BoletoScan no los trae). */
  final int? idRegistraCompra;
  final String? nombreCompleto;

  BoletoCanje({
    this.idTicket,
    this.cedula,
    this.localidad,
    this.numeroEntrada,
    this.canje,
    this.codigoEvento,
    this.concierto,
    required this.idItem,
    this.silla,
    this.fila,
    this.correlativo,
    required this.idRegistraCompraCodigo,
    this.nombreLocalidad,
    this.idRegistraCompra,
    this.nombreCompleto,
  });

  bool get canjeado => (canje ?? '').trim().toUpperCase() == 'CANJEADO';

  String get descripcion {
    final partes = [if (fila != null && fila!.isNotEmpty) 'Fila $fila', if (silla != null && silla!.isNotEmpty) 'Silla $silla'];
    if (partes.isNotEmpty) return partes.join(' · ');
    if (numeroEntrada != null && numeroEntrada!.isNotEmpty) return 'Entrada N.º $numeroEntrada';
    if (correlativo != null) return 'Entrada N.º $correlativo';
    return 'Asiento #$idItem';
  }

  String get localidadLimpia => (nombreLocalidad ?? localidad ?? '').replaceAll(RegExp(r'__+'), '').trim();
}

class ResultadoConsultaCanje {
  final BoletoCanje? boleto;
  final String mensaje;
  ResultadoConsultaCanje(this.boleto, this.mensaje);
  bool get ok => boleto != null;
}

Future<ResultadoConsultaCanje> consultarBoletoCanje(String codigo) async {
  final cod = Uri.encodeComponent(codigo);
  try {
    final resultados = await Future.wait([
      dio.get('$urlMikroti/Boleteria/BoletoScan/$cod').then((r) => r.data),
      /* Solo para la orden de compra: si falla, la entrada se puede canjear igual. */
      dio.get('$urlMikroti/Boleteria/info-boleto/$cod').then((r) => r.data).catchError((_) => null),
    ]);
    final data = asMap(resultados[0]);
    final info = asMap(resultados[1]);
    if (truthy(data['estado']) && data['boleto'] != null) {
      final b = asMap(data['boleto']);
      final extra = (truthy(info['estado']) && info['tipo'] == 'asiento') ? asMap(info['data']) : <String, dynamic>{};
      return ResultadoConsultaCanje(
        BoletoCanje(
          idTicket: entN(b['id_ticket']),
          cedula: strN(b['cedula']),
          localidad: strN(b['localidad']),
          numeroEntrada: strN(b['numero_entrada']),
          canje: strN(b['canje']),
          codigoEvento: strN(b['codigoEvento']),
          concierto: strN(b['concierto']),
          idItem: ent(b['id_item']),
          silla: strN(b['silla']),
          fila: strN(b['fila']),
          correlativo: entN(b['correlativo']),
          idRegistraCompraCodigo: str(b['id_registra_compra']),
          nombreLocalidad: strN(b['nombre_localidad']),
          idRegistraCompra: entN(extra['id_registraCompra']),
          nombreCompleto: strN(extra['nombreCompleto']),
        ),
        '',
      );
    }
    return ResultadoConsultaCanje(null, strN(data['mensaje']) ?? 'No se encontró ninguna entrada con ese código.');
  } catch (_) {
    return ResultadoConsultaCanje(null, 'Error de conexión al consultar la entrada.');
  }
}

class ResultadoCanje {
  final bool ok;
  final bool yaCanjeado;
  final String mensaje;
  const ResultadoCanje(this.ok, {this.yaCanjeado = false, this.mensaje = ''});
}

Future<ResultadoCanje> canjearEntrada(int idTicket, String cedula, Map<String, dynamic> info) async {
  try {
    final r = await dio.post('$urlMikroti/Boleteria/canjeticke2/$idTicket', data: {'cedula': cedula, 'info': info});
    final data = asMap(r.data);
    if (truthy(data['estado'])) return const ResultadoCanje(true);
    return ResultadoCanje(false, mensaje: strN(data['mensaje']) ?? 'No se pudo canjear.');
  } catch (e) {
    if (statusDe(e) == 409) return const ResultadoCanje(false, yaCanjeado: true, mensaje: 'Ya fue canjeada.');
    return const ResultadoCanje(false, mensaje: 'Error de conexión al canjear.');
  }
}

/* Descanje de UNA entrada: vuelve a 'NO CANJEADO' solo si estaba canjeada
   (si no, 409) y queda registrado con el operador y el motivo. */
Future<ResultadoCanje> descanjearEntrada(int idTicket, String cedula, String motivo, Map<String, dynamic> info) async {
  try {
    final r = await dio.post('$urlMikroti/Boleteria/descanjeticke/$idTicket',
        data: {'cedula': cedula, 'motivo': motivo, 'info': info});
    final data = asMap(r.data);
    if (truthy(data['estado'])) return const ResultadoCanje(true);
    return ResultadoCanje(false, mensaje: strN(data['mensaje']) ?? 'No se pudo descanjear.');
  } catch (e) {
    final s = statusDe(e);
    if (s == 409) return const ResultadoCanje(false, mensaje: 'No estaba canjeada.');
    if (s == 404) {
      return const ResultadoCanje(false, mensaje: 'Servicio de descanje no disponible (falta desplegar el backend).');
    }
    return const ResultadoCanje(false, mensaje: 'Error de conexión al descanjear.');
  }
}
