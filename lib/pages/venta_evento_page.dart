import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/imagen_zoom.dart';
import 'detalle_compra_page.dart';
import 'localidad_page.dart';

class VentaEventoPage extends StatefulWidget {
  final EventoVenta evento;
  const VentaEventoPage({super.key, required this.evento});

  @override
  State<VentaEventoPage> createState() => _VentaEventoPageState();
}

class _CompraPendiente {
  final int id;
  final String estadoPago;
  final String totalPago;
  final String nombreConcierto;
  _CompraPendiente(this.id, this.estadoPago, this.totalPago, this.nombreConcierto);
}

class _VentaEventoPageState extends State<VentaEventoPage> {
  EventoVenta get ev => widget.evento;

  /* ── Cliente ── */
  final _cedula = TextEditingController();
  bool _buscando = false;
  Cliente? _cliente;
  bool _noEncontrado = false;
  String _error = '';

  /* Formulario de cliente nuevo */
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _movil = TextEditingController();
  final _ciudad = TextEditingController();
  /* De dónde salieron los datos precargados -- null si hay que llenarlo a mano. */
  String? _fuenteDatos;
  int _intentosCorreoDup = 0;

  /* ── Localidades / precios ── */
  List<PrecioLocalidad> _precios = [];
  bool _cargandoPrecios = false;

  /* ── Compra pendiente: si el cliente ya tiene una orden sin resolver, no se
     le deja generar otra. ── */
  _CompraPendiente? _compraPendiente;
  bool _verificandoPendiente = false;

  /* Si no hay imagen de bloques configurada, "Ver bloques" cae al mapa. */
  String? _imagenBloques;

  @override
  void initState() {
    super.initState();
    _cargarImagenBloques();
  }

