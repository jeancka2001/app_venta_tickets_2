import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../services/escaner.dart';
import '../services/info_boleto.dart';
import '../services/metodos_pago.dart';
import '../widgets/comunes.dart';
import 'canjear_entradas_page.dart';
import 'detalle_compra_page.dart';

({String texto, Color fondo, Color color}) _badgeEstado(String? estadoRaw) {
  final e = (estadoRaw ?? '').toUpperCase();
  if (e == 'VENDIDO') return (texto: 'Vendido', fondo: C.rojoFondo, color: C.rojoOscuro);
  if (e == 'OCUPADO' || e == 'PASADO') return (texto: 'Ocupado', fondo: C.rojoFondo, color: C.rojoOscuro);
  if (e == 'RESERVADO') return (texto: 'Reservado', fondo: const Color(0xFFE3E5F8), color: C.azul);
  if (e == 'ANULADO') return (texto: 'Anulado', fondo: const Color(0xFFEDEFF3), color: C.gris);
  return (texto: 'Libre', fondo: const Color(0xFFD4F1DD), color: const Color(0xFF155724));
}

String _descripcionAsiento(Map<String, dynamic> d) {
  final t = str(d['typo']).toLowerCase();
  String? s(String k) => str(d[k]).isEmpty ? null : str(d[k]);
  if (t == 'correlativo') {
    return d['boleto_numero'] != null
        ? 'Boleto N.º ${d['boleto_numero']}${d['boleto_total'] != null ? ' de ${d['boleto_total']}' : ''}'
        : 'Boleto correlativo';
  }
  if (t == 'mesa') {
    final p = [
      if (s('mesa') != null) 'Mesa ${s('mesa')}',
      if (s('fila') != null) 'Fila ${s('fila')}',
      if (s('silla') != null) 'Silla ${s('silla')}',
      if (s('sillas') != null) '(${s('sillas')} sillas)',
    ];
    return p.isNotEmpty ? p.join(' · ') : 'Mesa';
  }
  if (t == 'fila') {
    final p = [
      if (s('fila') != null) 'Fila ${s('fila')}',
      if (s('silla') != null) 'Silla ${s('silla')}',
      if (s('sillas') != null) '(${s('sillas')} sillas)',
    ];
    return p.isNotEmpty ? p.join(' · ') : 'Fila';
  }
  return s('silla') ?? s('fila') ?? s('mesa') ?? 'Asiento #${d['id_item']}';
}

/* Asiento ocupado SIN orden de compra = lo asignó un admin (no es venta). */
bool _esAsignacionManual(Map<String, dynamic> d) =>
    d['id_registraCompra'] == null && str(d['estado']).toUpperCase() == 'OCUPADO';

class EscanearBoletoPage extends StatefulWidget {
  const EscanearBoletoPage({super.key});

  @override
  State<EscanearBoletoPage> createState() => _EscanearBoletoPageState();
}

class _EscanearBoletoPageState extends State<EscanearBoletoPage> {
  final _codigo = TextEditingController();
  final _foco = FocusNode();
  Timer? _autoEnvio;
  bool _buscando = false;
  String _error = '';
  ResultadoInfoBoleto? _resultado;

  @override
  void initState() {
    super.initState();
    _codigo.addListener(() {
      _autoEnvio?.cancel();
      /* Lectores que NO mandan Enter: auto-envío tras 600ms sin teclear. */
      if (_codigo.text.trim().isEmpty || _buscando) return;
      _autoEnvio = Timer(const Duration(milliseconds: 600), _buscarCodigo);
    });
  }

