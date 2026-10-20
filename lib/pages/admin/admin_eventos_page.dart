import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/nav.dart';
import '../../services/admin_eventos.dart';
import '../../services/staff_auth.dart';
import '../../widgets/comunes.dart';
import '../comisiones_page.dart';
import '../login_page.dart';
import 'admin_evento_detalle_page.dart';
import 'admin_evento_form_page.dart';
import 'admin_metodos_pago_page.dart';
import 'admin_reporte_usuarios_page.dart';

class AdminEventosPage extends StatefulWidget {
  const AdminEventosPage({super.key});

  @override
  State<AdminEventosPage> createState() => _AdminEventosPageState();
}

class _AdminEventosPageState extends State<AdminEventosPage> {
  List<EventoAdmin> _eventos = [];
  bool _cargando = true;
  String _error = '';
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final lista = await listarEventosAdmin();
      if (mounted) setState(() => _eventos = lista);
    } on SesionExpiradaError {
      logoutStaff();
      irComoRaiz(const LoginPage());
      return;
    } catch (_) {
      if (mounted) setState(() => _error = 'Error al conectar con el servidor.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados =
        _eventos.where((ev) => ev.nombreConcierto.toLowerCase().contains(_busqueda.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const TituloConLogo('Admin · Eventos'),
        actions: [
          IconButton(
              tooltip: 'Comisiones', icon: const Icon(Icons.groups_outlined), onPressed: () => ir(const ComisionesPage())),
          IconButton(
              tooltip: 'Métodos de pago',
              icon: const Icon(Icons.credit_card),
              onPressed: () => ir(const AdminMetodosPagoPage())),
          IconButton(
              tooltip: 'Reporte por usuario',
              icon: const Icon(Icons.bar_chart),
              onPressed: () => ir(const AdminReporteUsuariosPage())),
          IconButton(
            tooltip: 'Nuevo evento',
            icon: const Icon(Icons.add),
            onPressed: () async {
              await ir(const AdminEventoFormPage());
              _cargar();
            },
          ),
        ],
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
          : Contenido(onRefresh: _cargar, children: [
              if (_error.isNotEmpty) MensajeVacio(_error, error: true),
              if (_error.isEmpty && filtrados.isEmpty) const MensajeVacio('No hay eventos.'),
              for (final ev in filtrados)
                Tarjeta(
                  onTap: () async {
                    await ir(AdminEventoDetallePage(codigoEvento: ev.codigoEvento, evento: ev));
                    _cargar();
                  },
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(ev.nombreConcierto,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: colorTexto(context))),
                          ),
                          insigniaEstadoEvento(ev.estado),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.calendar_month_outlined, size: 15, color: colorTenue(context)),
                          const SizedBox(width: 5),
                          Text('${formatFecha(ev.fechaConcierto)} · ${ev.horaConcierto}',
                              style: TextStyle(fontSize: 13, color: colorTenue(context))),
                        ]),
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.place_outlined, size: 15, color: colorTenue(context)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text('${ev.lugarConcierto}, ${ev.cuidadConcert}',
                                style: TextStyle(fontSize: 13, color: colorTenue(context))),
                          ),
                        ]),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
            ]),
    );
  }
}
