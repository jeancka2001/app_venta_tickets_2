import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../core/tema.dart';
import '../../services/admin_eventos.dart';
import '../../services/escaner.dart';
import '../../services/localidad_config.dart';
import '../../services/mapa_asientos.dart';
import '../../services/sincronizar_fisicos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/mapa_asientos.dart';

/* "Sincronizar boletos físicos" (solo admin): se elige una localidad
   numerada, se marcan en el mapa los asientos de boletos impresos y, en la
   lista, a cada asiento se le escribe una cédula/texto (opcional) y se le
   escanea el QR del boleto (opcional). Al guardar, cada asiento queda
   Ocupado -- en rojo si lleva cédula -- sin crear una compra. */

class _FilaSync {
  final ItemAsiento item;
  final cedula = TextEditingController();
  final codigo = TextEditingController();
  final foco = FocusNode();
  bool verificando = false;
  /* Código ya revisado (el que se manda). */
  String? codigoVerificado;
  String? seccion;
  String? filaAsiento;
  String aviso = '';
  String error = '';
  _FilaSync(this.item);

  void dispose() {
    cedula.dispose();
    codigo.dispose();
    foco.dispose();
  }
}

class AdminSincronizarFisicosPage extends StatefulWidget {
  final String codigoEvento;
  const AdminSincronizarFisicosPage({super.key, required this.codigoEvento});

  @override
  State<AdminSincronizarFisicosPage> createState() => _AdminSincronizarFisicosPageState();
}

class _AdminSincronizarFisicosPageState extends State<AdminSincronizarFisicosPage> {
  List<LocalidadAdmin> _localidades = [];
  bool _cargandoLocalidades = true;
  LocalidadAdmin? _localidad;

  List<ItemAsiento> _items = [];
  Map<String, String> _alineacion = {};
  Map<String, bool> _ordenSillas = {};
  int? _idEspacio;
  bool _cargandoMapa = false;

  final List<_FilaSync> _filas = [];
  final _cedulaTodas = TextEditingController();
  bool _escaneandoSecuencia = false;
  bool _guardando = false;

  bool get _esMesa => _localidad?.tipoLocalidad == 'mesa';

  @override
  void initState() {
    super.initState();
    listarLocalidadesAdmin(widget.codigoEvento).then((locs) {
      if (!mounted) return;
      final numeradas = locs.where((l) => l.esNumerada).toList();
      setState(() {
        _localidades = numeradas;
        _cargandoLocalidades = false;
      });
      if (numeradas.length == 1) _seleccionarLocalidad(numeradas.first);
    });
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    _cedulaTodas.dispose();
    super.dispose();
  }

  Future<void> _seleccionarLocalidad(LocalidadAdmin loc) async {
    setState(() {
      _localidad = loc;
      _items = [];
      _idEspacio = null;
      _cargandoMapa = true;
    });
    final cfg = await obtenerConfiguracionLocalidad(loc.idLocalidad!);
    if (!mounted) return;
    setState(() {
      _alineacion = cfg.alineacion;
      _ordenSillas = cfg.ordenSillas;
      _idEspacio = cfg.idEspacio;
    });
    if (cfg.idEspacio != null) {
      await _cargarMapa();
    } else {
      setState(() => _cargandoMapa = false);
    }
  }

  Future<void> _cargarMapa() async {
    if (_idEspacio == null || _localidad == null) return;
    setState(() => _cargandoMapa = true);
    final r = await obtenerMapaLocalidad(_idEspacio!, _localidad!.idLocalidad!);
    if (mounted) {
      setState(() {
        _items = r.items;
        _cargandoMapa = false;
      });
    }
  }

  Future<void> _elegirLocalidad(LocalidadAdmin loc) async {
    if (loc.id == _localidad?.id) return;
    if (_filas.isNotEmpty) {
      final si = await confirmar(context,
          titulo: 'Cambiar de localidad', mensaje: 'Se quitarán los asientos elegidos que todavía no guardaste.', si: 'Cambiar');
      if (!si) return;
      _quitarTodas();
    }
    _seleccionarLocalidad(loc);
  }