  @override
  void dispose() {
    for (final c in [_cedula, _nombre, _email, _movil, _ciudad]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarImagenBloques() async {
    try {
      final r = await dio.get('$urlBase/imagenBloques/${ev.codigoEvento}', options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true && data['imagen_bloques'] != null && mounted) {
        setState(() => _imagenBloques = str(data['imagen_bloques']));
      }
    } catch (_) {}
  }

  String? get _imagenBloquesMostrar =>
      _imagenBloques ?? (ev.mapaConcierto.isNotEmpty ? ev.mapaConcierto : null);

  /* Si la cédula no está registrada, se intenta autocompletar con el
     Registro Civil vía SRI y, si falla, con Manta (mismo orden que la web). */
  Future<({String name, String telefono, String direccion, String fuente})?> _buscarEnRegistroCivil(String cedula) async {
    for (final (ruta, fuente) in [('consultar_cedula_sri', 'SRI'), ('consultar_cedula_turnos', 'MANTA')]) {
      try {
        final r = await dio.get('$urlBase/$ruta/$cedula', options: hdr(apiHdr()));
        final data = asMap(r.data);
        if (data['success'] == true && data['data'] != null) {
          final d = asMap(data['data']);
          return (name: str(d['name']), telefono: str(d['telefono']), direccion: str(d['direccion']), fuente: fuente);
        }
      } catch (_) {
        /* intenta la siguiente fuente */
      }
    }
    return null;
  }

  Future<void> _buscarCliente() async {
    final cedula = _cedula.text.trim();
    FocusScope.of(context).unfocus();
    if (cedula.isEmpty) {
      setState(() => _error = 'Ingresa una cédula.');
      return;
    }
    setState(() {
      _buscando = true;
      _error = '';
      _noEncontrado = false;
      _fuenteDatos = null;
    });
    try {
      final r = await dio.post('$urlBase/consultar_cedula', data: {'cedula': cedula, 'email': ''}, options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true && data['data'] != null) {
        final d = asMap(data['data']);
        _seleccionarCliente(Cliente(
          id: ent(d['id']),
          cedula: cedula,
          nombreCompleto: str(d['nombreCompleto']),
          email: str(d['email']),
          movil: str(d['movil']),
          ciudad: str(d['ciudad']),
          esNuevo: false,
        ));
      } else {
        for (final c in [_nombre, _email, _movil, _ciudad]) {
          c.clear();
        }
        setState(() => _noEncontrado = true);
        final civil = await _buscarEnRegistroCivil(cedula);
        if (civil != null && mounted) {
          _nombre.text = civil.name;
          _movil.text = civil.telefono;
          _ciudad.text = civil.direccion;
          setState(() => _fuenteDatos = civil.fuente);
        }
      }
    } catch (_) {
      setState(() => _error = 'Error de conexión al buscar el cliente.');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _manejarErrorCrearCliente(String? mensajeBackend) {
    final esCorreoDuplicado =
        RegExp(r'correo.*(registrad|usad|existe|repite|otro)', caseSensitive: false).hasMatch(mensajeBackend ?? '');
    setState(() {
      if (esCorreoDuplicado) {
        _intentosCorreoDup++;
        _error = _intentosCorreoDup >= 2
            ? 'Ese correo sigue sin funcionar. Prueba con otro usuario: busca al cliente por su cédula en vez de crearlo de nuevo, o usa un correo distinto.'
            : 'Ese correo ya está registrado con otro cliente. Cambia el correo e intenta de nuevo.';
      } else {
        _intentosCorreoDup = 0;
        _error = mensajeBackend ?? 'No se pudo crear el cliente.';
      }
    });
  }

  Future<void> _crearCliente() async {
    final cedula = _cedula.text.trim();
    if (_nombre.text.trim().isEmpty || _email.text.trim().isEmpty || _movil.text.trim().isEmpty) {
      setState(() => _error = 'Completa nombre, correo y celular del nuevo cliente.');
      return;
    }
    setState(() {
      _buscando = true;
      _error = '';
    });
    final email = _email.text.trim().toLowerCase();
    try {
      final r = await dio.post('$urlBase/crear_suscriptor',
          data: {
            'nombreCompleto': _nombre.text.trim(),
            'email': email,
            'password': cedula,
            'movil': _movil.text.trim(),
            'ciudad': _ciudad.text.trim(),
            'cedula': cedula,
          },
          options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true) {
        _intentosCorreoDup = 0;
        _seleccionarCliente(Cliente(
          id: ent(asMap(data['data'])['id'] ?? data['id']),
          cedula: cedula,
          nombreCompleto: _nombre.text.trim(),
          email: email,
          movil: _movil.text.trim(),
          ciudad: _ciudad.text.trim(),
          esNuevo: true,
        ));
      } else {
        _manejarErrorCrearCliente(strN(data['message']));
      }
    } catch (e) {
      /* El backend responde 409/400 con mensaje cuando el correo ya está en uso. */
      final msg = mensajeBackend(e);
      if (msg != null) {
        _manejarErrorCrearCliente(msg);
      } else {
        setState(() => _error = 'Error de conexión al crear el cliente.');
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  void _seleccionarCliente(Cliente c) {
    setState(() {
      _cliente = c;
      _noEncontrado = false;
    });
    _verificarPendiente();
    _cargarPrecios();
  }

  void _cambiarCliente() {
    for (final c in [_cedula, _nombre, _email, _movil, _ciudad]) {
      c.clear();
    }
    setState(() {
      _cliente = null;
      _noEncontrado = false;
      _fuenteDatos = null;
      _compraPendiente = null;
      _precios = [];
      _error = '';
    });
  }

  Future<void> _verificarPendiente() async {
    final c = _cliente;
    if (c == null) return;
    setState(() {
      _verificandoPendiente = true;
      _compraPendiente = null;
    });
    try {
      final r = await dio.get('$urlBase/compra_pendiente',
          queryParameters: {'cedula': c.cedula, 'codigoEvento': ev.codigoEvento}, options: hdr(apiHdr()));
      final data = asMap(r.data);
      if (data['success'] == true && truthy(data['pendiente'])) {
        final d = asMap(data['data']);
        _compraPendiente =
            _CompraPendiente(ent(d['id']), str(d['estado_pago']), str(d['total_pago'], '0'), str(d['nombreConcierto']));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _verificandoPendiente = false);
    }
  }

  /* Mismo motivo que en Vender: filtrado por usuario_evento con el JWT. */
  Future<void> _cargarPrecios() async {
    setState(() => _cargandoPrecios = true);
    try {
      final r = await dio.get('$urlMsLogin/ListaPreciosLocaDispo/${ev.codigoEvento}', options: hdr(staffAuthHeaders()));
      final data = asMap(r.data);
      if (data['success'] == true && mounted) {
        setState(() => _precios = asMapList(data['data']).map(PrecioLocalidad.fromJson).toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoPrecios = false);
    }
  }

  Future<void> _seleccionarLocalidad(PrecioLocalidad p) async {
    final c = _cliente;
    if (c == null) return;
    await ir(LocalidadPage(evento: ev, precio: p, cliente: c));
    /* Al volver (sin vender) se refresca disponibilidad y pendientes. */
    if (mounted && _cliente != null) {
      _verificarPendiente();
      _cargarPrecios();
    }
  }

  List<PrecioLocalidad> get _filasLocalidad => [
        for (final p in _precios) ...[p, for (final m in p.modalidades) p.conModalidad(m)],
      ];

  @override
  Widget build(BuildContext context) {
    final c = _cliente;
    return Scaffold(
      appBar: AppBar(title: Text(ev.nombreConcierto.isEmpty ? 'Vender entrada' : ev.nombreConcierto)),
      body: Contenido(children: [
        if (ev.mapaConcierto.isNotEmpty || _imagenBloquesMostrar != null)
          Row(children: [
            if (ev.mapaConcierto.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => verImagen(context, ev.mapaConcierto, 'Mapa del lugar'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Ver mapa'),
                ),
              ),
            if (ev.mapaConcierto.isNotEmpty && _imagenBloquesMostrar != null) const SizedBox(width: 10),
            if (_imagenBloquesMostrar != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => verImagen(context, _imagenBloquesMostrar!, 'División por bloques'),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('Ver bloques'),
                ),
              ),
          ]),

        /* ── Paso 1: cliente ── */
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloTarjeta('Cliente'),
            if (c == null) ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cedula,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _buscarCliente(),
                    decoration: const InputDecoration(hintText: 'Cédula del cliente'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _buscando ? null : _buscarCliente,
                    child: _buscando ? const MiniSpinner() : const Icon(Icons.search),
                  ),
                ),
              ]),
              if (_noEncontrado) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.person_add_alt_1, size: 18, color: C.naranja),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _fuenteDatos != null
                          ? 'No está registrado'
                          : 'No se encontró en ningún registro — completa sus datos para crearlo',
                      style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre completo')),
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => _intentosCorreoDup = 0,
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: _movil,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Celular')),
                const SizedBox(height: 10),
                TextField(controller: _ciudad, decoration: const InputDecoration(labelText: 'Ciudad')),
                const SizedBox(height: 12),
                BotonAccion('Crear cliente', primario: true, cargando: _buscando, onPressed: _crearCliente),
              ],
            ] else
              Row(children: [
                const Icon(Icons.check_circle_outline, color: C.verde, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.nombreOCedula,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: colorTexto(context))),
                    Text('${c.cedula} · ${c.email.isEmpty ? 'sin correo' : c.email}',
                        style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                    if (c.esNuevo) ...[
                      const SizedBox(height: 4),
                      const Insignia('Cliente nuevo', fondo: Color(0xFFD4F1DD), color: Color(0xFF155724)),
                    ],
                  ]),
                ),
                TextButton(onPressed: _cambiarCliente, child: const Text('Cambiar')),
              ]),
            if (_error.isNotEmpty) TextoError(_error),
          ]),
        ),

        /* ── Compra pendiente: bloquea el paso 2 hasta que se resuelva ── */
        if (c != null && _verificandoPendiente) const Tarjeta(child: Center(child: CircularProgressIndicator())),
        if (c != null && !_verificandoPendiente && _compraPendiente != null)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('Compra pendiente', icono: Icons.error_outline),
              Aviso(
                'Este cliente ya tiene una compra sin resolver (${_compraPendiente!.estadoPago}) de '
                '"${_compraPendiente!.nombreConcierto}" por \$${f2(dbl(_compraPendiente!.totalPago))}. '
                'Resuélvela antes de generar una nueva.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  await ir(DetalleCompraPage(id: _compraPendiente!.id));
                  if (mounted) _verificarPendiente();
                },
                child: const Text('Ver compra pendiente'),
              ),
            ]),
          ),

        /* ── Paso 2: localidades ── */
        if (c != null && !_verificandoPendiente && _compraPendiente == null)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('Selecciona la localidad', icono: Icons.groups_outlined),
              if (_cargandoPrecios) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
              if (!_cargandoPrecios && _precios.isEmpty)
                Text('No hay localidades disponibles', style: TextStyle(color: colorTenue(context))),
              if (!_cargandoPrecios)
                for (final p in _filasLocalidad)
                  InkWell(
                    onTap: () => _seleccionarLocalidad(p),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: esOscuro(context) ? const Color(0xFF2A3050) : C.borde),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              '${limpiarLocalidad(p.localidad)}'
                              '${p.modalidadNombre != null ? ' · ${p.modalidadNombre}' : (p.modalidades.isNotEmpty ? ' · Individual' : '')}',
                              style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context)),
                            ),
                            Text('${p.cantidadDisponible} disponibles',
                                style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                          ]),
                        ),
                        Text('\$${f2(dbl(p.precioNormal))}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colorAcento(context))),
                        const Icon(Icons.chevron_right),
                      ]),
                    ),
                  ),
            ]),
          ),
      ]),
    );
  }
}
