import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import '../services/localidad_config.dart';
import '../services/mapa_asientos.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/imagen_zoom.dart';
import '../widgets/mapa_asientos.dart';
import 'pago_page.dart';

/* Mapa de asientos + temporizador de 3 min + refresco en vivo. Quien
   "sostiene" la reserva es el CLIENTE que se buscó/creó en VentaEvento; el
   vendedor logueado se manda como id_operador. */

const _maxSel = 10;
const _tiempoSeleccionSeg = 180;
const _pollCada = Duration(seconds: 15);

String _formatMMSS(int seg) {
  final s = math.max(0, seg);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class LocalidadPage extends StatefulWidget {
  final EventoVenta evento;
  final PrecioLocalidad precio;
  final Cliente cliente;
  const LocalidadPage({super.key, required this.evento, required this.precio, required this.cliente});

  @override
  State<LocalidadPage> createState() => _LocalidadPageState();
}

class _LocalidadPageState extends State<LocalidadPage> {
  late final String _id = '${widget.precio.idLocalidad}';
  late final String _tipo = widget.precio.tipoLocalidad.toLowerCase();
  late final String _nombre = limpiarLocalidad(widget.precio.localidad);
  late final double _precio = dbl(widget.precio.precioNormal);
  late final int _factor = widget.precio.factorBoletos.clamp(1, 10);
  Cliente get _cliente => widget.cliente;

  List<ItemAsiento> _items = [];
  ResumenLocalidad _resumen = const ResumenLocalidad(0, 0, 0);
  bool _hayDatos = false;
  bool _cargando = true;
  List<ItemAsiento> _sel = [];
  int _cantidad = 1;
  /* Correlativo: hay un +/− esperando respuesta del servidor. */
  bool _actualizandoCant = false;
  final Set<int> _procesando = {};
  Map<String, String> _alineacion = {};
  Map<String, bool> _ordenSillas = {};
  int? _idEspacio;
  String? _imagenBloques;
  int _segundos = _tiempoSeleccionSeg;

  bool _corrActivo = false;
  bool _pagando = false;
  bool _salioPorTiempo = false;
  bool _cerrada = false;
  Timer? _timer;
  Timer? _poll;

  bool get _esCorrelativo => _tipo == 'correlativo';
  bool get _esMapa => _tipo == 'fila' || _tipo == 'mesa';
  int get _idOperador => obtenerStaffData()?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _cargarImagenBloques();
    if (!_esCorrelativo) {
      obtenerConfiguracionLocalidad(_id).then((cfg) {
        if (_cerrada) return;
        setState(() {
          _alineacion = cfg.alineacion;
          _ordenSillas = cfg.ordenSillas;
          _idEspacio = cfg.idEspacio;
        });
        if (cfg.idEspacio != null) {
          _cargarLocalidad(reconcile: true);
        } else {
          setState(() => _cargando = false);
        }
      });
    }
    _entrar();
  }

  @override
  void dispose() {
    _cerrada = true;
    _detenerTemporizadores();
    if (!_pagando) _liberarReservas();
    super.dispose();
  }

  Future<void> _cargarImagenBloques() async {
    try {
      final r = await dio.get('$urlBase/imagenBloques/${widget.evento.codigoEvento}', options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true && data['imagen_bloques'] != null && !_cerrada) {
        setState(() => _imagenBloques = str(data['imagen_bloques']));
      }
    } catch (_) {}
  }

  /* Arranque limpio en cada entrada a esta pantalla (también al volver de
   Pago sin terminar la venta). */
  void _entrar() {
    _pagando = false;
    _procesando.clear();
    if (_esCorrelativo) {
      /* Este tipo no distingue "reservado por mí" de "vendido", así que se
         limpia cualquier reserva vieja y se arranca siempre desde 0. */
      sinEsperar(dio.post('$urlBase/selecionar_localidad_correlativa',
              data: {
                'id': _id,
                'cedula': _cliente.cedula,
                'estado': 'reservado',
                'cantidad': 0,
                'mas': 'eliminar',
                'id_usuario': _cliente.id,
                'id_operador': _idOperador,
              },
              options: hdr(apiHdr())));
      _cantidad = 1;
      _corrActivo = false;
    }
    _cargarLocalidad(reconcile: true);
    _iniciarTemporizadores();
  }

  Future<void> _cargarLocalidad({bool reconcile = false, bool silencioso = false}) async {
    if (!_esCorrelativo && _idEspacio == null) return;
    if (silencioso && _cargando) return;
    if (!silencioso) setState(() => _cargando = true);
    try {
      if (_esCorrelativo) {
        final r = await dio.get('$urlMikroti/Boleteria/localidades/$_id/todo',
            options: hdr({'Authorization': msLoginAuthHeaders['authorization-ticket']!}));
        final data = asMap(r.data);
        if (!truthy(data['estado'])) return;
        final d = asMap(data['data']);
        final res = asMap(d['resumen']);
        if (_cerrada) return;
        setState(() {
          _resumen = ResumenLocalidad(ent(res['total']), ent(res['disponibles']), ent(res['ocupadas']));
          _hayDatos = true;
        });
      } else {
        final r = await obtenerMapaLocalidad(_idEspacio!, _id);
        if (_cerrada) return;
        setState(() {
          _items = r.items;
          _resumen = r.resumen;
          _hayDatos = true;
          /* Se reconstruye la selección SIEMPRE desde el servidor: los asientos
             que sigan 'reservado' bajo la cédula de este cliente. Así un
             asiento ya vendido en una compra anterior no reaparece marcado. */
          if (reconcile) {
            _sel = r.items.where((fi) => fi.estado == 'reservado' && fi.cedula == _cliente.cedula).toList();
          }
        });
      }
    } catch (_) {
      /* silencioso */
    } finally {
      if (!silencioso && !_cerrada) setState(() => _cargando = false);
    }
  }

  void _detenerTemporizadores() {
    _timer?.cancel();
    _poll?.cancel();
    _timer = null;
    _poll = null;
  }

  void _iniciarTemporizadores() {
    _detenerTemporizadores();
    _salioPorTiempo = false;
    _segundos = _tiempoSeleccionSeg;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cerrada) return;
      setState(() => _segundos = math.max(0, _segundos - 1));
      if (_segundos <= 0 && !_salioPorTiempo) {
        _salioPorTiempo = true;
        _detenerTemporizadores();
        toast('Se acabó el tiempo para completar la selección. Vuelve a intentarlo.', color: C.rojo);
        if (mounted) Navigator.of(context).pop();
      }
    });
    _poll = Timer.periodic(_pollCada, (_) => _cargarLocalidad(reconcile: true, silencioso: true));
  }

  Map<String, dynamic> _mesaPayload(ItemAsiento item) {
    /* Mismo cuerpo que la app Ionic ({id_silla, id, cedula, ...item, estado:''}). */
    final m = <String, dynamic>{'id_silla': item.idsilla, 'id': _id, 'cedula': _cliente.cedula};
    m['fila'] = item.fila;
    if (item.mesa != null) m['mesa'] = item.mesa;
    m['silla'] = item.silla;
    m['idsilla'] = item.idsilla;
    if (item.cedula != null) {
      m['cedula'] = item.cedula;
    } else {
      m.remove('cedula');
    }
    m['id_registra_compra'] = item.idRegistraCompra;
    m['estado'] = '';
    return m;
  }

  /* Al salir sin pagar se sueltan los asientos / la cantidad apartada. */
  void _liberarReservas() {
    for (final item in _sel) {
      sinEsperar(dio.post('$urlBase/selecionar_localidad_correlativa',
              data: {
                'cedula': _cliente.cedula,
                'estado': 'disponible',
                'id': _id,
                'cantidad': 1,
                'mas': 'mas',
                'mesa': [_mesaPayload(item)],
              },
              options: hdr(apiHdr())));
    }
    if (_corrActivo) {
      sinEsperar(dio.post('$urlBase/selecionar_localidad_correlativa',
              data: {
                'id': _id,
                'cedula': _cliente.cedula,
                'estado': 'reservado',
                'cantidad': 0,
                'mas': 'eliminar',
                'id_usuario': _cliente.id,
                'id_operador': _idOperador,
              },
              options: hdr(apiHdr())));
      _corrActivo = false;
    }
  }

  bool _estaSel(ItemAsiento item) => _sel.any((s) => s.idsilla == item.idsilla);

  Future<void> _toggleSilla(ItemAsiento item) async {
    final r = await dio.post('$urlBase/selecionar_localidad_correlativa',
        data: {
          'cedula': _cliente.cedula,
          'estado': 'disponible',
          'id': _id,
          'cantidad': 1,
          'mas': 'mas',
          'mesa': [_mesaPayload(item)],
        },
        options: hdr(apiHdr()));
    final data = asMap(r.data);
    if (data['success'] != true) throw Exception(str(data['message'], 'Error al reservar'));
    final reservado = asList(data['insert']).map(ent).contains(item.idsilla);
    final liberado = asList(data['update']).map(ent).contains(item.idsilla);
    if (_cerrada) return;
    setState(() {
      if (reservado) _sel = [..._sel, item];
      if (liberado) _sel = _sel.where((s) => s.idsilla != item.idsilla).toList();
    });
  }

  Future<void> _toggle(ItemAsiento item) async {
    final isSel = _estaSel(item);
    if (!isSel && item.estado != 'disponible') return;
    if (_procesando.contains(item.idsilla)) return;
    if (!isSel && _sel.length >= _maxSel) return;
    setState(() => _procesando.add(item.idsilla));
    try {
      await _toggleSilla(item);
    } catch (_) {
      toast('Este asiento ya no está disponible. El mapa se ha actualizado.', color: C.rojo);
      _cargarLocalidad(reconcile: true);
    } finally {
      if (!_cerrada) setState(() => _procesando.remove(item.idsilla));
    }
  }

  Future<void> _cambiarCantidad(int delta) async {
    if (!_hayDatos || _actualizandoCant) return;
    /* Con x2 cada paso es un paquete de "factor" entradas. */
    final max = math.min(_resumen.disponibles, _maxSel) ~/ _factor;
    final next = _cantidad + delta;
    if (next < 1 || next > max) return;
    final anterior = _cantidad;
    setState(() {
      _cantidad = next;
      _actualizandoCant = true;
    });
    try {
      await dio.post('$urlBase/selecionar_localidad_correlativa',
          data: {
            'id': _id,
            'cedula': _cliente.cedula,
            'estado': 'reservado',
            'cantidad': _factor,
            'mas': delta == 1 ? 'mas' : 'menos',
            'id_usuario': _cliente.id,
            'id_operador': _idOperador,
          },
          options: hdr(apiHdr()));
      setState(() => _corrActivo = true);
    } catch (_) {
      setState(() => _cantidad = anterior);
      toast('Error al actualizar la reserva. Intenta de nuevo.', color: C.rojo);
    } finally {
      if (!_cerrada) setState(() => _actualizandoCant = false);
    }
  }

  bool _bloqueada(ItemAsiento item) {
    if (_estaSel(item)) return false;
    return item.estado != 'disponible' || _sel.length >= _maxSel;
  }

  EstiloAsiento _estilo(ItemAsiento item) {
    if (_estaSel(item)) return EstiloAsiento.seleccionado;
    if (item.estado == 'disponible') return EstiloAsiento.disponible;
    if (item.estado == 'reservado') return EstiloAsiento.reservado;
    return EstiloAsiento.ocupado;
  }

  int get _cantCarrito => _esCorrelativo ? _cantidad * _factor : _sel.length;
  int get _paquetes => _factor > 1 ? (_cantCarrito / _factor).ceil() : _cantCarrito;
  double get _totalCarrito => _paquetes * _precio;

  /* Mesas / filas con sillas sueltas (x2 exige pares completos en la misma mesa o fila). */
  List<String> get _gruposIncompletos {
    if (_factor <= 1 || _esCorrelativo) return [];
    final conteo = <String, int>{};
    for (final s in _sel) {
      final g = s.silla.replaceFirst(RegExp(r'-s-\d+\s*$', caseSensitive: false), '').split('__')[0];
      conteo[g] = (conteo[g] ?? 0) + 1;
    }
    return [
      for (final e in conteo.entries)
        if (e.value % _factor != 0) '${e.key} (${e.value})',
    ];
  }

  bool get _haySeleccionActiva => _esCorrelativo ? _corrActivo : _sel.isNotEmpty;

  bool get _listoParaPagar =>
      !_cargando &&
      _hayDatos &&
      _procesando.isEmpty &&
      !_actualizandoCant &&
      _gruposIncompletos.isEmpty &&
      _cantCarrito > 0;

  Future<void> _intentarSalir() async {
    final salir = await confirmar(context,
        titulo: '¿Salir sin terminar?',
        mensaje: 'Vas a perder los asientos que seleccionaste.',
        si: 'Salir',
        no: 'Seguir eligiendo',
        peligro: true);
    if (salir && mounted) Navigator.of(context).pop();
  }

  Future<void> _pagar() async {
    if (!_listoParaPagar) return;
    _pagando = true;
    _detenerTemporizadores();
    await ir(PagoPage(
      datos: DatosPago(
        idLocalidad: _id,
        codigoEvento: widget.evento.codigoEvento,
        idPrecio: widget.precio.id,
        nombreEvento: widget.evento.nombreConcierto,
        localidadNombre: _nombre,
        precio: _precio,
        cantidad: _cantCarrito,
        factorBoletos: _factor,
        modalidadCodigo: widget.precio.modalidadCodigo ?? '',
        idSillas: _esCorrelativo ? [] : _sel.map((s) => s.idsilla).toList(),
        /* Etiqueta de cada asiento (mismo orden que idSillas): Pago la usa para
           mostrar a qué silla se asigna cada boleto físico escaneado. */
        sillasSeleccionadas: _esCorrelativo ? [] : _sel.map<String?>((s) => s.silla).toList(),
        comisionBoleto: dbl(widget.precio.comisionBoleto),
        iva: widget.evento.iva,
        cliente: _cliente,
      ),
    ));
    /* Volvió de Pago sin cerrar la venta: arranque limpio. */
    if (mounted && !_cerrada) _entrar();
  }

  Widget _chip(IconData? icono, String texto, Color fondo, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          if (icono != null) ...[Icon(icono, size: 18, color: color), const SizedBox(width: 6)],
          Expanded(child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13.5))),
        ]),
      );

  Widget _vistaCorrelativo() => Tarjeta(
        child: Column(children: [
          Text('Boletos asignados automáticamente. Máx. $_maxSel.', style: TextStyle(color: colorTenue(context))),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(
                onPressed: _actualizandoCant ? null : () => _cambiarCantidad(-1), icon: const Icon(Icons.remove)),
            SizedBox(
              width: 70,
              child: Center(
                child: _actualizandoCant
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text('$_cantidad',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: colorTexto(context))),
              ),
            ),
            IconButton.filledTonal(
                onPressed: _actualizandoCant ? null : () => _cambiarCantidad(1), icon: const Icon(Icons.add)),
          ]),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '\$${f2(_precio)} × $_cantidad'
                      '${_factor > 1 ? ' (x$_factor: $_cantCarrito entradas)' : ''} = '),
              TextSpan(text: '\$${f2(_totalCarrito)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            style: TextStyle(color: colorTexto(context)),
          ),
        ]),
      );

  Widget _vistaMapa() {
    final incompletos = _gruposIncompletos;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Seleccione boletos. Máx. $_maxSel.', style: TextStyle(color: colorTenue(context))),
      if (_factor > 1)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'x$_factor', style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(
                text: ': elija de $_factor en $_factor sillas en la misma ${_tipo == 'mesa' ? 'mesa' : 'fila'} · '
                    '\$${f2(_precio)} cada $_factor.'),
            if (incompletos.isNotEmpty)
              TextSpan(text: ' Falta completar: ${incompletos.join(', ')}.', style: const TextStyle(color: C.rojoOscuro)),
          ])),
        ),
      const SizedBox(height: 8),
      const Leyenda([
        LeyendaItem('Disponible', EstiloAsiento.disponible),
        LeyendaItem('Reservada', EstiloAsiento.reservado),
        LeyendaItem('Ocupada', EstiloAsiento.ocupado),
        LeyendaItem('Seleccionada', EstiloAsiento.seleccionado),
      ]),
      if (_sel.length >= _maxSel)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Máximo $_maxSel asientos por venta', style: TextStyle(color: C.rojo, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 6),
      MapaAsientos(
        items: _items,
        esMesa: _tipo == 'mesa',
        alineacion: _alineacion,
        ordenSillas: _ordenSillas,
        estilo: _estilo,
        onTap: _toggle,
        deshabilitado: (i) => _bloqueada(i) || _procesando.contains(i.idsilla),
        atenuado: (i) => _bloqueada(i) && i.estado == 'disponible',
        procesando: (i) => _procesando.contains(i.idsilla),
        alto: MediaQuery.sizeOf(context).height * 0.5,
        zoomInicial: 0.7,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final imagenBloques = _imagenBloques ?? (widget.evento.mapaConcierto.isNotEmpty ? widget.evento.mapaConcierto : null);
    final critico = _segundos <= 30;
    return PopScope(
      canPop: !_haySeleccionActiva,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _intentarSalir();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_nombre.isEmpty ? 'Seleccionar asientos' : _nombre)),
        body: Contenido(children: [
          _chip(Icons.person_outline, 'Vendiendo a: ${_cliente.nombreOCedula}', const Color(0xFFFEF3C7),
              const Color(0xFF92400E)),
          _chip(
            Icons.schedule,
            'Tienes ${_formatMMSS(_segundos)} para completar la selección',
            critico ? C.rojoFondo : const Color(0xFFE3E5F8),
            critico ? C.rojoOscuro : C.azul,
          ),
          if (widget.evento.mapaConcierto.isNotEmpty)
            Tarjeta(
              padding: const EdgeInsets.all(10),
              onTap: () => verImagen(context, widget.evento.mapaConcierto, 'Mapa del lugar'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Mapa del lugar', style: TextStyle(fontWeight: FontWeight.w700, color: colorTenue(context))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(widget.evento.mapaConcierto,
                      height: 160, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
                ),
              ]),
            ),
          if (imagenBloques != null)
            OutlinedButton.icon(
              onPressed: () => verImagen(context, imagenBloques, 'División por bloques'),
              icon: const Icon(Icons.grid_view),
              label: const Text('Ver bloques en el mapa'),
            ),
          if (_cargando) const Cargando(texto: 'Cargando...'),
          if (!_cargando && _hayDatos && _esCorrelativo) _vistaCorrelativo(),
          if (!_cargando && _hayDatos && _esMapa) _vistaMapa(),
          if (!_cargando && !_hayDatos) const MensajeVacio('No se pudo cargar la localidad.', error: true),
        ]),
        bottomNavigationBar: _cantCarrito > 0
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: Row(children: [
                    Icon(Icons.shopping_cart_outlined, color: colorAcento(context), size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('$_cantCarrito/$_maxSel asientos', style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                        Text('\$${f2(_totalCarrito)}',
                            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: colorTexto(context))),
                      ]),
                    ),
                    FilledButton(
                      onPressed: _listoParaPagar ? _pagar : null,
                      style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                      child: const Text('Pagar'),
                    ),
                  ]),
                ),
              )
            : null,
      ),
    );
  }
}