  @override
  void dispose() {
    _autoEnvio?.cancel();
    _codigo.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _buscarCodigo([String? directo]) async {
    _autoEnvio?.cancel();
    final codigo = (directo ?? _codigo.text).trim();
    if (codigo.isEmpty) return;
    _codigo.clear();
    setState(() {
      _error = '';
      _resultado = null;
      _buscando = true;
    });
    final info = await obtenerInfoBoleto(codigo);
    if (!mounted) return;
    setState(() {
      _resultado = info;
      _buscando = false;
    });
    _foco.requestFocus();
  }

  Future<void> _escanearConCamara() async {
    setState(() => _error = '');
    final r = await escanearBoletoFisico(titulo: 'Escanear boleto');
    if (!r.ok || r.codigo == null) {
      if (r.mensaje != null) setState(() => _error = r.mensaje!);
      return;
    }
    await _buscarCodigo(r.codigo);
  }

  Future<void> _copiar(String cedula) async {
    await Clipboard.setData(ClipboardData(text: cedula));
    toast('Cédula copiada.');
  }

  Widget _fila(String etiqueta, Widget valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(etiqueta, style: TextStyle(color: colorTenue(context), fontSize: 13))),
          Expanded(child: valor),
        ]),
      );

  Widget _texto(String t, {bool bold = false}) => Text(t,
      style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: colorTexto(context), fontSize: 13.5));

  Widget? _comprador(String? nombre, String? cedula, String? email, String? movil, String? ciudad, String? direccion,
      {String titulo = 'Comprador', String etiquetaCedula = 'Cédula'}) {
    bool v(String? s) => s != null && s.isNotEmpty;
    if (!v(nombre) && !v(cedula)) return null;
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TituloTarjeta(titulo, icono: Icons.person_outline),
        if (v(nombre)) _fila('Nombre', _texto(nombre!)),
        if (v(cedula))
          _fila(
            etiquetaCedula,
            Row(children: [
              Flexible(child: _texto(cedula!)),
              IconButton(
                  visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy, size: 18), onPressed: () => _copiar(cedula)),
            ]),
          ),
        if (v(email)) _fila('Correo', _texto(email!)),
        if (v(movil)) _fila('Celular', _texto(movil!)),
        if (v(ciudad) || v(direccion))
          _fila('Ubicación', _texto([ciudad, direccion].where(v).join(' · '))),
      ]),
    );
  }

  Widget? _pago(String? forma, String? estado, String? total, String? fecha) {
    if ((forma ?? '').isEmpty && (estado ?? '').isEmpty && total == null) return null;
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const TituloTarjeta('Compra', icono: Icons.credit_card),
        if ((forma ?? '').isNotEmpty) _fila('Método de pago', _texto(etiquetaFormaPago(forma))),
        if ((estado ?? '').isNotEmpty) _fila('Estado de pago', _texto(estado!)),
        if (total != null) _fila('Total', _texto('\$${f2(dbl(total))}', bold: true)),
        if ((fecha ?? '').isNotEmpty) _fila('Fecha de compra', _texto(formatFecha(fecha))),
      ]),
    );
  }

  Widget? _origen(Map<String, dynamic> d) {
    if (d['id_registraCompra'] != null) {
      return Tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TituloTarjeta('Origen', icono: Icons.receipt_long_outlined),
          _fila(
            'Compra',
            Row(children: [
              _texto('#${d['id_registraCompra']}'),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () => ir(DetalleCompraPage(id: ent(d['id_registraCompra']))),
              ),
            ]),
          ),
        ]),
      );
    }
    if (!_esAsignacionManual(d)) return null;
    final codigo = str(d['id_registra_compra']);
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const TituloTarjeta('Origen', icono: Icons.link),
        _fila('Tipo', _texto('${codigo.isNotEmpty ? 'Boleto físico sincronizado' : 'Asiento asignado'} (sin compra)')),
        if (codigo.isNotEmpty) _fila('Código', _texto(codigo)),
        if (str(d['fecha_ocupado']).isNotEmpty) _fila('Asignado el', _texto(formatFecha(str(d['fecha_ocupado'])))),
      ]),
    );
  }

  List<Widget> _resultadoWidgets() {
    final r = _resultado;
    if (r == null) return [];
    if (!r.ok) {
      return [
        Tarjeta(
          child: Column(children: [
            Icon(Icons.qr_code_2, size: 46, color: colorTenue(context)),
            const SizedBox(height: 8),
            Text(r.mensaje, textAlign: TextAlign.center, style: TextStyle(color: colorTexto(context))),
          ]),
        ),
      ];
    }
    final d = r.data;
    String? s(String k) => strN(d[k]);
    if (r.tipo == 'asiento') {
      final b = _badgeEstado(s('estado'));
      return [
        Tarjeta(
          child: Column(children: [
            Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
              Insignia(b.texto, fondo: b.fondo, color: b.color),
              if (s('pasado') == 'PASADO') const Insignia('✓ Ya ingresó', fondo: Color(0xFFD4F1DD), color: Color(0xFF155724)),
            ]),
            const SizedBox(height: 10),
            Text(_descripcionAsiento(d),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colorTexto(context))),
            const SizedBox(height: 4),
            Text(
              [s('nombreConcierto'), limpiarLocalidad(s('localidad_nombre'))].where((x) => x != null && x.isNotEmpty).join(' · ')
                  .ifEmpty('Boleto digital'),
              textAlign: TextAlign.center,
              style: TextStyle(color: colorTenue(context)),
            ),
          ]),
        ),
        ?_origen(d),
        if (_esAsignacionManual(d))
          ?_comprador(null, s('cedula'), null, null, null, null, titulo: 'Asignado a', etiquetaCedula: 'Cédula / nota')
        else
          ?_comprador(s('nombreCompleto'), (s('cedula') ?? '').isNotEmpty ? s('cedula') : s('cedula_compra'), s('email'),
              s('movil'), s('ciudad'), s('direccion')),
        ?_pago(s('forma_pago'), s('estado_pago'), s('total'), s('fecha_compra')),
      ];
    }
    final b = _badgeEstado(s('estado'));
    return [
      Tarjeta(
        child: Column(children: [
          Insignia(b.texto, fondo: b.fondo, color: b.color),
          const SizedBox(height: 10),
          Text([s('seccion'), s('fila_asiento')].where((x) => x != null && x.isNotEmpty).join(' · ').ifEmpty('Boleto físico'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colorTexto(context))),
          const SizedBox(height: 4),
          Text('Boleto físico · Código ${s('codigo_barras') ?? ''}', style: TextStyle(color: colorTenue(context))),
        ]),
      ),
      ?_comprador(s('nombreCompleto'), s('cedula_compra'), s('email'), s('movil'), s('ciudad'), s('direccion')),
      ?_pago(s('forma_pago'), s('estado_pago'), s('total'), s('fecha_compra')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const TituloConLogo('Escanear boleto')),
      body: Contenido(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codigo,
              focusNode: _foco,
              autofocus: true,
              enabled: !_buscando,
              autocorrect: false,
              onSubmitted: (_) => _buscarCodigo(),
              decoration: const InputDecoration(hintText: 'Código del boleto (QR o barras)'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton(onPressed: _buscando ? null : _escanearConCamara, child: const Icon(Icons.qr_code_scanner)),
          ),
        ]),
        Text('Escanea con la cámara o el lector, o teclea el código y presiona Enter.',
            style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
        OutlinedButton.icon(
          onPressed: () => ir(const CanjearEntradasPage()),
          icon: const Icon(Icons.done_all),
          label: const Text('Canjear una o varias entradas'),
        ),
        if (_error.isNotEmpty) TextoError(_error),
        if (_resultado == null && !_buscando)
          const MensajeVacio(
            'Escanea el código QR o de barras del boleto (digital o físico) para ver el asiento, si está ocupado o '
            'libre, y los datos del comprador.',
            icono: Icons.qr_code_2,
          ),
        if (_buscando) const Cargando(texto: 'Buscando boleto…'),
        if (!_buscando && _resultado != null) ...[
          ..._resultadoWidgets(),
          FilledButton.icon(
            onPressed: _escanearConCamara,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear otro boleto'),
          ),
        ],
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