  /* ── Selección en el mapa ── */
  bool _estaSel(int idsilla) => _filas.any((f) => f.item.idsilla == idsilla);

  void _quitarFila(int idsilla) {
    final i = _filas.indexWhere((f) => f.item.idsilla == idsilla);
    if (i < 0) return;
    setState(() => _filas.removeAt(i).dispose());
  }

  void _quitarTodas() {
    for (final f in _filas) {
      f.dispose();
    }
    setState(() => _filas.clear());
  }

  void _tocarAsiento(ItemAsiento item) {
    if (_estaSel(item.idsilla)) return _quitarFila(item.idsilla);
    if (item.estado != 'disponible') {
      final detalle = [
        etiquetaAsiento(item, _esMesa),
        item.estado,
        if ((item.cedula ?? '').isNotEmpty) 'cédula ${item.cedula}',
        if (item.idRegistraCompra.isNotEmpty) 'código ${item.idRegistraCompra}',
      ].join(' · ');
      toast('$detalle -- no se puede sincronizar.');
      return;
    }
    setState(() => _filas.add(_FilaSync(item)));
  }

  /* Tocar la etiqueta de una fila selecciona todos sus asientos libres (o los
     quita si ya estaban todos elegidos). */
  void _tocarGrupo(List<ItemAsiento> grupo) {
    final libres = grupo.where((i) => i.estado == 'disponible').toList();
    if (libres.isEmpty) return;
    if (libres.every((i) => _estaSel(i.idsilla))) {
      for (final i in libres) {
        _quitarFila(i.idsilla);
      }
    } else {
      setState(() {
        for (final i in libres) {
          if (!_estaSel(i.idsilla)) _filas.add(_FilaSync(i));
        }
      });
    }
  }

  EstiloAsiento _estilo(ItemAsiento item) => _estaSel(item.idsilla) ? EstiloAsiento.seleccionado : estiloAsiento(item);

  void _enfocarSiguienteSinCodigo(_FilaSync despuesDe) {
    final idx = _filas.indexOf(despuesDe);
    final siguiente = _filas.skip(idx + 1).where((f) => f.codigo.text.trim().isEmpty).firstOrNull;
    if (siguiente != null) Future.delayed(const Duration(milliseconds: 50), () => siguiente.foco.requestFocus());
  }

  /* Revisa el código (duplicado en la lista, ya vinculado a otro asiento,
     vendido/anulado) y lo deja listo para guardar. true si quedó aceptado. */
  Future<bool> _asignarCodigo(_FilaSync fila, String crudo) async {
    final codigo = crudo.trim();
    if (codigo.isEmpty) {
      setState(() {
        fila.codigoVerificado = null;
        fila.seccion = null;
        fila.filaAsiento = null;
        fila.aviso = '';
        fila.error = '';
      });
      return false;
    }
    if (fila.codigoVerificado == codigo && fila.error.isEmpty) return true;
    if (fila.verificando) return false;
    final repetido = _filas.where((f) => f != fila && f.codigo.text.trim() == codigo).firstOrNull;
    if (repetido != null) {
      setState(() {
        fila.codigo.text = codigo;
        fila.codigoVerificado = null;
        fila.error = 'Ya lo escaneaste para ${etiquetaAsiento(repetido.item, _esMesa)}.';
      });
      return false;
    }
    setState(() {
      fila.codigo.text = codigo;
      fila.verificando = true;
      fila.codigoVerificado = null;
      fila.aviso = '';
      fila.error = '';
    });
    final r = await verificarCodigoFisico(widget.codigoEvento, codigo);
    /* Si mientras tanto se cambió o quitó el código, se descarta. */
    if (!mounted || !_filas.contains(fila) || fila.codigo.text.trim() != codigo) {
      fila.verificando = false;
      return false;
    }
    setState(() {
      fila.verificando = false;
      if (r.ok) {
        fila.codigoVerificado = codigo;
        fila.seccion = r.seccion;
        fila.filaAsiento = r.filaAsiento;
        fila.aviso = r.aviso ?? '';
      } else {
        fila.seccion = null;
        fila.filaAsiento = null;
        fila.error = r.mensaje;
      }
    });
    return r.ok;
  }

