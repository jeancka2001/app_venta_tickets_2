import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import '../services/bloqueo_sesion.dart';
import '../services/descuentos.dart';
import '../services/escaner.dart';
import '../services/metodos_pago.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import 'dashboard_page.dart';
import 'detalle_compra_page.dart';
import 'login_page.dart';

class _MetodoItem {
  final String key;
  final String label;
  final double pct;
  final String desc;
  final CategoriaMetodo categoria;
  final bool aplicaComisionBoleto;
  const _MetodoItem(this.key, this.label, this.pct, this.desc, this.categoria, this.aplicaComisionBoleto);
}

class _ResultadoFisico {
  final String codigo;
  final bool ok;
  final String mensaje;
  final String? etiqueta;
  _ResultadoFisico(this.codigo, this.ok, this.mensaje, this.etiqueta);
}

class _Cuenta {
  final String banco;
  final String valor;
  final String cuenta;
  final String ruc;
  final String tipo;
  const _Cuenta(this.banco, this.valor, this.cuenta, this.ruc, this.tipo);
}

const _cuentas = [
  _Cuenta('Banco Pichincha', 'Pichincha', '2100298093', '0993377293001', 'Corriente'),
  _Cuenta('Banco Guayaquil', 'Guayaquil', '18057352', '0993377293001', 'Corriente'),
];

/* "A-s-1" -> "A · Silla 1". Si no trae "-s-" se muestra tal cual. */
String? formatearEtiquetaAsiento(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.contains('-s-')) {
    final partes = raw.split('-s-');
    return partes[1].isNotEmpty ? '${partes[0]} · Silla ${partes[1]}' : partes[0];
  }
  return raw;
}

enum _Fase { seleccion, procesando, comprobante, exito }

class PagoPage extends StatefulWidget {
  final DatosPago datos;
  const PagoPage({super.key, required this.datos});

  @override
  State<PagoPage> createState() => _PagoPageState();
}

class _PagoPageState extends State<PagoPage> {
  DatosPago get st => widget.datos;
  Cliente get cliente => st.cliente;

  String _metodo = '';
  List<_MetodoItem>? _metodosDisponibles;
  bool _cargando = false;
  String _error = '';
  String _urlPago = '';
  _Fase _fase = _Fase.seleccion;

  /* Solo métodos locales -- "canjear" no se manda nunca desde aquí salvo
     boleto físico: el canje real se hace al ingresar al evento. */
  bool _enviarCorreo = true;
  /* Duna: QR (el cliente lo escanea) o link para enviar. */
  String _dunaModo = 'qr';

  /* Tarjeta física (POS): lote y referencia, obligatorios, máx. 6 dígitos. */
  final _tarjetaLote = TextEditingController();
  final _tarjetaReferencia = TextEditingController();

  /* Descuentos que este vendedor puede aplicar (uno por venta). */
  List<DescuentoVendedor> _descuentos = [];
  int? _descuentoSel;

  /* Boleto físico (impreso de antemano): por defecto. */
  String _tipoBoleto = 'fisico';
  final _codigoFisico = TextEditingController();
  final _focoFisico = FocusNode();
  Timer? _autoEnvio;
  final List<String> _codigosFisicos = [];
  final Map<String, String> _seccionPorCodigo = {};
  final Map<String, String> _filaAsientoPorCodigo = {};
  bool _buscandoCodigo = false;
  List<_ResultadoFisico> _resumenFisico = [];

  /* Transferencia/Depósito: tras crear la orden (Pendiente) se pide el comprobante. */
  int? _idRegistro;
  String _bancoComprobante = '';
  final _numeroTransaccion = TextEditingController();
  File? _comprobanteArchivo;
  String _comprobanteUrl = '';
  bool _subiendoComprobante = false;
  String _errorComprobante = '';
  bool _comprobanteAdjuntado = false;
  bool _analizandoOcr = false;
  Map<String, dynamic>? _ocrResultado;
  String _ocrError = '';

  bool _anulando = false;

