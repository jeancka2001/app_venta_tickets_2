import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import '../services/bloqueo_sesion.dart';
import '../services/documentos.dart';
import '../services/escaner.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/imagen_zoom.dart';

/* Métodos que requieren aprobación manual (Pendiente/Comprobar hasta que
   alguien confirma el depósito/transferencia). */
const _metodosManuales = ['Deposito', 'Transferencia'];
const _bancosValidos = ['Pichincha', 'Guayaquil'];

/* Palabras de relleno del texto libre del boleto impreso. */
const _rellenoAsiento = {
  'fila', 'filas', 'asiento', 'asientos', 'silla', 'sillas', 'mesa', 'mesas',
  'butaca', 'butacas', 'puesto', 'puestos', 'seat', 'row', 'numero', 'nro', 'num',
};

String _normalizar(String? s) {
  const con = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const sin = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  var r = (s ?? '').toLowerCase();
  for (var i = 0; i < con.length; i++) {
    r = r.replaceAll(con[i], sin[i].toLowerCase());
  }
  return r.trim();
}

List<String> _tokensAsiento(String? s) => RegExp(r'[a-z]+|\d+')
    .allMatches(_normalizar(s))
    .map((m) => m.group(0)!)
    .where((t) => !_rellenoAsiento.contains(t))
    .toList();

String _numeroDeSilla(String? silla) {
  final s = _normalizar(silla).replaceAll(RegExp(r'\s+'), '');
  if (s.contains('-s-')) return s.split('-s-').last;
  final m = RegExp(r'(\d+)$').firstMatch(s);
  return m?.group(1) ?? '';
}

bool _mismoNumero(String a, String b) =>
    RegExp(r'^\d+$').hasMatch(a) && RegExp(r'^\d+$').hasMatch(b) && int.parse(a) == int.parse(b);

/* Compara el texto libre del boleto impreso contra la etiqueta del boleto
   digital ("A-s-1"): solo fila/mesa y NÚMERO de asiento. */
bool _coincideConAsientoExistente(String filaAsiento, String? sillas) {
  if (sillas == null || sillas.isEmpty) return true;
  final base = _normalizar(sillas).replaceAll(RegExp(r'\s+'), '');
  final grupo = base.contains('-s-') ? base.split('-s-')[0] : '';
  final numero = _numeroDeSilla(sillas);
  if (grupo.isEmpty && numero.isEmpty) return true;
  final toks = _tokensAsiento(filaAsiento);
  if (toks.isEmpty) return false;
  final numeroOk = numero.isEmpty || toks.any((t) => _mismoNumero(t, numero));
  final grupoOk = grupo.isEmpty ||
      toks.any((t) => t == grupo || _mismoNumero(t, grupo)) ||
      (RegExp(r'^[a-z]+$').hasMatch(grupo) && !toks.any((t) => RegExp(r'^[a-z]+$').hasMatch(t)));
  return numeroOk && grupoOk;
}

class DetalleCompraPage extends StatefulWidget {
  final int id;
  const DetalleCompraPage({super.key, required this.id});

  @override
  State<DetalleCompraPage> createState() => _DetalleCompraPageState();
}

class _DetalleCompraPageState extends State<DetalleCompraPage> {
  Registro? _registro;
  bool _cargando = true;
  String _error = '';

  /* Datos del cliente (recibo y WhatsApp) -- se consultan aparte. */
  String _clienteNombre = '';
  String _clienteEmail = '';
  String _clienteMovil = '';

  String? _procesando;
  final _nuevoComentario = TextEditingController();

  /* ── Reemplazar por boleto físico ── */
  bool _mostrarBoletoFisico = false;
  final _codigoFisico = TextEditingController();
  final _focoFisico = FocusNode();
  Timer? _autoEnvio;
  final List<String> _codigosNuevos = [];
  final Map<String, String> _seccionPorCodigo = {};
  bool _buscandoCodigo = false;

  /* ── Comprobante(s) ── */
  List<String> _comprobantesExtra = [];
  final _numeroEdit = TextEditingController();
  List<Map<String, dynamic>>? _duplicados;
  String _mensajeDuplicado = '';
  bool _analizandoOcr = false;
  Map<String, dynamic>? _ocrResultado;
  String _ocrError = '';