  Future<void> _escanearParaFila(_FilaSync fila) async {
    final r = await escanearBoletoFisico(titulo: etiquetaAsiento(fila.item, _esMesa));
    if (r.ok && r.codigo != null) {
      if (await _asignarCodigo(fila, r.codigo!)) _enfocarSiguienteSinCodigo(fila);
    } else if (r.mensaje != null) {
      toast(r.mensaje!);
    }
  }

  /* Abre la cámara para cada asiento sin código, uno tras otro. */
  Future<void> _escanearEnSecuencia() async {
    setState(() => _escaneandoSecuencia = true);
    try {
      while (mounted) {
        final siguiente = _filas.where((f) => f.codigo.text.trim().isEmpty).firstOrNull;
        if (siguiente == null) {
          toast('Todos los asientos tienen código.');
          break;
        }
        final r = await escanearBoletoFisico(titulo: 'Boleto para ${etiquetaAsiento(siguiente.item, _esMesa)}');
        if (!r.ok || r.codigo == null) {
          if (r.mensaje != null) toast(r.mensaje!);
          break;
        }
        if (!await _asignarCodigo(siguiente, r.codigo!)) {
          toast('Código rechazado -- revisa la lista.');
          break;
        }
      }
    } finally {
      if (mounted) setState(() => _escaneandoSecuencia = false);
    }
  }

  bool get _pendientesVerificar => _filas.any((f) => f.verificando);
  List<_FilaSync> get _conError => _filas
      .where((f) => f.error.isNotEmpty || (f.codigo.text.trim().isNotEmpty && f.codigoVerificado != f.codigo.text.trim()))
      .toList();
  bool get _puedeGuardar => _filas.isNotEmpty && !_pendientesVerificar && _conError.isEmpty && !_guardando;

  Future<void> _confirmarGuardar() async {
    final conCodigo = _filas.where((f) => f.codigoVerificado != null).length;
    final conCedula = _filas.where((f) => f.cedula.text.trim().isNotEmpty).length;
    final total = _filas.length;
    final si = await confirmar(
      context,
      titulo: 'Sincronizar asientos',
      mensaje: '$total asiento(s) de ${_localidad?.localidad ?? ''} quedarán ocupados: $conCodigo con QR del boleto físico '
          'y $conCedula con cédula.'
          '${conCedula > 0 && conCedula < total ? ' ⚠ ${total - conCedula} fila(s) van SIN cédula: si son de la misma persona o empresa, usa "Aplicar a todas".' : ''}',
      si: 'Guardar',
    );
    if (si) _guardar();
  }