  @override
  void initState() {
    super.initState();
    _cargarMetodos();
    _cargarDescuentos();
    _codigoFisico.addListener(_alEscribirCodigo);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focoFisico.requestFocus());
  }

  @override
  void dispose() {
    _autoEnvio?.cancel();
    for (final c in [_tarjetaLote, _tarjetaReferencia, _codigoFisico, _numeroTransaccion]) {
      c.dispose();
    }
    _focoFisico.dispose();
    super.dispose();
  }

  Future<void> _cargarMetodos() async {
    /* Se relee la sesión: con el JWT vencido el backend no podría filtrar
       los métodos asignados a este vendedor. */
    if (obtenerStaffData() == null) {
      logoutStaff();
      toast('Tu sesión expiró. Vuelve a iniciar sesión.', color: C.rojo);
      irComoRaiz(const LoginPage());
      return;
    }
    final activos = await obtenerMetodosPagoActivos(st.codigoEvento);
    final porMetodo = {for (final a in activos) a.metodo: a};
    /* Se filtra por PRESENCIA en la respuesta: si el vendedor tiene métodos
       restringidos el backend devuelve solo esos. Lista vacía (falla de red)
       muestra todos para no dejarlo sin opciones. */
    final lista = metodosConfigurables.where((m) => activos.isEmpty || porMetodo.containsKey(m.key)).map((m) {
      final cfg = porMetodo[m.key];
      final pct = cfg?.comisionPorcentaje ?? m.pctDefault;
      return _MetodoItem(m.key, m.label, pct, pct > 0 ? '+${(pct * 100).round()}% comisión' : 'Sin comisión', m.categoria,
          cfg?.aplicaComisionBoleto ?? true);
    }).toList();
    if (!mounted) return;
    setState(() {
      _metodosDisponibles = lista;
      if (_metodo.isEmpty && lista.isNotEmpty) _metodo = lista.first.key;
    });
  }

  Future<void> _cargarDescuentos() async {
    final lista = await obtenerDescuentosVendedor(st.codigoEvento, obtenerStaffData()?.id);
    if (!mounted) return;
    setState(() {
      _descuentos = lista;
      /* Preseleccionado el primero si el vendedor tiene alguno. */
      _descuentoSel = lista.isNotEmpty ? lista.first.id : null;
    });
  }

  _MetodoItem get _met =>
      _metodosDisponibles?.where((x) => x.key == _metodo).firstOrNull ??
      const _MetodoItem('', '', 0, '', CategoriaMetodo.local, true);

  bool get _esLocal => _met.categoria == CategoriaMetodo.local;
  bool get _esTransferencia => _met.categoria == CategoriaMetodo.transferencia;
  bool get _esDuna => _met.key == 'Duna';
  bool get _esQrDuna => _esDuna && _dunaModo == 'qr';
  /* Métodos que el backend deja "Pagado" en el mismo registraCompra.
     "Efectivo" (Speed/Comnet) queda afuera: el backend lo deja Pendiente. */
  bool get _quedaPagadoAlInstante => const ['Efectivo-Local', 'Tarjeta-Local', 'Efectivo-QR'].contains(_met.key);

  int get _factor => st.factorBoletos.clamp(1, 10);
  /* Precios a cobrar (paquetes): con x2, 2 entradas = 1 precio. */
  int get _cantidadCobro => _factor > 1 ? (st.cantidad / _factor).ceil() : st.cantidad;
  double get _ivaRate => ivaRateDe(st.iva);

  DescuentoVendedor? get _descuentoActivo => _descuentos.where((d) => d.id == _descuentoSel).firstOrNull;
  /* "sobre precio base": el % se resta del precio ANTES de IVA/comisión
     bancaria (que se recalculan); "final" (default): se resta del total. */
  bool get _aplicaSobreBase => _descuentoActivo?.aplicaSobre == 'base';
  double get _precioParaCalculo =>
      _aplicaSobreBase ? st.precio * (1 - _descuentoActivo!.porcentaje / 100) : st.precio;

  DesgloseTotal get _desglose => calcularTotalConComision(_precioParaCalculo, _cantidadCobro, st.comisionBoleto * _factor,
      _ivaRate, _met.pct, _met.aplicaComisionBoleto);

  /* En modo "base" el total ya sale NETO (el backend no lo vuelve a tocar);
     en "final" es el BRUTO y el backend aplica el %. */
  double get _totalACobrar {
    final t = _desglose.total;
    if (_aplicaSobreBase) return t;
    final d = _descuentoActivo;
    return d != null ? aplicarDescuento(t, d.porcentaje).neto : t;
  }

  double get _montoDescuento {
    final d = _descuentoActivo;
    if (d == null) return 0;
    if (_aplicaSobreBase) return ((st.precio - _precioParaCalculo) * _cantidadCobro * 100).roundToDouble() / 100;
    return aplicarDescuento(_desglose.total, d.porcentaje).monto;
  }

  /* El backend solo avisa de posible adulteración de la imagen, no si el
     monto/banco coinciden con ESTA venta -- eso se revisa aquí. */
  List<String> get _ocrAvisos {
    final o = _ocrResultado;
    if (o == null) return [];
    final avisos = <String>[];
    final monto = o['monto'];
    if (monto is num && (monto - _totalACobrar).abs() > 0.01) {
      avisos.add('El monto leído en el comprobante (\$${f2(monto)}) no coincide con el total a cobrar (\$${f2(_totalACobrar)}).');
    }
    final banco = str(o['banco_receptor'] ?? o['banco_emisor']);
    if (banco.isNotEmpty && !_cuentas.any((c) => banco.toUpperCase().contains(c.valor.toUpperCase()))) {
      avisos.add('El banco detectado ($banco) no coincide con ninguna de nuestras cuentas registradas.');
    }
    return avisos;
  }

  bool get _ocrSospechoso {
    final v = asMap(_ocrResultado?['validacion']);
    return v['posible_adulteracion'] == true || v['nivel_sospecha'] == 'alto';
  }

  /* Comprobante subido pero sin validación automática: la pantalla final NO
     debe dar a entender que ya quedó aprobado. */
  bool get _comprobanteSospechoso =>
      _esTransferencia &&
      _comprobanteAdjuntado &&
      (_ocrError.isNotEmpty || _ocrResultado == null || _ocrAvisos.isNotEmpty || _ocrSospechoso);

  bool get _esFisico => _tipoBoleto == 'fisico';
  /* Un boleto físico por asiento elegido, o la cantidad si es correlativo. */
  int get _cantidadFisicaMax => st.idSillas.isNotEmpty ? st.idSillas.length : st.cantidad;
  bool get _faltanCodigosFisicos => _esFisico && _codigosFisicos.length < _cantidadFisicaMax;
  bool get _esTarjetaFisica => _metodo == 'Tarjeta-Local';
  static final _digitosTarjeta = RegExp(r'^\d{1,6}$');
  bool get _faltanDatosTarjetaFisica =>
      _esTarjetaFisica &&
      (!_digitosTarjeta.hasMatch(_tarjetaLote.text) || !_digitosTarjeta.hasMatch(_tarjetaReferencia.text));

  int get _idOperador => obtenerStaffData()?.id ?? 0;

  /* ── Anular al retroceder con una orden creada pero sin pagar ── */
  Future<void> _manejarAtras() async {
    final id = _idRegistro;
    /* Ya pagada (métodos locales) o todavía generándose: atrás no hace nada;
       para salir está "Vender otra entrada". */
    if (id == null || _quedaPagadoAlInstante) return;
    final anular = await confirmar(
      context,
      titulo: '¿Anular esta compra?',
      mensaje: 'Esta compra (#$id) todavía no está pagada. Si retrocedes, se anulará y los asientos quedarán libres '
          'para volver a elegirlos.',
      si: 'Anular y volver',
      no: 'Seguir aquí',
      peligro: true,
    );
    if (anular) await _anularYVolver(id);
  }

  Future<void> _anularYVolver(int id) async {
    setState(() => _anulando = true);
    try {
      final r = await dio.post('$urlBase/anularCompraPendiente',
          data: {'id': id, 'id_usuario': cliente.id, 'id_operador': _idOperador}, options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true) {
        toast('Compra anulada. Los asientos quedaron libres para elegir de nuevo.');
        if (mounted) Navigator.of(context).pop();
      } else if (mounted) {
        await informar(context,
            titulo: 'No se puede anular',
            mensaje: strN(data['message']) ??
                'Esta compra ya no se puede anular -- puede que ya haya sido pagada o confirmada.');
      }
    } catch (_) {
      if (mounted) {
        await informar(context,
            titulo: 'No se puede anular',
            mensaje: 'Error de conexión al anular la compra. Intenta de nuevo o revisa el detalle desde Buscar.');
      }
    } finally {
      if (mounted) setState(() => _anulando = false);
    }
  }

  /* ── Boletos físicos ── */

  /* Busca el código en el inventario de boletos físicos del evento solo para
     MOSTRAR qué sección/fila-asiento trae. */
  Future<void> _buscarBoletoFisico(String codigo) async {
    setState(() => _buscandoCodigo = true);
    try {
      final r = await dio.get('$urlBase/boletos_fisicos/buscar',
          queryParameters: {'codigoEvento': st.codigoEvento, 'codigo_barras': codigo}, options: hdr(apiHdr()));
      final data = asMap(r.data);
      final filas = asMapList(data['data']);
      if (data['success'] == true && filas.isNotEmpty) {
        /* Si en cualquier sección ya está Vendido/Anulado se rechaza. */
        final usado = filas.where((f) => f['estado'] != null && f['estado'] != 'Disponible').firstOrNull;
        if (usado != null) {
          _quitarCodigoFisico(codigo);
          final motivo = usado['estado'] == 'Anulado' ? 'fue anulado' : 'ya fue vendido';
          final compra = usado['id_registraCompra'] != null ? ' (compra #${usado['id_registraCompra']})' : '';
          toast('Este código $motivo$compra -- no se puede reutilizar.', color: C.rojo);
          return;
        }
        if (filas.length == 1) {
          final f = filas.first;
          setState(() {
            _seccionPorCodigo[codigo] = str(f['seccion']);
            _filaAsientoPorCodigo[codigo] = str(f['fila_asiento']);
          });
          toast('Boleto encontrado: ${f['seccion']}${str(f['fila_asiento']).isNotEmpty ? ' · ${f['fila_asiento']}' : ''}');
        } else {
          toast('Ese código existe en ${filas.length} secciones -- se agrega igual, sin descontar del inventario.');
        }
      } else {
        toast('No se encontró ese código en el inventario -- se agrega igual.');
      }
    } catch (_) {
      /* Silencioso: el código igual queda agregado. */
    } finally {
      if (mounted) setState(() => _buscandoCodigo = false);
    }
  }

  void _agregarCodigoFisico([String? directo]) {
    _autoEnvio?.cancel();
    final codigo = (directo ?? _codigoFisico.text).trim();
    if (codigo.isEmpty) return;
    _codigoFisico.clear();
    if (_codigosFisicos.contains(codigo)) return;
    if (_codigosFisicos.length >= _cantidadFisicaMax) {
      toast('Ya escaneaste los $_cantidadFisicaMax boleto${_cantidadFisicaMax > 1 ? 's' : ''} de esta venta.');
      return;
    }
    setState(() => _codigosFisicos.add(codigo));
    _buscarBoletoFisico(codigo);
    _focoFisico.requestFocus();
  }

  /* Lectores de código de barras que NO mandan Enter: si no entra ningún
     carácter nuevo en 600ms, se agrega solo. */
  void _alEscribirCodigo() {
    _autoEnvio?.cancel();
    if (_tipoBoleto != 'fisico' || _codigoFisico.text.trim().isEmpty) return;
    _autoEnvio = Timer(const Duration(milliseconds: 600), _agregarCodigoFisico);
  }

  Future<void> _escanearConCamara() async {
    final r = await escanearBoletoFisico(titulo: 'Escanear boleto físico');
    if (r.ok && r.codigo != null) {
      _agregarCodigoFisico(r.codigo);
    } else if (r.mensaje != null) {
      toast(r.mensaje!);
    }
  }

  void _quitarCodigoFisico(String codigo) {
    setState(() {
      _codigosFisicos.remove(codigo);
      _seccionPorCodigo.remove(codigo);
      _filaAsientoPorCodigo.remove(codigo);
    });
  }

  /* Correlativo: los asientos recién se conocen después de crear la compra. */
  Future<List<int>> _obtenerAsientosCorrelativo(int idRegistraCompra) async {
    try {
      final r = await dio.post('$urlBase/listarRegistros',
          data: {}, queryParameters: {'id_registro': idRegistraCompra}, options: hdr(apiHdr()));
      final filas = asMapList(asMap(r.data)['data']);
      if (filas.isEmpty) return [];
      final info = asMapList(filas.first['info_concierto']);
      if (info.isEmpty) return [];
      return asList(info.first['id_sillas']).map(ent).where((n) => n > 0).toList();
    } catch (_) {
      return [];
    }
  }

  /* Vincula cada código con su asiento (1.º con 1.º...) y canjea la compra.
     omitirCanje: si el pago aún no está confirmado, el boleto queda
     reservado pero el canje se deja para cuando se apruebe. */
  Future<void> _asignarBoletosFisicosYCanjear(int idRegistraCompra, {bool omitirCanje = false}) async {
    final asientos = st.idSillas.isNotEmpty ? st.idSillas : await _obtenerAsientosCorrelativo(idRegistraCompra);
    final esCorrelativo = st.idSillas.isEmpty;
    final resumen = <_ResultadoFisico>[];
    for (var i = 0; i < _codigosFisicos.length; i++) {
      final codigo = _codigosFisicos[i];
      final seccion = _seccionPorCodigo[codigo];
      final etiqueta = esCorrelativo
          ? 'Boleto correlativo N.º ${i + 1}'
          : formatearEtiquetaAsiento(i < st.sillasSeleccionadas.length ? st.sillasSeleccionadas[i] : null);
      if (seccion == null || seccion.isEmpty) {
        resumen.add(_ResultadoFisico(codigo, false, 'No se encontró en el inventario de boletos físicos.', etiqueta));
        continue;
      }
      final idAsiento = i < asientos.length ? asientos[i] : null;
      try {
        final r = await dio.post('$urlBase/boletos_fisicos/asignar',
            data: {
              'codigoEvento': st.codigoEvento,
              'seccion': seccion,
              'codigo_barras': codigo,
              'id_registraCompra': idRegistraCompra,
              'id_operador': _idOperador,
              'id_localidades_items': ?idAsiento,
            },
            options: hdr(apiHdr()));
        final data = asMap(r.data);
        final ok = data['success'] == true;
        resumen.add(_ResultadoFisico(
            codigo, ok, strN(data['message']) ?? (ok ? 'Vinculado correctamente.' : 'No se pudo vincular.'), etiqueta));
      } catch (_) {
        resumen.add(_ResultadoFisico(codigo, false, 'Error de conexión al vincular este boleto.', etiqueta));
      }
    }
    _resumenFisico = resumen;
    if (omitirCanje) return;
    try {
      await dio.post('$urlBase/canje_boleto',
          data: {
            'id_registraCompra': idRegistraCompra,
            'canjeado': 'CANJEADO',
            'id_operador': _idOperador,
            'id_usuario': cliente.id,
          },
          options: hdr(apiHdr()));
    } catch (_) {
      /* best-effort */
    }
  }

  Future<void> _confirmarVenta() async {
    if (_faltanCodigosFisicos) {
      setState(() => _error = 'Escanea el código de todos los boletos físicos antes de registrar la venta.');
      return;
    }
    if (_faltanDatosTarjetaFisica) {
      setState(() => _error = 'Ingresa el número de lote y la referencia de la tarjeta (máximo 6 dígitos cada uno).');
      return;
    }
    final d = _desglose;
    final esLocal = _esLocal;
    final esFisico = _esFisico;
    final esQrDuna = _esQrDuna;
    final esTransferencia = _esTransferencia;
    setState(() {
      _cargando = true;
      _error = '';
      _fase = _Fase.procesando;
    });
    final inicio = DateTime.now();
    try {
      final payload = {
        'id_usuario': cliente.id,
        'id_operador': _idOperador,
        'cedula': cliente.cedula,
        'email': cliente.email,
        'forma_pago': _metodo,
        'canal': esQrDuna ? 'Web' : 'App Ventas',
        'concierto': [
          {
            'nombreConcierto': st.nombreEvento,
            'id_localidad': st.idLocalidad,
            'idespaciolocalida': st.idPrecio,
            'CODIGEVENTO': st.codigoEvento,
            'cantidad': st.cantidad,
            /* x2: el backend arma las entradas como paquetes x factor. */
            'cantidad_paquetes': _cantidadCobro,
            'factor_boletos': _factor,
            if (st.modalidadCodigo.isNotEmpty) 'modalidad_codigo': st.modalidadCodigo,
            'localidad_nombre': st.localidadNombre,
            'localidad_precio': st.precio,
            'comision_por_boleto': f2(d.comisionServicio),
            'iva': f2(d.ivaImporte),
            'discapacida': false,
            'menor': false,
            'naipes': false,
            'id_sillas': st.idSillas,
          }
        ],
        'valores': {
          'total': f2(d.total),
          'comision': f2(d.comisionServicio),
          'subtotal': f2(d.subtotal),
          'comision_bancaria': f2(d.comisionBancaria),
          'description': st.localidadNombre,
          'iva': f2(d.ivaImporte),
        },
        if (_descuentoSel != null) 'descuento': {'id': _descuentoSel},
        if (_esTarjetaFisica) 'tarjeta_lote': _tarjetaLote.text,
        if (_esTarjetaFisica) 'tarjeta_referencia': _tarjetaReferencia.text,
        'transaccion': '',
        'codigo_boletos': _codigosFisicos,
        if (esLocal) 'canjear': esFisico,
        if (esLocal) 'enviar_correo': _enviarCorreo,
      };

      final r = await dio.post('$urlBase/registraCompra', data: payload, options: hdr(apiHdr()));
      final data = asMap(r.data);

      /* Pantalla de "Procesando…" con duración mínima de 2 s. */
      final restante = 2000 - DateTime.now().difference(inicio).inMilliseconds;
      if (restante > 0) await Future.delayed(Duration(milliseconds: restante));

      final idRegistro = entN(data['idRegistro']);
      if (data['success'] == true || idRegistro != null) {
        final url = str(data['url']);
        _urlPago = url;
        _idRegistro = idRegistro;
        if (esFisico && idRegistro != null) {
          await _asignarBoletosFisicosYCanjear(idRegistro, omitirCanje: !esLocal);
        }
        if (!mounted) return;
        if (esTransferencia && idRegistro != null) {
          setState(() => _fase = _Fase.comprobante);
        } else {
          setState(() => _fase = _Fase.exito);
          /* En modo QR el "url" es la imagen del código, no una página. */
          if (url.isNotEmpty && !esQrDuna) {
            sinEsperar(sinBloqueo(() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)));
          }
        }
      } else {
        setState(() {
          _fase = _Fase.seleccion;
          _error = strN(data['message']) ?? 'No se pudo registrar la venta. Intenta de nuevo.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.seleccion;
        _error = mensajeBackend(e) ?? 'Error de conexión. Verifica tu internet e intenta de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /* ── Link de pago ── */

  Future<void> _copiarLink() async {
    if (_urlPago.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _urlPago));
    toast('Link de pago copiado.');
  }

  /* Celular a formato internacional de Ecuador (593 + número sin 0 inicial). */
  String _celularWhatsapp(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('593')) d = d.substring(3);
    d = d.replaceFirst(RegExp(r'^0+'), '');
    return d.isNotEmpty ? '593$d' : '';
  }

  String _mensajePago() =>
      'Hola${cliente.nombreCompleto.isNotEmpty ? ' ${cliente.nombreCompleto.split(' ').first}' : ''}, '
      'aquí tienes el link para completar el pago de tu entrada a '
      '${st.nombreEvento.isEmpty ? 'el evento' : st.nombreEvento}: $_urlPago';

  void _enviarPorWhatsapp() {
    final numero = _celularWhatsapp(cliente.movil);
    if (numero.isEmpty) {
      toast('El cliente no tiene celular registrado.');
      return;
    }
    sinEsperar(sinBloqueo(() => launchUrl(
        Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(_mensajePago())}'),
        mode: LaunchMode.externalApplication)));
  }

  Future<void> _compartirLink() async {
    try {
      await sinBloqueo(() => SharePlus.instance.share(ShareParams(text: _mensajePago(), title: 'Link de pago')));
    } catch (_) {
      toast('No se pudo abrir el menú de compartir.');
    }
  }

  /* ── Comprobante (Transferencia/Depósito) ── */

  Future<void> _elegirComprobante() async {
    final origen = await elegirOpcion(context, titulo: 'Foto del comprobante', opciones: ['Tomar foto', 'Elegir de la galería']);
    if (origen == null) return;
    final foto = await sinBloqueo(() => ImagePicker().pickImage(
          source: origen == 0 ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 2000,
        ));
    if (foto == null || !mounted) return;
    setState(() {
      _comprobanteArchivo = File(foto.path);
      _comprobanteUrl = '';
      _ocrResultado = null;
      _ocrError = '';
    });
    _analizarComprobante(foto.path);
  }

  /* Al elegir la foto se sube y se analiza con OCR para autocompletar
     banco/número (los campos siguen siendo editables). */
  Future<void> _analizarComprobante(String ruta) async {
    setState(() {
      _analizandoOcr = true;
      _ocrError = '';
    });
    try {
      final url = await subirImagen(ruta);
      if (url == null) {
        setState(() => _ocrError = 'No se pudo subir la imagen para analizarla. Completa los datos manualmente.');
        return;
      }
      _comprobanteUrl = url;
      final r = await dio.post(urlOcrComprobante,
          data: {'url_imagen': url, 'request_id': '${DateTime.now().millisecondsSinceEpoch}', 'guardar_bd': false},
          options: hdr(jsonHdr));
      final resp = asMap(r.data);
      if (!truthy(resp['success']) && !truthy(resp['estado'])) {
        setState(() => _ocrError = 'No se pudo analizar la imagen automáticamente. Completa los datos manualmente.');
        return;
      }
      final extraido = asMap(resp['data']);
      setState(() {
        _ocrResultado = extraido;
        final numero = str(extraido['numero_comprobante'] ?? extraido['referencia']).trim();
        if (numero.isNotEmpty) _numeroTransaccion.text = numero;
        final banco = str(extraido['banco_receptor'] ?? extraido['banco_emisor']).toUpperCase();
        if (banco.contains('PICHINCHA')) {
          _bancoComprobante = 'Pichincha';
        } else if (banco.contains('GUAYAQUIL')) {
          _bancoComprobante = 'Guayaquil';
        }
      });
    } catch (_) {
      setState(() => _ocrError = 'No se pudo analizar la imagen automáticamente. Completa los datos manualmente.');
    } finally {
      if (mounted) setState(() => _analizandoOcr = false);
    }
  }

  Future<void> _subirComprobante() async {
    if (_bancoComprobante.isEmpty) return setState(() => _errorComprobante = 'Selecciona el banco.');
    if (_numeroTransaccion.text.trim().isEmpty) {
      return setState(() => _errorComprobante = 'Ingresa el número de comprobante o transacción.');
    }
    if (_comprobanteArchivo == null) return setState(() => _errorComprobante = 'Toma o selecciona una foto del comprobante.');
    if (_idRegistro == null) return setState(() => _errorComprobante = 'No se encontró el registro de la venta.');
    setState(() {
      _subiendoComprobante = true;
      _errorComprobante = '';
    });
    try {
      /* Si ya se subió al analizar con OCR, se reutiliza esa URL. */
      var urlImagen = _comprobanteUrl;
      if (urlImagen.isEmpty) {
        final url = await subirImagen(_comprobanteArchivo!.path);
        if (url == null) {
          setState(() => _errorComprobante = 'No se pudo subir la imagen del comprobante. Intenta de nuevo.');
          return;
        }
        urlImagen = url;
      }
      final r = await dio.post('$urlBase/registraPagos',
          data: {
            'id': _idRegistro,
            'id_usuario': cliente.id,
            'id_operador': _idOperador,
            'forma_pago': _metodo,
            'cedula': cliente.cedula,
            'banco': _bancoComprobante,
            'bancos': _bancoComprobante,
            'link_comprobante': urlImagen,
            'numeroTransaccion': _numeroTransaccion.text.trim(),
            'estado': 'Comprobar',
            'total_pago': f2(_desglose.total),
          },
          options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true) {
        setState(() {
          _comprobanteAdjuntado = true;
          _fase = _Fase.exito;
        });
      } else {
        setState(() => _errorComprobante = strN(data['message']) ?? 'No se pudo registrar el comprobante. Intenta de nuevo.');
      }
    } catch (_) {
      setState(() => _errorComprobante = 'Error de conexión al subir el comprobante.');
    } finally {
      if (mounted) setState(() => _subiendoComprobante = false);
    }
  }

  /* ── UI ── */

  Widget _tarjetaResumen({bool conMetodo = false}) => Tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloTarjeta(conMetodo ? 'Resumen de la venta' : 'Resumen de venta'),
          Text(st.nombreEvento.isEmpty ? '—' : st.nombreEvento,
              style: TextStyle(fontWeight: FontWeight.w700, color: colorAcento(context))),
          const SizedBox(height: 6),
          FilaDato('Cliente', cliente.nombreOCedula),
          FilaDato('Localidad', st.localidadNombre.isEmpty ? '—' : st.localidadNombre),
          FilaDato(
              'Cantidad',
              st.idSillas.isNotEmpty
                  ? '${st.idSillas.length} asiento${st.idSillas.length > 1 ? 's' : ''}'
                  : '${st.cantidad} boleto${st.cantidad > 1 ? 's' : ''}'),
          if (conMetodo) FilaDato('Método de pago', _met.label.isEmpty ? '—' : _met.label),
          if (conMetodo) FilaDato('Tipo de boleto', _esFisico ? 'Físico' : 'Digital'),
        ]),
      );

  Widget _tarjetaPrecios() {
    final d = _desglose;
    final desc = _descuentoActivo;
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const TituloTarjeta('Detalle de precios'),
        FilaDato('Subtotal', '\$${f2(d.subtotal)}'),
        if (d.comisionServicio > 0) FilaDato('Servicio Em. por Boleto', '\$${f2(d.comisionServicio)}'),
        if (d.ivaImporte > 0) FilaDato('IVA (${(_ivaRate * 100).round()}%)', '\$${f2(d.ivaImporte)}'),
        if (d.comisionBancaria > 0) FilaDato('Comisión (${(_met.pct * 100).round()}%)', '\$${f2(d.comisionBancaria)}'),
        /* En modo "base" ya está reflejado arriba: no se resta otra vez. */
        if (desc != null)
          FilaDato('Descuento (${desc.nombre} -${desc.porcentajeTexto}%)',
              _aplicaSobreBase ? 'Incluido arriba' : '-\$${f2(_montoDescuento)}'),
        const Divider(),
        FilaDato('TOTAL', '\$${f2(_totalACobrar)}', destacado: true),
      ]),
    );
  }

  Widget _opcionSegmento(String valor, String actual, IconData icono, String texto, ValueChanged<String> onTap) {
    final sel = valor == actual;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(valor),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? colorAcento(context).withValues(alpha: 0.12) : null,
            border: Border.all(color: sel ? colorAcento(context) : C.borde, width: sel ? 2 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Icon(icono, color: sel ? colorAcento(context) : colorTenue(context)),
            const SizedBox(height: 4),
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: sel ? colorAcento(context) : colorTenue(context))),
          ]),
        ),
      ),
    );
  }

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(t, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
      );

  Widget _seccionFisico() {
    final max = _cantidadFisicaMax;
    final lleno = _codigosFisicos.length >= max;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 10),
      Text.rich(TextSpan(style: TextStyle(fontSize: 13, color: colorTenue(context)), children: [
        TextSpan(
            text: '${_codigosFisicos.length} de $max',
            style: TextStyle(fontWeight: FontWeight.w800, color: colorTexto(context))),
        TextSpan(
            text: ' boleto${max > 1 ? 's' : ''} escaneado${max > 1 ? 's' : ''}. '
                'Escanea el código con el lector (o cámara) o tecléalo y presiona Enter.'
                '${_buscandoCodigo ? ' Buscando…' : ''}'),
      ])),
      if (st.sillasSeleccionadas.isNotEmpty)
        _hint('El 1.º código escaneado se asigna a la 1.ª silla elegida en el mapa, el 2.º a la 2.ª, y así '
            'sucesivamente -- revisa abajo que cada código quede junto a la silla correcta antes de confirmar.'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _codigoFisico,
            focusNode: _focoFisico,
            enabled: !lleno,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _agregarCodigoFisico(),
            decoration: const InputDecoration(hintText: 'Código de barras del boleto físico'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(onPressed: lleno ? null : _escanearConCamara, icon: const Icon(Icons.photo_camera_outlined)),
      ]),
      if (_codigosFisicos.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final (i, c) in _codigosFisicos.indexed)
          Builder(builder: (_) {
            final asiento =
                formatearEtiquetaAsiento(i < st.sillasSeleccionadas.length ? st.sillasSeleccionadas[i] : null);
            final info = [_seccionPorCodigo[c], _filaAsientoPorCodigo[c]].where((s) => s != null && s.isNotEmpty).join(' · ');
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  if (asiento != null) '→ $asiento',
                  if (info.isNotEmpty) 'Impreso: $info',
                ].join('\n')),
                trailing: IconButton(icon: const Icon(Icons.cancel_outlined), onPressed: () => _quitarCodigoFisico(c)),
              ),
            );
          }),
      ],
      _hint(_esLocal
          ? 'Se canjeará automáticamente al confirmar la venta.'
          : 'El pago aún no está confirmado -- se canjeará recién cuando se confirme.'),
      if (st.idSillas.isEmpty)
        _hint('Localidad sin asientos numerados: los boletos se van asignando en el orden en que se compran.'),
    ]);
  }

  Widget _faseSeleccion() {
    final metodos = _metodosDisponibles;
    return Contenido(children: [
      _tarjetaResumen(),
      Tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TituloTarjeta('Método de pago'),
          if (metodos == null)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else
            RadioGroup<String>(
              groupValue: _metodo,
              onChanged: (v) => setState(() => _metodo = v ?? _metodo),
              child: Column(children: [
                for (final m in metodos)
                  RadioListTile<String>(
                    value: m.key,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(m.desc),
                  ),
              ]),
            ),
          const Divider(height: 24),
          /* Tipo de boleto: disponible para CUALQUIER método de pago. */
          Text('Tipo de boleto', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
          const SizedBox(height: 8),
          Row(children: [
            _opcionSegmento('digital', _tipoBoleto, Icons.qr_code, 'Digital', (v) => setState(() => _tipoBoleto = v)),
            const SizedBox(width: 10),
            _opcionSegmento('fisico', _tipoBoleto, Icons.qr_code_scanner, 'Físico', (v) {
              setState(() => _tipoBoleto = v);
              _focoFisico.requestFocus();
            }),
          ]),
          if (_esFisico) _seccionFisico(),
          if (_esLocal)
            CheckboxListTile(
              value: _enviarCorreo,
              onChanged: (v) => setState(() => _enviarCorreo = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Enviar entradas al correo'),
            ),
          if (_esDuna) ...[
            const Divider(height: 24),
            Text('¿Cómo quieres cobrar con Duna?', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
            const SizedBox(height: 8),
            Row(children: [
              _opcionSegmento('qr', _dunaModo, Icons.qr_code, 'Código QR', (v) => setState(() => _dunaModo = v)),
              const SizedBox(width: 10),
              _opcionSegmento('link', _dunaModo, Icons.link, 'Link para enviar', (v) => setState(() => _dunaModo = v)),
            ]),
            _hint(_dunaModo == 'qr'
                ? 'El cliente escanea el código con la app de Deuna o de su banco.'
                : 'Comparte el link para que el cliente pague desde su teléfono.'),
          ],
          if (_esTarjetaFisica) ...[
            const Divider(height: 24),
            Text('Datos del voucher (POS)', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _tarjetaLote,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Número de lote', hintText: 'Ej: 001234'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _tarjetaReferencia,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Referencia', hintText: 'Ej: 998877'),
                ),
              ),
            ]),
            _hint('Ambos son obligatorios -- van impresos en el voucher de la POS (máximo 6 dígitos).'),
          ],
        ]),
      ),
      if (_descuentos.isNotEmpty)
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloTarjeta('Descuento'),
            RadioGroup<int?>(
              groupValue: _descuentoSel,
              onChanged: (v) => setState(() => _descuentoSel = v),
              child: Column(children: [
                const RadioListTile<int?>(value: null, dense: true, contentPadding: EdgeInsets.zero, title: Text('Sin descuento')),
                for (final d in _descuentos)
                  RadioListTile<int?>(
                    value: d.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text.rich(TextSpan(children: [
                      TextSpan(text: '${d.nombre} '),
                      TextSpan(text: '-${d.porcentajeTexto}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ])),
                  ),
              ]),
            ),
          ]),
        ),
      _tarjetaPrecios(),
      if (_faltanCodigosFisicos)
        TextoError('Faltan escanear ${_cantidadFisicaMax - _codigosFisicos.length} código'
            '${_cantidadFisicaMax - _codigosFisicos.length > 1 ? 's' : ''} de boleto físico para poder continuar.'),
      if (_faltanDatosTarjetaFisica)
        const TextoError(
            'Ingresa el número de lote y la referencia de la tarjeta (máximo 6 dígitos cada uno) para poder continuar.'),
      if (_error.isNotEmpty) TextoError(_error),
      BotonAccion(
        'Registrar venta  \$${f2(_totalACobrar)}',
        primario: true,
        cargando: _cargando,
        onPressed: (_metodo.isEmpty || _faltanCodigosFisicos || _faltanDatosTarjetaFisica) ? null : _mostrarConfirmacion,
      ),
      const SizedBox(height: 20),
    ]);
  }

  /* Resumen antes de disparar el cobro real -- el POST solo se hace desde aquí. */
  Future<void> _mostrarConfirmacion() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('Confirmar venta', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: colorTexto(ctx))),
          const SizedBox(height: 12),
          _tarjetaResumen(conMetodo: true),
          const SizedBox(height: 12),
          _tarjetaPrecios(),
          const SizedBox(height: 12),
          Text('Revisa los datos antes de continuar. Una vez registrada, la venta no se puede deshacer desde aquí.',
              style: TextStyle(color: colorTenue(ctx))),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar venta')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('REGRESAR A LA VENTA')),
        ]),
      ),
    );
    if (ok == true) _confirmarVenta();
  }

  Widget _cuentasBancarias() => Column(children: [
        for (final c in _cuentas)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: esOscuro(context) ? const Color(0xFF1A2035) : const Color(0xFFF4F6FB),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c.banco} · ${c.tipo}', style: TextStyle(fontWeight: FontWeight.w800, color: colorTexto(context))),
              SelectableText('Cuenta: ${c.cuenta}'),
              Text('RUC: ${c.ruc}', style: TextStyle(color: colorTenue(context))),
            ]),
          ),
      ]);

  Widget _panelOcr() {
    final o = _ocrResultado!;
    final numero = str(o['numero_comprobante'] ?? o['referencia']);
    final banco = str(o['banco_receptor'] ?? o['banco_emisor']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, size: 18, color: C.azul),
          SizedBox(width: 6),
          Text('Datos detectados automáticamente', style: TextStyle(fontWeight: FontWeight.w700, color: C.azul)),
        ]),
        const SizedBox(height: 6),
        if (numero.isNotEmpty) _datoOcr('N° comprobante', numero),
        if (o['monto'] is num) _datoOcr('Monto', '\$${f2(o['monto'] as num)}'),
        if (banco.isNotEmpty) _datoOcr('Banco', banco),
        if (str(o['fecha']).isNotEmpty) _datoOcr('Fecha', str(o['fecha'])),
        if (_ocrSospechoso)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('⚠ Esta imagen podría no ser válida — revísala antes de confirmar.',
                style: TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600)),
          ),
        for (final a in _ocrAvisos)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('⚠ $a', style: const TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 6),
        const Text('Verifica y corrige los campos si es necesario antes de adjuntar.',
            style: TextStyle(fontSize: 12, color: C.gris)),
      ]),
    );
  }

  Widget _datoOcr(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: const TextStyle(color: C.gris, fontSize: 13))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.azulOscuro)),
        ]),
      );

  Widget _faseComprobante() => Contenido(children: [
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloTarjeta('Comprobante del depósito', icono: Icons.receipt_long_outlined),
            Text(
              'La orden quedó registrada como pendiente. Adjunta el comprobante para que quede lista para aprobación, '
              'o continúa sin él y súbelo después desde el detalle de la compra.',
              style: TextStyle(color: colorTenue(context)),
            ),
            const SizedBox(height: 12),
            _cuentasBancarias(),
            const SizedBox(height: 4),
            Text('Banco del depósito/transferencia', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, c) in _cuentas.indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                _opcionSegmento(c.valor, _bancoComprobante, Icons.account_balance, c.banco.replaceFirst('Banco ', ''),
                    (v) => setState(() => _bancoComprobante = v)),
              ],
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _numeroTransaccion,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Número de comprobante / transacción', hintText: 'Ej. 000123456'),
            ),
            const SizedBox(height: 14),
            Text('Foto del comprobante', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
            _hint('Sube el comprobante que genera la opción "Compartir" del banco o de Deuna, no una captura de pantalla '
                '— ese trae toda la información necesaria (banco, monto, número de comprobante) y es más fácil de leer automáticamente.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirComprobante,
              icon: Icon(_comprobanteArchivo != null ? Icons.cloud_upload_outlined : Icons.photo_camera_outlined),
              label: Text(_comprobanteArchivo != null ? 'Cambiar foto' : 'Tomar o elegir foto'),
            ),
            if (_comprobanteArchivo != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(_comprobanteArchivo!, height: 220, fit: BoxFit.contain),
              ),
            ],
            if (_analizandoOcr)
              const Padding(
                padding: EdgeInsets.all(10),
                child: Row(children: [MiniSpinner(color: C.azul), SizedBox(width: 10), Text('Analizando comprobante…')]),
              ),
            if (!_analizandoOcr && _ocrError.isNotEmpty) TextoError('⚠ $_ocrError'),
            if (!_analizandoOcr && _ocrResultado != null) ...[const SizedBox(height: 8), _panelOcr()],
            if (_errorComprobante.isNotEmpty) TextoError(_errorComprobante),
            const SizedBox(height: 12),
            BotonAccion(_subiendoComprobante ? 'Subiendo…' : 'Adjuntar comprobante',
                primario: true, cargando: _subiendoComprobante, onPressed: _subirComprobante),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _subiendoComprobante ? null : () => setState(() => _fase = _Fase.exito),
              child: const Text('Continuar sin comprobante ahora'),
            ),
          ]),
        ),
      ]);

  Widget _faseExito() {
    final sospechoso = _comprobanteSospechoso;
    final p = <String>[];
    if (!_quedaPagadoAlInstante && !sospechoso) {
      p.add('Los boletos se generarán y los asientos se asignarán automáticamente en cuanto se confirme el pago '
          '(puede tardar unos minutos). Al cliente también le llegarán las entradas digitales a su correo.');
    }
    if (_esLocal && !_esFisico) p.add('La entrada quedó pagada. ${_enviarCorreo ? 'Se envió al correo del cliente.' : ''}');
    if (_esFisico && _esLocal) {
      p.add('Entrada(s) física(s) registrada(s) y canjeada(s). ${_enviarCorreo ? 'También se envió al correo del cliente.' : ''}');
    }
    if (_esFisico && !_esLocal && !_esTransferencia) {
      p.add('Boleto(s) físico(s) registrado(s) y reservado(s). Se canjeará(n) al confirmarse el pago.');
    }
    if (_met.categoria == CategoriaMetodo.gateway && !_esQrDuna) {
      p.add('Comparte el link de pago con el cliente para que complete el pago con tarjeta.');
    }
    if (_esQrDuna) p.add('Pide al cliente que escanee este código QR con la app de Deuna o de su banco para completar el pago.');
    if (_esTransferencia && _esFisico) {
      p.add('Boleto(s) físico(s) reservado(s) -- se canjeará(n) recién cuando se apruebe el depósito.');
    }
    if (_esTransferencia && _comprobanteAdjuntado && !sospechoso) {
      p.add('El comprobante quedó adjunto y la venta pendiente de aprobación manual.');
    }
    if (_esTransferencia && !_comprobanteAdjuntado) {
      p.add('La venta quedó pendiente de aprobación hasta confirmar el depósito. Comparte estos datos con el cliente y '
          'adjunta el comprobante después desde el detalle de la compra:');
    }

    return Contenido(children: [
      const SizedBox(height: 10),
      Icon(sospechoso ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          size: 80, color: sospechoso ? C.naranja : C.verde),
      Text(sospechoso ? 'Comprobante en revisión' : '¡Venta registrada!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colorTexto(context))),
      for (final t in p) Text(t, textAlign: TextAlign.center, style: TextStyle(color: colorTenue(context), height: 1.4)),
      if (_esFisico && _resumenFisico.isNotEmpty)
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TituloTarjeta('Vinculación de boletos físicos',
                icono: _resumenFisico.every((r) => r.ok) ? Icons.check_circle_outline : Icons.warning_amber_rounded),
            for (final r in _resumenFisico)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: r.ok ? const Color(0xFFD4F1DD) : C.rojoFondo,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r.codigo}${r.etiqueta != null ? ' · ${r.etiqueta}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: C.azulOscuro)),
                  Text(r.ok ? 'Vinculado' : r.mensaje, style: TextStyle(color: r.ok ? const Color(0xFF155724) : C.rojoOscuro)),
                ]),
              ),
            if (_resumenFisico.any((r) => !r.ok))
              const Text('Corrige los boletos marcados desde "Ver compra" antes de entregarlos al cliente.',
                  style: TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600)),
          ]),
        ),
      if (_esTransferencia && _comprobanteAdjuntado && sospechoso)
        const Aviso(
          'No pudimos validar el comprobante automáticamente (dato faltante, monto/banco que no coincide, o imagen poco '
          'clara). La compra va a quedar en proceso hasta que el departamento de contabilidad revise y apruebe el '
          'depósito o la transferencia.',
          icono: Icons.warning_amber_rounded,
        ),
      if (_esTransferencia && !_comprobanteAdjuntado) _cuentasBancarias(),
      if (_esQrDuna && _urlPago.isNotEmpty)
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Image.network(_urlPago, width: 260, height: 260, fit: BoxFit.contain),
          ),
        ),
      if (_urlPago.isNotEmpty && !_esQrDuna) ...[
        FilledButton.icon(
          onPressed: () => sinEsperar(
              sinBloqueo(() => launchUrl(Uri.parse(_urlPago), mode: LaunchMode.externalApplication))),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Abrir link de pago'),
        ),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _enviarPorWhatsapp, icon: const Icon(Icons.chat_outlined), label: const Text('WhatsApp al cliente')),
          OutlinedButton.icon(onPressed: _compartirLink, icon: const Icon(Icons.share_outlined), label: const Text('Compartir')),
          OutlinedButton.icon(onPressed: _copiarLink, icon: const Icon(Icons.copy), label: const Text('Copiar link')),
        ]),
      ],
      if (_idRegistro != null)
        FilledButton.icon(
          onPressed: () => ir(DetalleCompraPage(id: _idRegistro!)),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Ver compra'),
        ),
      OutlinedButton(onPressed: () => irComoRaiz(const DashboardPage()), child: const Text('Vender otra entrada')),
      const SizedBox(height: 20),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final titulo = switch (_fase) {
      _Fase.exito => _comprobanteSospechoso ? 'Comprobante en revisión' : 'Venta registrada',
      _Fase.comprobante => 'Comprobante de depósito',
      _Fase.procesando => 'Procesando…',
      _Fase.seleccion => 'Confirmar venta',
    };
    return PopScope(
      /* Con la venta ya registrada no se puede "volver" a Localidad (dejaría
         agregar asientos a una orden cerrada). */
      canPop: _fase == _Fase.seleccion,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_anulando) _manejarAtras();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(titulo), automaticallyImplyLeading: _fase == _Fase.seleccion),
        body: switch (_fase) {
          _Fase.procesando => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text('Procesando tu venta…',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colorTexto(context))),
                const SizedBox(height: 6),
                Text('Esto toma solo un momento.', style: TextStyle(color: colorTenue(context))),
              ]),
            ),
          _Fase.exito => _faseExito(),
          _Fase.comprobante => _faseComprobante(),
          _Fase.seleccion => _faseSeleccion(),
        },
      ),
    );
  }
}
