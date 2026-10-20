import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/nav.dart';
import '../core/tema.dart';
import '../services/canje_boletos.dart';
import '../services/escaner.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import 'detalle_compra_page.dart';

/* La misma pantalla sirve para canjear y para descanjear (selector arriba).
   Cada modo tiene su propia lista.
   Canjear -> pendiente: lista para canjear · yaCanjeado: estaba canjeada al
     escanear · canjeado: hecho aquí
   Descanjear -> pendiente: canjeada, lista para descanjear · noCanjeado: no
     estaba canjeada · descanjeado: hecho aquí */
enum _Modo { canjear, descanjear }

enum _Estado { pendiente, yaCanjeado, canjeado, noCanjeado, descanjeado, error }

class _Item {
  final _Modo modo;
  final String codigo;
  final BoletoCanje boleto;
  _Estado estado;
  String? mensaje;
  _Item(this.modo, this.codigo, this.boleto, this.estado);
}

class _AvisoCanje {
  final bool rojo;
  final String titulo;
  final String mensaje;
  const _AvisoCanje(this.rojo, this.titulo, this.mensaje);
}

Future<void> _vibrar(bool error) async {
  if (error) {
    await HapticFeedback.heavyImpact();
    await HapticFeedback.vibrate();
  } else {
    await HapticFeedback.mediumImpact();
  }
}

class CanjearEntradasPage extends StatefulWidget {
  const CanjearEntradasPage({super.key});

  @override
  State<CanjearEntradasPage> createState() => _CanjearEntradasPageState();
}

class _CanjearEntradasPageState extends State<CanjearEntradasPage> {
  _Modo _modo = _Modo.canjear;
  final List<_Item> _todos = [];
  final _codigo = TextEditingController();
  final _foco = FocusNode();
  Timer? _autoEnvio;
  int _consultando = 0;
  _AvisoCanje? _aviso;
  bool _continuo = true;
  bool _canjeando = false;
  ({int ok, int fallidos})? _resumen;
  /* Lectores de código (USB, Bluetooth, PDA) se comportan como teclado: el
     campo recibe lo que "teclean" pero sin mostrar el teclado en pantalla. El
     botón de teclado lo activa para escribir a mano. */
  bool _tecladoVisible = false;
  /* Códigos ya en la lista o consultándose ("modo|código"). */
  final Set<String> _vistos = {};

  bool get _esDescanje => _modo == _Modo.descanjear;
  List<_Item> get _items => _todos.where((i) => i.modo == _modo).toList();
  List<_Item> get _pendientes => _items.where((i) => i.estado == _Estado.pendiente).toList();
  String _clave(_Modo m, String c) => '${m.name}|$c';