  Future<void> _guardar() async {
    final loc = _localidad;
    if (loc?.idLocalidad == null) return;
    setState(() => _guardando = true);
    final enviados = [..._filas];
    final r = await sincronizarAsientosFisicos(
      widget.codigoEvento,
      loc!.idLocalidad!,
      enviados
          .map((f) => AsientoSincronizar(f.item.idsilla, f.codigoVerificado,
              f.cedula.text.trim().isEmpty ? null : f.cedula.text.trim(), f.seccion))
          .toList(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (!r.ok) {
      await informar(context, titulo: 'Sincronización parcial', mensaje: '0 asiento(s) guardado(s). Petición: ${r.mensaje}', ok: 'OK');
      return;
    }
    /* Sin detalle por asiento = todos OK. */
    final porId = {for (final x in r.resultados) x.idLocalidadesItems: x};
    String mensajeDe(int id) {
      final res = porId[id];
      final base = res?.message ?? 'No se pudo guardar este asiento (el backend no devolvió motivo).';
      return res?.paso != null ? '$base [paso: ${res!.paso}]' : base;
    }

    final fallidos = enviados.where((f) => porId.isNotEmpty && !(porId[f.item.idsilla]?.ok ?? false)).toList();
    setState(() {
      for (final f in enviados) {
        if (!fallidos.contains(f)) {
          _filas.remove(f);
          f.dispose();
        } else {
          f.error = mensajeDe(f.item.idsilla);
        }
      }
    });
    await informar(
      context,
      titulo: fallidos.isNotEmpty ? 'Sincronización parcial' : 'Asientos sincronizados',
      mensaje: '${enviados.length - fallidos.length} asiento(s) guardado(s).'
          '${fallidos.isNotEmpty ? ' No se guardaron: ${fallidos.map((f) => '${etiquetaAsiento(f.item, _esMesa)} (${mensajeDe(f.item.idsilla)})').join('; ')}' : ''}',
      ok: 'OK',
    );
    _cargarMapa();
  }

  Widget _estadoFila(_FilaSync f) {
    if (f.verificando) {
      return const Row(children: [MiniSpinner(color: C.azul), SizedBox(width: 8), Text('Verificando código…')]);
    }
    if (f.error.isNotEmpty) return Text('⚠ ${f.error}', style: const TextStyle(color: C.rojoOscuro, fontWeight: FontWeight.w600));
    if (f.codigoVerificado != null) {
      final impreso = [f.seccion, if (f.filaAsiento != null) 'N.º ${f.filaAsiento}'].whereType<String>().join(' · ');
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('✓ QR listo${impreso.isNotEmpty ? ' · Impreso: $impreso' : ''}',
            style: const TextStyle(color: C.verde, fontWeight: FontWeight.w700)),
        if (f.aviso.isNotEmpty) Text('⚠ ${f.aviso}', style: const TextStyle(color: Color(0xFFB45309))),
      ]);
    }
    return Text(
      f.cedula.text.trim().isNotEmpty ? 'Se guardará con cédula (rojo), sin QR.' : 'Sin QR ni cédula: solo se marcará ocupado.',
      style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
    );
  }