  int get _idOperador => obtenerStaffData()?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _codigoFisico.addListener(_alEscribirCodigo);
    _cargar();
  }

  @override
  void dispose() {
    _autoEnvio?.cancel();
    for (final c in [_nuevoComentario, _codigoFisico, _numeroEdit]) {
      c.dispose();
    }
    _focoFisico.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      /* La ruta solo existe como POST en el backend. */
      final r = await dio.post('$urlBase/listarRegistros',
          data: {}, queryParameters: {'id_registro': widget.id}, options: hdr(msLoginAuthHeaders));
      final filas = asMapList(asMap(r.data)['data']);
      if (filas.isEmpty) {
        setState(() => _error = 'No se encontró el registro.');
        return;
      }
      final reg = Registro.fromJson(filas.first);
      setState(() {
        _registro = reg;
        _numeroEdit.text = str(reg.raw['numerTransacion']);
      });
      sinEsperar(dio
          .post('$urlBase/consultar_cedula', data: {'cedula': reg.cedula, 'email': ''}, options: hdr(apiHdr()))
          .then<void>((res) {
        final cli = asMap(res.data);
        if (cli['success'] == true && cli['data'] != null && mounted) {
          final d = asMap(cli['data']);
          setState(() {
            _clienteNombre = str(d['nombreCompleto']);
            _clienteEmail = str(d['email']);
            _clienteMovil = str(d['movil']);
          });
        }
      }));
      if (_metodosManuales.contains(reg.formaPago)) {
        sinEsperar(dio
            .get('$urlMikroti/Boleteria/comprobantes/${reg.id}', options: hdr(msLoginAuthHeaders))
            .then<void>((res) {
          final extra = asMap(res.data);
          if (truthy(extra['estado']) && mounted) {
            setState(() => _comprobantesExtra =
                asMapList(extra['data']).map((c) => str(c['url_imagen'])).where((u) => u.isNotEmpty).toList());
          }
        }));
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión al cargar el detalle.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  List<Map<String, dynamic>> get _boletos => _registro?.ticketUsuarios ?? [];
  bool get _todosCanjeados => _boletos.isNotEmpty && _boletos.every((b) => b['canje'] == 'CANJEADO');
  bool get _esManual => _registro != null && _metodosManuales.contains(_registro!.formaPago);
  bool get _puedeAprobar => _esManual && ['Pendiente', 'Comprobar'].contains(_registro!.estadoPago);
  String get _linkPago => str(_registro?.raw['link_pago'] ?? _registro?.raw['link_comprobante']);

  List<String> get _ocrAvisos {
    final o = _ocrResultado;
    final reg = _registro;
    if (o == null || reg == null) return [];
    final avisos = <String>[];
    final monto = o['monto'];
    if (monto is num && (monto - reg.total).abs() > 0.01) {
      avisos.add('El monto leído en el comprobante (\$${f2(monto)}) no coincide con el total de esta compra (\$${f2(reg.total)}).');
    }
    final banco = str(o['banco_receptor'] ?? o['banco_emisor']);
    if (banco.isNotEmpty && !_bancosValidos.any((b) => banco.toUpperCase().contains(b.toUpperCase()))) {
      avisos.add('El banco detectado ($banco) no coincide con ninguna de nuestras cuentas registradas.');
    }
    return avisos;
  }

  Future<void> _accion(String clave, Future<void> Function() fn) async {
    setState(() => _procesando = clave);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  Future<void> _postSimple(String clave, String url, Map<String, dynamic> body,
      {required String ok, required String falla, required String errorRed}) =>
      _accion(clave, () async {
        try {
          final r = await dio.post(url, data: body, options: hdr(apiHdr()));
          final data = asMap(r.data);
          if (data['success'] == true) {
            toast(ok);
            await _cargar();
          } else {
            toast(strN(data['message']) ?? falla);
          }
        } catch (_) {
          toast(errorRed);
        }
      });

  /* ── Anular compra ── */
  Future<void> _anular() async {
    final reg = _registro!;
    final si = await confirmar(
      context,
      titulo: '¿Anular esta compra?',
      mensaje: _boletos.isNotEmpty
          ? 'Esta compra tiene asientos asignados. Al anularla, sus asientos se liberarán y quedarán disponibles para la venta. ¿Deseas continuar?'
          : '¿Estás seguro de que deseas anular esta compra?',
      si: 'Sí, anular',
      no: 'No',
      peligro: true,
    );
    if (!si) return;
    await _postSimple('anular', '$urlBase/anularCompra', {'id': reg.id, 'id_usuario': 0, 'id_operador': _idOperador},
        ok: 'Compra anulada correctamente.', falla: 'No se pudo anular la compra.', errorRed: 'Error de conexión al anular.');
  }

  Future<void> _copiarLinkPago() async {
    if (_linkPago.isEmpty) return toast('No hay link de pago registrado en esta compra.');
    await Clipboard.setData(ClipboardData(text: _linkPago));
    toast('Link de pago copiado.');
  }

  Future<void> _generarLinkAsientos() => _accion('link-asientos', () async {
        try {
          final r = await dio.post('$urlBase/generar_link_asignacion',
              data: {'id_registraCompra': _registro!.id}, options: hdr(apiHdr()));
          final data = asMap(r.data);
          if (data['success'] == true && data['link'] != null) {
            await Clipboard.setData(ClipboardData(text: str(data['link'])));
            toast('Link de asignación de asientos copiado.');
          } else {
            toast(strN(data['message']) ?? 'No se pudo generar el link de asignación.');
          }
        } catch (_) {
          toast('Error de conexión al generar el link.');
        }
      });

  /* ── Aprobar pago pendiente (Deposito/Transferencia) ── */
  Future<void> _aprobarPago([String? banco]) {
    final reg = _registro!;
    return _postSimple(
      'aprobar',
      '$urlBase/registraPagos',
      {
        'id_usuario': _idOperador,
        'id_operador': _idOperador,
        'forma_pago': reg.formaPago,
        'link_comprobante': reg.raw['link_comprobante'],
        'id': reg.id,
        'numeroTransaccion': reg.raw['numerTransacion'],
        'cedula': reg.cedula,
        'estado': 'Pagado',
        'bancos': banco ?? reg.raw['banco'],
        'enviar_correo': true,
        'generar_ticket': true,
        'send_email': true,
        'notify': true,
        'notificar': true,
        'enviar_ticket': true,
      },
      ok: 'Pago aprobado — se generaron los boletos.',
      falla: 'No se pudo aprobar el pago.',
      errorRed: 'Error de conexión al aprobar el pago.',
    );
  }

  Future<void> _tocarAprobar() async {
    if (_registro?.formaPago == 'Deposito') {
      final i = await elegirOpcion(context,
          titulo: '¿En qué banco se recibió el depósito?', opciones: ['Banco Pichincha', 'Banco Guayaquil']);
      if (i != null) await _aprobarPago(i == 0 ? 'Pichincha' : 'Guayaquil');
    } else {
      await _aprobarPago();
    }
  }

  Future<void> _regenerarBoletos() => _postSimple('regenerar', '$urlBase/validar_existencia_asientos',
      {'id_registraCompra': _registro!.id, 'cedula': _registro!.cedula},
      ok: 'Boletos regenerados.',
      falla: 'No se pudieron regenerar los boletos.',
      errorRed: 'Error de conexión al regenerar los boletos.');

  Future<void> _canjearTodos() => _postSimple(
      'canjear', '$urlBase/canje_boleto', {'id_registraCompra': _registro!.id, 'canjeado': 'CANJEADO'},
      ok: 'Boletos canjeados.', falla: 'No se pudo canjear los boletos.', errorRed: 'Error de conexión al canjear.');

  /* ── PDF de un boleto puntual ── */
  Future<void> _verPdfBoleto(Map<String, dynamic> ticket) => _accion('pdf-${ticket['id']}', () async {
        try {
          final reg = _registro!;
          final r = await dio.post(urlTicketPdf,
              data: {'cedula': reg.cedula, 'codigoEvento': reg.codigoEvento, 'id_ticket_usuarios': [ticket['id']]},
              options: hdr(apiHdr()));
          final data = asMap(r.data);
          final link = data['link'] ?? asMap(data['data'])['link'] ?? data['url'];
          if (link != null) {
            await sinBloqueo(() => launchUrl(Uri.parse(str(link).replaceFirst('flash', 'api')),
                mode: LaunchMode.externalApplication));
          } else {
            toast('No se pudo obtener el PDF de este boleto.');
          }
        } catch (_) {
          toast('Error de conexión al pedir el PDF.');
        }
      });

  /* ── Imprimir / guardar recibo en PDF ── */
  Future<void> _imprimirRecibo() => _accion('recibo', () async {
        final reg = _registro!;
        final error = await imprimirRecibo(DatosFactura(
          id: reg.id,
          nombreConcierto: reg.nombreEvento,
          localidades: reg.infoConcierto
              .map((c) => LocalidadFactura(str(c['localidad_nombre']), str(c['cantidad'])))
              .toList(),
          formaPago: reg.formaPago,
          total: reg.total,
          cliente: _clienteNombre,
          correo: _clienteEmail,
          cedula: reg.cedula,
          fechaRegistro: reg.fechaCreacion,
          numeroComprobante: strN(reg.raw['numerTransacion']),
        ));
        if (error != null) toast(error);
      });

  void _contactarWhatsapp() {
    final digitos = _clienteMovil.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return toast('El cliente no tiene celular registrado.');
    final numero = digitos.startsWith('593') ? digitos : '593${digitos.replaceFirst(RegExp(r'^0'), '')}';
    sinEsperar(sinBloqueo(() =>
        launchUrl(Uri.parse('https://api.whatsapp.com/send?phone=$numero'), mode: LaunchMode.externalApplication)));
  }

  /* ── Reemplazar por boleto físico ── */
  int get _cantidadFisicaMax => _boletos.isNotEmpty ? _boletos.length : 1;

  Future<void> _buscarBoletoFisicoExistente(String codigo, int indice) async {
    final codigoEvento = _registro?.codigoEvento ?? '';
    if (codigoEvento.isEmpty) return;
    setState(() => _buscandoCodigo = true);
    try {
      final r = await dio.get('$urlBase/boletos_fisicos/buscar',
          queryParameters: {'codigoEvento': codigoEvento, 'codigo_barras': codigo}, options: hdr(apiHdr()));
      final data = asMap(r.data);
      final filas = asMapList(data['data']);
      if (data['success'] == true && filas.isNotEmpty) {
        final usado = filas.where((f) => f['estado'] != null && f['estado'] != 'Disponible').firstOrNull;
        if (usado != null) {
          _quitarCodigo(codigo);
          final motivo = usado['estado'] == 'Anulado' ? 'fue anulado' : 'ya fue vendido';
          final compra = usado['id_registraCompra'] != null ? ' en la compra #${usado['id_registraCompra']}' : '';
          toast('Este código $motivo$compra -- no se puede reutilizar.', color: C.rojo);
          return;
        }
        if (filas.length == 1) {
          final f = filas.first;
          final sillas = indice < _boletos.length ? strN(_boletos[indice]['sillas']) : null;
          final filaAsiento = str(f['fila_asiento']);
          if (sillas != null && sillas.isNotEmpty && !_coincideConAsientoExistente(filaAsiento, sillas)) {
            if (!mounted) return;
            final seguir = await confirmar(
              context,
              titulo: 'El boleto no coincide con el asiento',
              mensaje: 'Este boleto es de ${f['seccion']}${filaAsiento.isNotEmpty ? ' · $filaAsiento' : ''}, pero no '
                  'coincide con el asiento del boleto digital que se va a reemplazar. ¿Continuar de todas formas?',
              si: 'Está bien',
              no: 'Salir',
            );
            if (!seguir) {
              _quitarCodigo(codigo);
              return;
            }
            toast('Boleto agregado igual -- revisa que sea el correcto.');
          } else {
            toast('Boleto encontrado: ${f['seccion']}${filaAsiento.isNotEmpty ? ' · $filaAsiento' : ''}');
          }
          setState(() => _seccionPorCodigo[codigo] = str(f['seccion']));
        } else {
          toast('Ese código existe en ${filas.length} secciones -- se agrega igual, sin descontar del inventario.');
        }
      } else {
        toast('No se encontró ese código en el inventario -- se agrega igual.');
      }
    } catch (_) {
      /* Silencioso */
    } finally {
      if (mounted) setState(() => _buscandoCodigo = false);
    }
  }

  void _agregarCodigo([String? directo]) {
    _autoEnvio?.cancel();
    final codigo = (directo ?? _codigoFisico.text).trim();
    if (codigo.isEmpty) return;
    _codigoFisico.clear();
    if (_codigosNuevos.contains(codigo)) return;
    if (_codigosNuevos.length >= _cantidadFisicaMax) {
      toast('Ya escaneaste los $_cantidadFisicaMax boleto${_cantidadFisicaMax > 1 ? 's' : ''} de esta compra.');
      return;
    }
    final indice = _codigosNuevos.length;
    setState(() => _codigosNuevos.add(codigo));
    _buscarBoletoFisicoExistente(codigo, indice);
    _focoFisico.requestFocus();
  }

  void _alEscribirCodigo() {
    _autoEnvio?.cancel();
    if (!_mostrarBoletoFisico || _codigoFisico.text.trim().isEmpty) return;
    _autoEnvio = Timer(const Duration(milliseconds: 600), _agregarCodigo);
  }

  void _quitarCodigo(String codigo) => setState(() {
        _codigosNuevos.remove(codigo);
        _seccionPorCodigo.remove(codigo);
      });

  Future<void> _escanearConCamara() async {
    final r = await escanearBoletoFisico(titulo: 'Escanear boleto físico');
    if (r.ok && r.codigo != null) {
      _agregarCodigo(r.codigo);
    } else if (r.mensaje != null) {
      toast(r.mensaje!);
    }
  }

  Future<void> _confirmarBoletoFisico() => _accion('boleto-fisico', () async {
        final reg = _registro!;
        if (!_codigosNuevos.any((c) => _seccionPorCodigo[c] != null)) {
          toast('Ningún código coincidió con una sección del inventario.');
          return;
        }
        final resumen = <(String, bool, String)>[];
        try {
          for (var i = 0; i < _codigosNuevos.length; i++) {
            final codigo = _codigosNuevos[i];
            final seccion = _seccionPorCodigo[codigo];
            if (seccion == null) {
              resumen.add((codigo, false, 'Sin sección resuelta en el inventario.'));
              continue;
            }
            /* Reemplaza el QR del boleto digital en el mismo orden (1.º con 1.º). */
            final idAsiento = i < _boletos.length ? entN(_boletos[i]['id_localidades_items']) : null;
            try {
              final r = await dio.post('$urlBase/boletos_fisicos/asignar',
                  data: {
                    'codigoEvento': reg.codigoEvento,
                    'seccion': seccion,
                    'codigo_barras': codigo,
                    'id_registraCompra': reg.id,
                    'id_operador': _idOperador,
                    if (idAsiento != null && idAsiento != 0) 'id_localidades_items': idAsiento,
                  },
                  options: hdr(apiHdr()));
              final data = asMap(r.data);
              final ok = data['success'] == true;
              resumen.add((codigo, ok, strN(data['message']) ?? (ok ? 'Vinculado.' : 'No se pudo vincular.')));
            } catch (_) {
              resumen.add((codigo, false, 'Error de conexión al vincular este código.'));
            }
          }
          await dio.post('$urlBase/canje_boleto',
              data: {'id_registraCompra': reg.id, 'canjeado': 'CANJEADO', 'id_operador': _idOperador, 'id_usuario': 0},
              options: hdr(apiHdr()));
          setState(() {
            _mostrarBoletoFisico = false;
            _codigosNuevos.clear();
            _seccionPorCodigo.clear();
          });
          await _cargar();
          if (resumen.every((r) => r.$2)) {
            toast('Boleto(s) físico(s) asignado(s) y compra canjeada.');
          } else if (mounted) {
            await informar(context,
                titulo: 'Vinculación de boletos físicos',
                mensaje: resumen.map((r) => '${r.$2 ? '✓' : '✗'} ${r.$1}: ${r.$2 ? 'vinculado' : r.$3}').join('\n'));
          }
        } catch (_) {
          toast('Error de conexión al asignar el boleto físico.');
        }
      });

  /* ── Comentarios ── */
  Future<void> _agregarComentario() async {
    final texto = _nuevoComentario.text.trim();
    if (texto.isEmpty) return;
    await _accion('comentario', () async {
      try {
        final r = await dio.post('$urlBase/Comentario_registro',
            data: {'id_registro': widget.id, 'id_operador': _idOperador, 'comentario': texto}, options: hdr(apiHdr()));
        final data = asMap(r.data);
        if (data['success'] == true) {
          _nuevoComentario.clear();
          await _cargar();
        } else {
          toast(strN(data['message']) ?? 'No se pudo guardar el comentario.');
        }
      } catch (_) {
        toast('Error de conexión al guardar el comentario.');
      }
    });
  }

  /* ── Añadir un comprobante adicional (foto o galería) ── */
  Future<void> _agregarComprobanteExtra() async {
    final origen =
        await elegirOpcion(context, titulo: 'Añadir comprobante', opciones: ['Tomar foto', 'Elegir de la galería']);
    if (origen == null) return;
    final foto = await sinBloqueo(() => ImagePicker().pickImage(
        source: origen == 0 ? ImageSource.camera : ImageSource.gallery, imageQuality: 85, maxWidth: 2000));
    if (foto == null) return;
    setState(() {
      _ocrResultado = null;
      _ocrError = '';
    });
    await _accion('comprobante-extra', () async {
      final url = await subirImagen(foto.path);
      if (url == null) return toast('No se pudo subir la imagen.');
      try {
        final r = await dio.post('$urlMikroti/Boleteria/comprobantes',
            data: {'id_registraCompra': _registro!.id, 'url_imagen': url}, options: hdr(apiHdr()));
        final data = asMap(r.data);
        if (truthy(data['estado'])) {
          setState(() => _comprobantesExtra = [..._comprobantesExtra, url]);
          toast('Comprobante agregado.');
          _analizarComprobante(url);
        } else {
          toast(strN(data['mensaje']) ?? 'No se pudo agregar el comprobante.');
        }
      } catch (_) {
        toast('Error de conexión al subir el comprobante.');
      }
    });
  }

  /* OCR del comprobante recién subido: autocompleta el número si está vacío. */
  Future<void> _analizarComprobante(String urlImagen) async {
    setState(() {
      _analizandoOcr = true;
      _ocrError = '';
    });
    try {
      final r = await dio.post(urlOcrComprobante,
          data: {'url_imagen': urlImagen, 'request_id': '${DateTime.now().millisecondsSinceEpoch}', 'guardar_bd': false},
          options: hdr(jsonHdr));
      final resp = asMap(r.data);
      if (!truthy(resp['success']) && !truthy(resp['estado'])) {
        setState(() => _ocrError =
            'No se pudo analizar la imagen automáticamente. Completa el número de comprobante manualmente.');
        return;
      }
      final extraido = asMap(resp['data']);
      setState(() {
        _ocrResultado = extraido;
        final numero = str(extraido['numero_comprobante'] ?? extraido['referencia']).trim();
        if (_numeroEdit.text.trim().isEmpty) _numeroEdit.text = numero;
      });
    } catch (_) {
      setState(() =>
          _ocrError = 'No se pudo analizar la imagen automáticamente. Completa el número de comprobante manualmente.');
    } finally {
      if (mounted) setState(() => _analizandoOcr = false);
    }
  }

  Future<void> _guardarNumeroTransaccion() async {
    final numero = _numeroEdit.text.trim();
    if (numero.isEmpty) return toast('Ingresa un número de comprobante.');
    await _accion('num-transaccion', () async {
      try {
        final r = await dio.post('$urlBase/ActualizarNumeroTransaccion',
            data: {
              'id_registraCompra': _registro!.id,
              'numeroTransaccion': numero,
              'id_usuario': 0,
              'id_operador': _idOperador,
            },
            options: hdr(apiHdr()));
        final data = asMap(r.data);
        if (data['success'] == true) {
          _registro!.raw['numerTransacion'] = numero;
          toast('Número de comprobante actualizado.');
        } else {
          toast(strN(data['message']) ?? 'No se pudo actualizar el número.');
        }
      } catch (_) {
        toast('Error de conexión al actualizar el número.');
      }
    });
  }

  Future<void> _verificarDuplicado() async {
    final numero = (_numeroEdit.text.isNotEmpty ? _numeroEdit.text : str(_registro?.raw['numerTransacion'])).trim();
    if (numero.isEmpty) return toast('No hay número de comprobante para verificar.');
    setState(() {
      _duplicados = null;
      _mensajeDuplicado = '';
    });
    await _accion('verificar-duplicado', () async {
      try {
        final r = await dio.post('$urlBase/BuscarNumeroTransaccion',
            data: {'numeroTransaccion': numero}, options: hdr(apiHdr()));
        final data = asMap(r.data);
        setState(() {
          if (data['success'] == true && data['data'] is List) {
            final todos = asMapList(data['data']);
            _duplicados = todos.where((r) => ent(r['id']) != _registro?.id).toList();
            _mensajeDuplicado = 'Este número aparece en ${todos.length} compra(s).';
          } else if (data['success'] == true) {
            _mensajeDuplicado = 'Comprobante único, no se encontró en otra compra.';
          } else {
            _mensajeDuplicado = strN(data['message']) ?? 'No se encontró ese número de comprobante.';
          }
        });
      } catch (_) {
        toast('Error de conexión al verificar el comprobante.');
      }
    });
  }

  Future<void> _habilitarReenvio() => _accion('reenvio', () async {
        try {
          final r = await dio.get('$urlMikrotiV2/api/reenvio/${_registro!.id}', options: hdr(msLoginAuthHeaders));
          if (truthy(asMap(r.data)['estado'])) {
            toast('Se habilitó un nuevo envío de boletos.');
            await _cargar();
          } else {
            toast('No se pudo habilitar el reenvío.');
          }
        } catch (_) {
          toast('Error de conexión al habilitar el reenvío.');
        }
      });

  /* ── UI ── */

  Widget _boton(String clave, String texto, IconData icono, Future<void> Function() fn,
          {bool primario = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: BotonAccion(texto,
            icono: icono, primario: primario, color: color, cargando: _procesando == clave, onPressed: fn),
      );

  Widget _tarjetaComprobante(Registro reg) {
    final principal = str(reg.raw['link_comprobante']);
    final imagenes = [if (principal.isNotEmpty) principal, ..._comprobantesExtra];
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const TituloTarjeta('Comprobante', icono: Icons.image_outlined),
        if (imagenes.isEmpty)
          Text('No se ha subido ninguna imagen de comprobante.', style: TextStyle(color: colorTenue(context)))
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imagenes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => verImagen(context, imagenes[i], 'Comprobante'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(imagenes[i],
                      width: 96, height: 96, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Sube el comprobante que genera la opción "Compartir" del banco o de Deuna, no una captura de pantalla — '
          'ese trae toda la información necesaria (banco, monto, número de comprobante).',
          style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
        ),
        const SizedBox(height: 8),
        _boton('comprobante-extra', 'Añadir comprobante', Icons.add, _agregarComprobanteExtra),
        if (_analizandoOcr)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Row(children: [MiniSpinner(color: C.azul), SizedBox(width: 10), Text('Analizando comprobante…')]),
          ),
        if (!_analizandoOcr && _ocrError.isNotEmpty) TextoError('⚠ $_ocrError'),
        if (!_analizandoOcr && _ocrResultado != null) _panelOcr(),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _numeroEdit,
              decoration: const InputDecoration(labelText: 'Número de comprobante / transacción', hintText: 'Ej. 000123456'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: _procesando == 'num-transaccion' ? null : _guardarNumeroTransaccion,
            icon: _procesando == 'num-transaccion' ? const MiniSpinner() : const Icon(Icons.save_outlined),
          ),
          IconButton.outlined(
            onPressed: _procesando == 'verificar-duplicado' ? null : _verificarDuplicado,
            icon: const Icon(Icons.search),
          ),
        ]),
        if (_mensajeDuplicado.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_mensajeDuplicado,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: (_duplicados?.isNotEmpty ?? false) ? C.rojoOscuro : C.verde)),
          ),
        for (final d in _duplicados ?? const <Map<String, dynamic>>[])
          TextButton(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            onPressed: () => ir(DetalleCompraPage(id: ent(d['id']))),
            child: Text('Compra #${d['id']}${d['cedula'] != null ? ' · ${d['cedula']}' : ''}'),
          ),
      ]),
    );
  }

  Widget _panelOcr() {
    final o = _ocrResultado!;
    final v = asMap(o['validacion']);
    final numero = str(o['numero_comprobante'] ?? o['referencia']);
    final banco = str(o['banco_receptor'] ?? o['banco_emisor']);
    Widget dato(String a, String b) => Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: C.gris, fontSize: 13))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.azulOscuro)),
        ]);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('✨ Datos detectados automáticamente', style: TextStyle(fontWeight: FontWeight.w700, color: C.azul)),
        const SizedBox(height: 6),
        if (numero.isNotEmpty) dato('N° comprobante', numero),
        if (o['monto'] is num) dato('Monto', '\$${f2(o['monto'] as num)}'),
        if (banco.isNotEmpty) dato('Banco', banco),
        if (str(o['fecha']).isNotEmpty) dato('Fecha', str(o['fecha'])),
        if (v['posible_adulteracion'] == true || v['nivel_sospecha'] == 'alto')
          const Text('⚠ Esta imagen podría no ser válida — revísala antes de aprobar.',
              style: TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600)),
        for (final a in _ocrAvisos) Text('⚠ $a', style: const TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('El número se autocompletó abajo -- verifícalo antes de guardar.',
            style: TextStyle(fontSize: 12, color: C.gris)),
      ]),
    );
  }

  Widget _panelBoletoFisico() {
    final lleno = _codigosNuevos.length >= _cantidadFisicaMax;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: C.borde),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${_codigosNuevos.length} de $_cantidadFisicaMax boleto${_cantidadFisicaMax > 1 ? 's' : ''} escaneado'
          '${_cantidadFisicaMax > 1 ? 's' : ''}. Escanea el código con el lector (o cámara) o tecléalo y presiona Enter.'
          '${_buscandoCodigo ? ' Buscando…' : ''}',
          style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
        ),
        if (_boletos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'El 1.º código escaneado reemplaza el QR del 1.º boleto digital de esta compra, el 2.º al 2.º, y así -- '
              'revisa abajo que cada código quede junto al boleto correcto.',
              style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codigoFisico,
              focusNode: _focoFisico,
              enabled: !lleno,
              autofocus: true,
              onSubmitted: (_) => _agregarCodigo(),
              decoration: const InputDecoration(hintText: 'Código de barras del boleto físico'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(onPressed: lleno ? null : _escanearConCamara, icon: const Icon(Icons.photo_camera_outlined)),
        ]),
        for (final (i, c) in _codigosNuevos.indexed)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (i < _boletos.length && str(_boletos[i]['sillas']).isNotEmpty) '→ ${_boletos[i]['sillas']}',
              if (_seccionPorCodigo[c] != null) 'Impreso: ${_seccionPorCodigo[c]}',
            ].join('\n')),
            trailing: IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: () => _quitarCodigo(c)),
          ),
        const SizedBox(height: 8),
        BotonAccion('Asignar y canjear',
            primario: true,
            cargando: _procesando == 'boleto-fisico',
            onPressed: _codigosNuevos.isEmpty ? null : _confirmarBoletoFisico),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reg = _registro;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de compra'),
        actions: [IconButton(tooltip: 'Recargar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando && reg == null
          ? const Cargando()
          : (_error.isNotEmpty && reg == null)
              ? MensajeVacio(_error, error: true)
              : reg == null
                  ? const SizedBox.shrink()
                  : Contenido(onRefresh: _cargar, children: [
                      Tarjeta(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TituloTarjeta('Compra #${reg.id}'),
                          Text(reg.nombreEvento, style: TextStyle(fontWeight: FontWeight.w700, color: colorAcento(context))),
                          const SizedBox(height: 6),
                          FilaDato('Cliente', _clienteNombre.isNotEmpty ? _clienteNombre : reg.cedula),
                          FilaDato('Cédula', reg.cedula),
                          FilaDato('Localidad', reg.localidadNombre.isEmpty ? '—' : reg.localidadNombre),
                          FilaDato('Cantidad', '${reg.boletosEsperados}'),
                          FilaDato('Forma de pago', reg.formaPago),
                          FilaDato('Fecha', formatFecha(reg.fechaCreacion, conHora: true)),
                          FilaDato('Estado', null, valorWidget: insigniaEstadoPago(reg.estadoPago)),
                          if (_boletos.isNotEmpty)
                            FilaDato('Envío de boletos', null,
                                valorWidget: truthy(reg.raw['estado_envio'])
                                    ? const Insignia('Enviado', fondo: Color(0xFFD4F1DD), color: Color(0xFF155724))
                                    : const Insignia('No enviado', fondo: C.naranjaFondo, color: Color(0xFFB45309))),
                          if (dbl(reg.raw['descuento_monto']) > 0)
                            FilaDato(
                              'Descuento${reg.raw['descuento_nombre'] != null ? ' (${reg.raw['descuento_nombre']})' : ''}'
                              '${dbl(reg.raw['descuento_pct']) > 0 ? ' -${dbl(reg.raw['descuento_pct'])}%' : ''}',
                              '-\$${f2(dbl(reg.raw['descuento_monto']))}',
                            ),
                          const Divider(),
                          FilaDato('Total', '\$${f2(reg.total)}', destacado: true),
                        ]),
                      ),
                      if (reg.faltanBoletos)
                        Aviso('La compra está pagada pero solo se generaron ${_boletos.length} de ${reg.boletosEsperados} boletos.'),
                      if (_esManual) _tarjetaComprobante(reg),
                      Tarjeta(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const TituloTarjeta('Acciones'),
                          if (_puedeAprobar)
                            _boton('aprobar', 'Aprobar pago', Icons.check_circle_outline, _tocarAprobar, primario: true),
                          if (reg.faltanBoletos)
                            _boton('regenerar', 'Regenerar boletos faltantes', Icons.refresh, _regenerarBoletos),
                          if (_boletos.isNotEmpty && !_todosCanjeados)
                            _boton('canjear', 'Canjear todos los boletos', Icons.done_all, _canjearTodos),
                          if (_boletos.isNotEmpty)
                            _boton('reenvio', 'Habilitar nuevo envío de boletos', Icons.mail_outline, _habilitarReenvio),
                          if (reg.estadoPago == 'Pagado')
                            _boton('link-asientos', 'Copiar link para asignar asientos', Icons.person_add_alt,
                                _generarLinkAsientos),
                          if (_linkPago.isNotEmpty) _boton('link-pago', 'Copiar link de pago', Icons.link, _copiarLinkPago),
                          _boton('recibo', 'Imprimir recibo', Icons.print_outlined, _imprimirRecibo),
                          _boton('whatsapp', 'Contactar por WhatsApp', Icons.chat_outlined, () async => _contactarWhatsapp()),
                          if (reg.estadoPago != 'Anulado')
                            _boton('toggle-fisico', _mostrarBoletoFisico ? 'Cerrar' : 'Reemplazar por boleto físico',
                                Icons.qr_code_scanner, () async {
                              setState(() => _mostrarBoletoFisico = !_mostrarBoletoFisico);
                            }),
                          if (_mostrarBoletoFisico) _panelBoletoFisico(),
                          if (reg.estadoPago != 'Anulado')
                            _boton('anular', 'Anular compra', Icons.block, _anular, color: C.rojo),
                        ]),
                      ),
                      Tarjeta(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const TituloTarjeta('Comentarios', icono: Icons.chat_bubble_outline),
                          if (asList(reg.raw['comentarios']).isEmpty)
                            Text('Sin comentarios todavía.', style: TextStyle(color: colorTenue(context))),
                          for (final c in asMapList(reg.raw['comentarios']))
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: esOscuro(context) ? const Color(0xFF1A2035) : const Color(0xFFF4F6FB),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(str(c['comentario']), style: TextStyle(color: colorTexto(context))),
                                const SizedBox(height: 4),
                                Text(str(c['operador'] ?? c['name'], 'Operador'),
                                    style: TextStyle(fontSize: 12, color: colorTenue(context))),
                              ]),
                            ),
                          TextField(
                            controller: _nuevoComentario,
                            minLines: 2,
                            maxLines: 6,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(hintText: 'Escribe un comentario…'),
                          ),
                          const SizedBox(height: 8),
                          BotonAccion('Agregar comentario',
                              icono: Icons.note_add_outlined,
                              cargando: _procesando == 'comentario',
                              onPressed: _nuevoComentario.text.trim().isEmpty ? null : _agregarComentario),
                        ]),
                      ),
                      Tarjeta(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TituloTarjeta('Boletos generados (${_boletos.length})', icono: Icons.confirmation_number_outlined),
                          if (_boletos.isEmpty)
                            Text(
                              reg.estadoPago == 'Pagado'
                                  ? 'Aún no se han generado boletos para esta compra.'
                                  : 'Los boletos se generan cuando la compra queda pagada.',
                              style: TextStyle(color: colorTenue(context)),
                            ),
                          for (final (i, b) in _boletos.indexed)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                b['canje'] == 'CANJEADO' ? Icons.check_circle_outline : Icons.confirmation_number_outlined,
                                color: b['canje'] == 'CANJEADO' ? C.verde : colorAcento(context),
                              ),
                              title: Text(str(b['sillas']).isNotEmpty ? str(b['sillas']) : 'Boleto ${i + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(b['canje'] == 'CANJEADO' ? 'Canjeado' : 'Sin canjear'),
                              trailing: b['id'] == null
                                  ? null
                                  : TextButton(
                                      onPressed: _procesando == 'pdf-${b['id']}' ? null : () => _verPdfBoleto(b),
                                      child: _procesando == 'pdf-${b['id']}'
                                          ? const MiniSpinner(color: C.azul)
                                          : const Text('PDF'),
                                    ),
                            ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ]),
    );
  }
}