  @override
  void initState() {
    super.initState();
    _codigo.addListener(() {
      _autoEnvio?.cancel();
      if (_codigo.text.trim().isEmpty) return;
      _autoEnvio = Timer(const Duration(milliseconds: 600), _enviarInput);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _enfocar());
  }

  @override
  void dispose() {
    _autoEnvio?.cancel();
    _codigo.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _enfocar() {
    if (!mounted) return;
    _foco.requestFocus();
    if (!_tecladoVisible) SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _alternarTeclado() {
    setState(() => _tecladoVisible = !_tecladoVisible);
    _foco.unfocus();
    Future.delayed(const Duration(milliseconds: 80), () {
      _foco.requestFocus();
      if (_tecladoVisible) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    });
  }

  void _mostrarAviso(_AvisoCanje a) {
    setState(() => _aviso = a);
    _vibrar(true);
  }

  /* Devuelve false si hubo un aviso (duplicado, ya canjeada, no encontrada)
     para cortar el escaneo continuo y que el operador lo vea. */
  Future<bool> _agregarCodigo(String crudo) async {
    final codigo = crudo.trim();
    if (codigo.isEmpty) return true;
    final m = _modo;
    final k = _clave(m, codigo);

    if (_vistos.contains(k)) {
      final previo = _todos.where((i) => i.modo == m && i.codigo == codigo).firstOrNull;
      if (m == _Modo.descanjear) {
        _mostrarAviso(_AvisoCanje(false, 'Entrada escaneada dos veces',
            previo?.estado == _Estado.descanjeado ? 'El código $codigo ya fue descanjeado.' : 'El código $codigo ya está en la lista.'));
        return false;
      }
      if (previo != null && (previo.estado == _Estado.canjeado || previo.estado == _Estado.yaCanjeado)) {
        _mostrarAviso(_AvisoCanje(true, 'Entrada YA CANJEADA',
            '${previo.boleto.descripcion} (código $codigo) ya fue canjeada. No permitir el ingreso.'));
        return false;
      }
      _mostrarAviso(_AvisoCanje(false, 'Entrada escaneada dos veces', 'El código $codigo ya está en la lista.'));
      return false;
    }

    _vistos.add(k);
    setState(() => _consultando++);
    final r = await consultarBoletoCanje(codigo);
    if (!mounted) return false;
    setState(() => _consultando--);

    final b = r.boleto;
    if (b == null) {
      _vistos.remove(k);
      _mostrarAviso(_AvisoCanje(true, 'Entrada no válida', '${r.mensaje} ($codigo)'));
      return false;
    }
    if (b.idTicket == null) {
      _vistos.remove(k);
      _mostrarAviso(_AvisoCanje(true, 'Entrada sin ticket',
          'El asiento del código $codigo no tiene un ticket emitido (compra no pagada o sin generar).'));
      return false;
    }

    final yaCanjeado = b.canjeado;
    if (m == _Modo.descanjear) {
      setState(() => _todos.insert(0, _Item(m, codigo, b, yaCanjeado ? _Estado.pendiente : _Estado.noCanjeado)));
      if (!yaCanjeado) {
        _mostrarAviso(_AvisoCanje(false, 'Entrada NO canjeada',
            '${b.descripcion} · ${b.localidadLimpia} no está canjeada; no hay nada que descanjear.'));
        return false;
      }
      setState(() => _aviso = null);
      _vibrar(false);
      return true;
    }

    setState(() => _todos.insert(0, _Item(m, codigo, b, yaCanjeado ? _Estado.yaCanjeado : _Estado.pendiente)));
    if (yaCanjeado) {
      _mostrarAviso(_AvisoCanje(
          true, 'Entrada YA CANJEADA', '${b.descripcion} · ${b.localidadLimpia} ya fue canjeada. No permitir el ingreso.'));
      return false;
    }
    setState(() => _aviso = null);
    _vibrar(false);
    return true;
  }

  Future<void> _enviarInput() async {
    _autoEnvio?.cancel();
    final codigo = _codigo.text.trim();
    if (codigo.isEmpty) return;
    _codigo.clear();
    await _agregarCodigo(codigo);
    _enfocar();
  }

  /* En modo continuo la cámara se vuelve a abrir sola después de cada lectura
     correcta; se detiene al cerrarla o si sale algún aviso. */
  Future<void> _escanearConCamara() async {
    while (mounted) {
      final r = await escanearBoletoFisico(titulo: _esDescanje ? 'Descanjear entradas' : 'Canjear entradas');
      if (!r.ok || r.codigo == null) {
        if (r.mensaje != null) _mostrarAviso(_AvisoCanje(false, 'Escáner', r.mensaje!));
        _enfocar();
        return;
      }
      final siguio = await _agregarCodigo(r.codigo!);
      if (!_continuo || !siguio) {
        _enfocar();
        return;
      }
    }
  }

  void _quitarItem(String codigo) {
    _vistos.remove(_clave(_modo, codigo));
    setState(() => _todos.removeWhere((i) => i.modo == _modo && i.codigo == codigo));
    _enfocar();
  }

  void _limpiarLista() {
    for (final i in _items) {
      _vistos.remove(_clave(_modo, i.codigo));
    }
    setState(() {
      _todos.removeWhere((i) => i.modo == _modo);
      _aviso = null;
      _resumen = null;
    });
    _enfocar();
  }

  Future<void> _confirmarYEjecutar() async {
    final pendientes = _pendientes;
    final motivoCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text(_esDescanje ? 'Confirmar descanje' : 'Confirmar canje',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: colorTexto(ctx))),
            const SizedBox(height: 10),
            Text(_esDescanje
                ? 'Se van a descanjear ${pendientes.length} entrada${pendientes.length == 1 ? '' : 's'}. Volverán a quedar '
                    '"sin canjear" y podrán usarse otra vez para ingresar.'
                : 'Se van a canjear ${pendientes.length} entrada${pendientes.length == 1 ? '' : 's'}. Una vez canjeadas no '
                    'se pueden volver a usar.'),
            if (_esDescanje) ...[
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
              ),
            ],
            const SizedBox(height: 12),
            for (final i in pendientes) _tarjetaItem(i, conQuitar: false),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: _esDescanje ? FilledButton.styleFrom(backgroundColor: C.naranja) : null,
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirmar'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    final motivo = motivoCtrl.text.trim();
    motivoCtrl.dispose();
    if (ok == true) await _ejecutar(pendientes, motivo);
    _enfocar();
  }

  Future<void> _ejecutar(List<_Item> pendientes, String motivo) async {
    setState(() => _canjeando = true);
    final staff = obtenerStaffData();
    final operador = {'id': staff?.id, 'usuario': staff?.username ?? staff?.name, 'app': 'APP_VENTA_TICKETS'};
    var ok = 0;
    var fallidos = 0;
    for (final item in pendientes) {
      final info = {
        'codigo': item.codigo,
        'codigoEvento': item.boleto.codigoEvento,
        'localidad': item.boleto.localidadLimpia,
        'entrada': item.boleto.descripcion,
        'operador': operador,
      };
      final r = _esDescanje
          ? await descanjearEntrada(item.boleto.idTicket!, item.boleto.cedula ?? '', motivo, info)
          : await canjearEntrada(item.boleto.idTicket!, item.boleto.cedula ?? '', info);
      if (r.ok) {
        ok++;
      } else {
        fallidos++;
      }
      setState(() {
        if (r.ok) {
          item.estado = _esDescanje ? _Estado.descanjeado : _Estado.canjeado;
          item.mensaje = null;
        } else {
          item.estado = r.yaCanjeado ? _Estado.yaCanjeado : _Estado.error;
          item.mensaje = r.mensaje;
        }
      });
    }
    setState(() {
      _canjeando = false;
      _resumen = (ok: ok, fallidos: fallidos);
    });
    _vibrar(fallidos > 0);
  }

  void _cambiarModo(_Modo nuevo) {
    if (nuevo == _modo || _canjeando) return;
    setState(() {
      _modo = nuevo;
      _aviso = null;
      _resumen = null;
    });
    _codigo.clear();
    _enfocar();
  }

  Widget _chipEstado(_Item i) {
    final (texto, fondo, color) = switch (i.estado) {
      _Estado.pendiente => (_esDescanje ? 'Por descanjear' : 'Por canjear', const Color(0xFFE3E5F8), C.azul),
      _Estado.descanjeado => ('↩ Descanjeada', C.naranjaFondo, const Color(0xFFB45309)),
      _Estado.noCanjeado => ('⚠ No está canjeada', C.naranjaFondo, const Color(0xFFB45309)),
      _Estado.canjeado => ('✓ Canjeada', const Color(0xFFD4F1DD), const Color(0xFF155724)),
      _Estado.yaCanjeado => ('✗ Ya canjeada', C.rojoFondo, C.rojoOscuro),
      _Estado.error => ('✗ ${i.mensaje ?? 'Error'}', C.rojoFondo, C.rojoOscuro),
    };
    return Insignia(texto, fondo: fondo, color: color);
  }

  Widget _tarjetaItem(_Item i, {bool conQuitar = true}) {
    final b = i.boleto;
    final borde = switch (i.estado) {
      _Estado.canjeado => C.verde,
      _Estado.yaCanjeado || _Estado.error => C.rojo,
      _Estado.noCanjeado || _Estado.descanjeado => C.naranja,
      _Estado.pendiente => C.borde,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tarjeta(
        borde: borde,
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.descripcion, style: TextStyle(fontWeight: FontWeight.w800, color: colorTexto(context))),
              Text([b.localidadLimpia, b.concierto ?? ''].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
              Text('${(b.cedula ?? '').isNotEmpty ? 'C.I. ${b.cedula} · ' : ''}Código ${i.codigo}',
                  style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
              const SizedBox(height: 4),
              _chipEstado(i),
            ]),
          ),
          if (conQuitar &&
              !_canjeando &&
              const [_Estado.pendiente, _Estado.yaCanjeado, _Estado.noCanjeado, _Estado.error].contains(i.estado))
            IconButton(icon: const Icon(Icons.close), onPressed: () => _quitarItem(i.codigo)),
        ]),
      ),
    );
  }

  /* Órdenes de compra de las entradas ya canjeadas, para verificar el resto. */
  List<({int id, String? nombre, String? cedula, int escaneadas})> get _ordenes {
    final mapa = <int, ({int id, String? nombre, String? cedula, int escaneadas})>{};
    for (final i in _items) {
      final id = i.boleto.idRegistraCompra;
      if (id == null || ![_Estado.canjeado, _Estado.yaCanjeado, _Estado.descanjeado].contains(i.estado)) continue;
      final o = mapa[id];
      mapa[id] = (
        id: id,
        nombre: o?.nombre ?? i.boleto.nombreCompleto,
        cedula: o?.cedula ?? i.boleto.cedula,
        escaneadas: (o?.escaneadas ?? 0) + 1,
      );
    }
    return mapa.values.toList();
  }

  Widget _avisoWidget(_AvisoCanje a) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: a.rojo ? C.rojoFondo : C.naranjaFondo,
          border: Border.all(color: a.rojo ? C.rojo : C.naranja, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(a.rojo ? Icons.cancel : Icons.warning_amber_rounded, color: a.rojo ? C.rojo : C.naranja, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.titulo,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: a.rojo ? C.rojoOscuro : const Color(0xFFB45309))),
              Text(a.mensaje, style: const TextStyle(color: C.azulOscuro)),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() => _aviso = null);
              _enfocar();
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final pendientes = _pendientes;
    final ordenes = _ordenes;
    final res = _resumen;
    return Scaffold(
      appBar: AppBar(
        title: TituloConLogo(_esDescanje ? 'Descanjear entradas' : 'Canjear entradas'),
        actions: [
          if (items.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _canjeando ? null : _limpiarLista),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<_Modo>(
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.white,
                selectedBackgroundColor: _esDescanje ? C.naranja : C.verde,
                selectedForegroundColor: Colors.white,
              ),
              segments: const [
                ButtonSegment(value: _Modo.canjear, icon: Icon(Icons.done_all), label: Text('Canjear')),
                ButtonSegment(value: _Modo.descanjear, icon: Icon(Icons.undo), label: Text('Descanjear')),
              ],
              selected: {_modo},
              onSelectionChanged: _canjeando ? null : (s) => _cambiarModo(s.first),
            ),
          ),
        ),
      ),
      body: Contenido(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codigo,
              focusNode: _foco,
              enabled: !_canjeando,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: _tecladoVisible ? TextInputType.text : TextInputType.none,
              onSubmitted: (_) => _enviarInput(),
              decoration: InputDecoration(
                hintText: _tecladoVisible ? 'Escribe el código y presiona Enter' : 'Listo para escanear…',
              ),
            ),
          ),
          const SizedBox(width: 6),
          _tecladoVisible
              ? IconButton.filled(onPressed: _canjeando ? null : _alternarTeclado, icon: const Icon(Icons.keyboard))
              : IconButton.outlined(onPressed: _canjeando ? null : _alternarTeclado, icon: const Icon(Icons.keyboard)),
          const SizedBox(width: 4),
          IconButton.filled(onPressed: _canjeando ? null : _escanearConCamara, icon: const Icon(Icons.qr_code_scanner)),
        ]),
        SwitchListTile(
          value: _continuo,
          onChanged: (v) => setState(() => _continuo = v),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Escaneo continuo (la cámara se vuelve a abrir tras cada entrada)'),
        ),
        if (_aviso != null) _avisoWidget(_aviso!),
        if (res != null)
          Aviso(
            '${_esDescanje ? 'Descanje' : 'Canje'} terminado: ${res.ok} entrada${res.ok == 1 ? '' : 's'} '
            '${_esDescanje ? 'descanjeada' : 'canjeada'}${res.ok == 1 ? '' : 's'}'
            '${res.fallidos > 0 ? ' · ${res.fallidos} no se pudo ${_esDescanje ? 'descanjear' : 'canjear'} (ver lista)' : ''}.',
            icono: Icons.done_all,
            color: res.fallidos > 0 ? const Color(0xFFB45309) : const Color(0xFF155724),
            fondo: res.fallidos > 0 ? C.naranjaFondo : const Color(0xFFD4F1DD),
          ),
        if (_consultando > 0)
          const Row(children: [MiniSpinner(color: C.azul), SizedBox(width: 10), Text('Consultando entrada…')]),
        if (items.isEmpty && _consultando == 0)
          MensajeVacio(
            _esDescanje
                ? 'Escanea las entradas canjeadas que quieres devolver a "sin canjear". Al terminar presiona Descanjear.'
                : 'Escanea una o varias entradas (digitales o físicas). Se irán agregando a la lista; al terminar presiona Canjear.',
            icono: _esDescanje ? Icons.undo : Icons.confirmation_number_outlined,
          ),
        if (items.isNotEmpty) ...[
          Text('Entradas escaneadas (${items.length}) · ${pendientes.length} por ${_esDescanje ? 'descanjear' : 'canjear'}',
              style: TextStyle(fontWeight: FontWeight.w700, color: colorTenue(context))),
          Column(children: [for (final i in items) _tarjetaItem(i)]),
          if (ordenes.isNotEmpty) ...[
            Text('Órdenes de compra (${ordenes.length})', style: TextStyle(fontWeight: FontWeight.w700, color: colorTenue(context))),
            Text('Entra a la orden para verificar el estado de canje de todas sus entradas.',
                style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
            for (final o in ordenes)
              Tarjeta(
                padding: EdgeInsets.zero,
                onTap: () => ir(DetalleCompraPage(id: o.id)),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('Orden #${o.id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    [o.nombre, if (o.cedula != null) 'C.I. ${o.cedula}'].where((s) => s != null && s.isNotEmpty).join(' · '),
                    '${o.escaneadas} entrada${o.escaneadas == 1 ? '' : 's'} escaneada${o.escaneadas == 1 ? '' : 's'} aquí',
                  ].where((s) => s.isNotEmpty).join('\n')),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
          ],
        ],
        const SizedBox(height: 70),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: BotonAccion(
            '${_esDescanje ? 'Descanjear' : 'Canjear'}${pendientes.isNotEmpty ? ' (${pendientes.length})' : ''}',
            icono: _esDescanje ? Icons.undo : Icons.done_all,
            primario: true,
            color: _esDescanje ? C.naranja : C.verde,
            cargando: _canjeando,
            onPressed: (pendientes.isEmpty || _consultando > 0) ? null : _confirmarYEjecutar,
          ),
        ),
      ),
    );
  }
}