  Widget _tarjetaFila(int i, _FilaSync f) => Tarjeta(
        borde: f.error.isNotEmpty ? C.rojo : (f.codigoVerificado != null ? C.verde : null),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('#${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: colorTenue(context))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(etiquetaAsiento(f.item, _esMesa),
                  style: TextStyle(fontWeight: FontWeight.w800, color: colorTexto(context))),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => _quitarFila(f.item.idsilla)),
          ]),
          TextField(
            controller: f.cedula,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Cédula o texto (opcional)', counterText: ''),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Focus(
                onFocusChange: (tiene) {
                  if (!tiene && f.codigo.text.trim().isNotEmpty) _asignarCodigo(f, f.codigo.text);
                },
                child: TextField(
                  controller: f.codigo,
                  focusNode: f.foco,
                  enabled: !f.verificando,
                  autocorrect: false,
                  onChanged: (_) => setState(() {
                    f.codigoVerificado = null;
                    f.error = '';
                    f.aviso = '';
                  }),
                  onSubmitted: (v) async {
                    if (await _asignarCodigo(f, v)) _enfocarSiguienteSinCodigo(f);
                  },
                  decoration: const InputDecoration(hintText: 'QR / código del boleto físico (opcional)'),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: (f.verificando || _escaneandoSecuencia) ? null : () => _escanearParaFila(f),
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ]),
          const SizedBox(height: 6),
          _estadoFila(f),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final loc = _localidad;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizar boletos físicos'),
        actions: [IconButton(onPressed: (_cargandoMapa || loc == null) ? null : _cargarMapa, icon: const Icon(Icons.refresh))],
      ),
      body: Contenido(children: [
        Text(
          'Elige la localidad numerada y marca en el mapa los asientos que vas a asignar a boletos físicos. Luego, en la '
          'lista, escribe la cédula (opcional) y escanea el QR de cada boleto impreso.',
          style: TextStyle(color: colorTenue(context)),
        ),
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloTarjeta('1. Localidad'),
            if (_cargandoLocalidades) const Center(child: CircularProgressIndicator()),
            if (!_cargandoLocalidades && _localidades.isEmpty)
              Text('Este evento no tiene localidades numeradas (fila/mesa) con mapa de asientos.',
                  style: TextStyle(color: colorTenue(context))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in _localidades)
                ChoiceChip(
                  label: Text('${l.localidad} · ${l.tipoLocalidad}'),
                  selected: loc?.id == l.id,
                  onSelected: (_) => _elegirLocalidad(l),
                ),
            ]),
          ]),
        ),
        if (loc != null)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('2. Asientos en el mapa'),
              if (_cargandoMapa) const Cargando(texto: 'Cargando mapa...'),
              if (!_cargandoMapa && _items.isEmpty)
                Text('No se encontraron asientos para esta localidad.', style: TextStyle(color: colorTenue(context))),
              if (!_cargandoMapa && _items.isNotEmpty) ...[
                const Leyenda([
                  LeyendaItem('Disponible', EstiloAsiento.disponible),
                  LeyendaItem('Elegida', EstiloAsiento.seleccionado),
                  LeyendaItem('Ocupada', EstiloAsiento.bloqueado),
                  LeyendaItem('Con cédula', EstiloAsiento.ocupado),
                ]),
                const SizedBox(height: 6),
                Text(
                  'Toca los asientos para elegirlos (toca la fila para elegirla completa). Pellizca para hacer zoom.'
                  '${_filas.isNotEmpty ? ' ${_filas.length} elegido${_filas.length > 1 ? 's' : ''}.' : ''}',
                  style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
                ),
                const SizedBox(height: 6),
                MapaAsientos(
                  items: _items,
                  esMesa: _esMesa,
                  alineacion: _alineacion,
                  ordenSillas: _ordenSillas,
                  estilo: _estilo,
                  onTap: _tocarAsiento,
                  onTapGrupo: _tocarGrupo,
                  alto: MediaQuery.sizeOf(context).height * 0.5,
                ),
              ],
            ]),
          ),
        if (loc != null && _filas.isNotEmpty)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TituloTarjeta('3. Boletos (${_filas.length})',
                  trailing: TextButton(onPressed: _quitarTodas, child: const Text('Quitar todos'))),
              Text(
                'Escribe en el boleto impreso la fila y silla que indica cada tarjeta. La cédula pinta el asiento en rojo; '
                'el QR hace que el boleto físico abra este asiento al escanearlo.',
                style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
              ),
              const SizedBox(height: 8),
              BotonAccion('Escanear QR en secuencia',
                  icono: Icons.fast_forward,
                  onPressed: (_escaneandoSecuencia || _guardando || _filas.every((f) => f.codigo.text.trim().isNotEmpty))
                      ? null
                      : _escanearEnSecuencia),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cedulaTodas,
                    maxLength: 60,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Cédula o texto para todas las filas', counterText: ''),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: (_cedulaTodas.text.trim().isEmpty || _guardando)
                      ? null
                      : () => setState(() {
                            for (final f in _filas) {
                              f.cedula.text = _cedulaTodas.text.trim();
                            }
                          }),
                  child: const Text('Aplicar a todas'),
                ),
              ]),
              const SizedBox(height: 8),
              for (final (i, f) in _filas.indexed) ...[_tarjetaFila(i, f), const SizedBox(height: 8)],
            ]),
          ),
        const SizedBox(height: 80),
      ]),
      bottomNavigationBar: (loc != null && _filas.isNotEmpty)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  BotonAccion('Guardar ${_filas.length} asiento${_filas.length > 1 ? 's' : ''}',
                      icono: Icons.save_outlined,
                      primario: true,
                      cargando: _guardando,
                      onPressed: _puedeGuardar ? _confirmarGuardar : null),
                  if (_conError.isNotEmpty && !_pendientesVerificar)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Corrige o borra los códigos marcados en rojo para poder guardar.',
                          textAlign: TextAlign.center, style: TextStyle(color: C.rojoOscuro, fontSize: 12.5)),
                    ),
                ]),
              ),
            )
          : null,
    );
  }
}
