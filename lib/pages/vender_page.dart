import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import '../services/metodos_pago.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import 'login_page.dart';
import 'venta_evento_page.dart';

class VenderPage extends StatefulWidget {
  const VenderPage({super.key});

  @override
  State<VenderPage> createState() => _VenderPageState();
}

class _VenderPageState extends State<VenderPage> {
  List<EventoVenta> _eventos = [];
  bool _cargando = true;
  String _error = '';
  String _busqueda = '';

  /* "Ver precios" desplegable por evento. */
  final Set<int> _expandido = {};
  final Map<int, List<PrecioLocalidad>> _precios = {};
  final Set<int> _cargandoPrecios = {};
  /* "Sumar comisiones": null = no pedido, [] en curso se marca aparte. */
  final Map<int, List<MetodoPagoActivo>> _metodos = {};
  final Set<int> _cargandoMetodos = {};

  @override
  void initState() {
    super.initState();
    _cargarEventos();
  }

  Future<void> _cargarEventos() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      /* Con el JWT del vendedor: el backend filtra por lo que ese usuario
         tiene asignado (usuario_evento), salvo admin/super_admin. */
      final r = await dio.get('$urlMsLogin/listareventos/ACTIVO/', options: hdr(staffAuthHeaders()));
      final data = asMap(r.data);
      if (data['success'] == true) {
        final hoy = DateTime.now();
        final futuros = asMapList(data['data']).map(EventoVenta.fromJson).where((ev) {
          final fin = DateTime.tryParse('${ev.fechaConcierto}T23:59:59');
          return fin == null || fin.isAfter(hoy);
        }).toList();
        setState(() => _eventos = futuros);
      } else {
        setState(() => _error = 'No se pudieron cargar los eventos');
      }
    } catch (e) {
      /* 401 = JWT vencido (dura 1h): a loguearse otra vez. */
      if (statusDe(e) == 401) {
        logoutStaff();
        irComoRaiz(const LoginPage());
        return;
      }
      if (mounted) setState(() => _error = 'Error al conectar con el servidor');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _alternarPrecios(EventoVenta ev) async {
    setState(() {
      if (!_expandido.remove(ev.id)) _expandido.add(ev.id);
    });
    if (_precios.containsKey(ev.id)) return;
    setState(() => _cargandoPrecios.add(ev.id));
    try {
      final r = await dio.get('$urlMsLogin/ListaPreciosLocaDispo/${ev.codigoEvento}', options: hdr(staffAuthHeaders()));
      final data = asMap(r.data);
      if (data['success'] == true) {
        _precios[ev.id] = asMapList(data['data']).map(PrecioLocalidad.fromJson).toList();
      }
    } catch (_) {
      /* silencioso */
    } finally {
      if (mounted) setState(() => _cargandoPrecios.remove(ev.id));
    }
  }

  Future<void> _sumarComisiones(EventoVenta ev) async {
    setState(() => _cargandoMetodos.add(ev.id));
    final activos = await obtenerMetodosPagoActivos(ev.codigoEvento);
    if (!mounted) return;
    setState(() {
      _metodos[ev.id] = activos;
      _cargandoMetodos.remove(ev.id);
    });
  }

  Widget _tarjetaEvento(EventoVenta ev) {
    final abierto = _expandido.contains(ev.id);
    final precios = _precios[ev.id];
    final metodos = _metodos[ev.id];
    final ivaRate = ivaRateDe(ev.iva);
    return Tarjeta(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ev.imagenConcierto.isNotEmpty)
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(ev.imagenConcierto,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(color: C.borde, child: const Icon(Icons.image_not_supported))),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(ev.nombreConcierto,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: colorTexto(context))),
            const SizedBox(height: 8),
            _detalle(Icons.calendar_month_outlined, '${formatFecha(ev.fechaConcierto)} · ${ev.horaConcierto}'),
            _detalle(Icons.place_outlined, '${ev.lugarConcierto}, ${ev.cuidadConcert}'),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _alternarPrecios(ev),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Row(children: [
                const Text('Ver precios'),
                const Spacer(),
                Icon(abierto ? Icons.expand_less : Icons.expand_more),
              ]),
            ),
            if (abierto) _panelPrecios(ev, precios, metodos, ivaRate),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => ir(VentaEventoPage(evento: ev)),
              icon: const Icon(Icons.sell),
              label: const Text('Vender entrada'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _detalle(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icono, size: 16, color: colorTenue(context)),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, style: TextStyle(color: colorTenue(context), fontSize: 13.5))),
        ]),
      );

  Widget _panelPrecios(EventoVenta ev, List<PrecioLocalidad>? precios, List<MetodoPagoActivo>? metodos, double ivaRate) {
    if (_cargandoPrecios.contains(ev.id)) {
      return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
    }
    if (precios == null || precios.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('No hay localidades disponibles.', style: TextStyle(color: colorTenue(context))),
      );
    }
    final cargandoMet = _cargandoMetodos.contains(ev.id);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esOscuro(context) ? const Color(0xFF1A2035) : const Color(0xFFF4F6FB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final p in precios) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(limpiarLocalidad(p.localidad),
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
              ),
              Text('\$${f2(dbl(p.precioNormal))}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context))),
            ]),
          ),
          if (cargandoMet) const LinearProgressIndicator(),
          /* Se listan todos los métodos (mismo criterio que Pago). */
          if (metodos != null)
            for (final m in metodosConfigurables)
              Builder(builder: (_) {
                MetodoPagoActivo? cfg;
                for (final a in metodos) {
                  if (a.metodo == m.key) cfg = a;
                }
                final pct = cfg?.comisionPorcentaje ?? m.pctDefault;
                final t = calcularTotalConComision(
                    dbl(p.precioNormal), 1, dbl(p.comisionBoleto), ivaRate, pct, cfg?.aplicaComisionBoleto ?? true);
                return Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 2),
                  child: Row(children: [
                    Expanded(child: Text(m.label, style: TextStyle(fontSize: 12.5, color: colorTenue(context)))),
                    Text('\$${f2(t.total)}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colorTexto(context))),
                  ]),
                );
              }),
          const Divider(height: 10),
        ],
        if (metodos == null && !cargandoMet)
          OutlinedButton.icon(
            onPressed: () => _sumarComisiones(ev),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Sumar comisiones'),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados =
        _eventos.where((ev) => ev.nombreConcierto.toLowerCase().contains(_busqueda.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const TituloConLogo('Vender'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SearchBar(
              hintText: 'Buscar evento…',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
        ),
      ),
      body: _cargando
          ? const Cargando(texto: 'Cargando eventos…')
          : Contenido(
              onRefresh: _cargarEventos,
              children: [
                if (_error.isNotEmpty) MensajeVacio(_error, error: true),
                if (_error.isEmpty && filtrados.isEmpty) const MensajeVacio('No hay eventos activos'),
                if (_error.isEmpty) ...filtrados.map(_tarjetaEvento),
              ],
            ),
    );
  }
}
