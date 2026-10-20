import 'package:flutter/material.dart';

import '../core/nav.dart';
import '../services/app_lock.dart';
import '../services/bloqueo_sesion.dart';
import '../services/staff_auth.dart';
import 'admin/admin_eventos_page.dart';
import 'buscar_cliente_page.dart';
import 'login_page.dart';
import 'mis_ventas_page.dart';
import 'perfil_page.dart';
import 'reporte_page.dart';
import 'vender_page.dart';

/* Pestañas del panel. "Eventos" (admin) solo la ve un perfil admin/super_admin. */
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _Pestana {
  final IconData icono;
  final IconData iconoActivo;
  final String etiqueta;
  final Widget Function() construir;
  const _Pestana(this.icono, this.iconoActivo, this.etiqueta, this.construir);
}

class _DashboardPageState extends State<DashboardPage> {
  late final List<_Pestana> _pestanas;
  late final List<Widget?> _construidas;
  int _indice = 0;
  bool _dialogoConfigAbierto = false;

  @override
  void initState() {
    super.initState();
    final staff = obtenerStaffData();
    _pestanas = [
      _Pestana(Icons.sell_outlined, Icons.sell, 'Vender', () => const VenderPage()),
      _Pestana(Icons.search, Icons.search, 'Buscar', () => const BuscarClientePage()),
      _Pestana(Icons.history, Icons.history, 'Ventas', () => const MisVentasPage()),
      _Pestana(Icons.bar_chart_outlined, Icons.bar_chart, 'Reporte', () => const ReportePage()),
      if (esAdmin(staff?.perfil))
        _Pestana(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'Eventos', () => const AdminEventosPage()),
      _Pestana(Icons.account_circle_outlined, Icons.account_circle, 'Perfil', () => const PerfilPage()),
    ];
    /* Las pestañas se construyen recién la primera vez que se abren. */
    _construidas = List<Widget?>.filled(_pestanas.length, null);
    _construidas[0] = _pestanas[0].construir();

    AppLock.instance.addListener(_revisarConfig);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (staff == null) {
        irComoRaiz(const LoginPage());
        return;
      }
      _revisarConfig();
    });
  }

  @override
  void dispose() {
    AppLock.instance.removeListener(_revisarConfig);
    super.dispose();
  }

  /* Cuadro para elegir cuándo se bloquea la app (con huella) o cuándo se
     cierra la sesión. Aparece tras el primer login y desde Perfil. */
  Future<void> _revisarConfig() async {
    final lock = AppLock.instance;
    if (!mounted || _dialogoConfigAbierto || !lock.configPendiente) return;
    _dialogoConfigAbierto = true;
    final modo = lock.modo;
    final actual = lock.config?.modo == modo ? lock.config!.minutos : minutosPorDefecto(modo);
    final esHuella = modo == ModoBloqueo.huella;
    int? elegido = actual;
    final guardado = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(esHuella ? 'Bloqueo con huella' : 'Cierre de sesión automático'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(esHuella
                  ? '¿Después de cuánto tiempo con la app cerrada o sin usar quieres que se pida tu huella?'
                  : '¿Después de cuánto tiempo con la app cerrada o sin usar quieres que se cierre tu sesión? Luego ingresarás con tu usuario y contraseña.'),
              const SizedBox(height: 8),
              RadioGroup<int?>(
                groupValue: elegido,
                onChanged: (v) => setD(() => elegido = v),
                child: Column(children: [
                  for (final o in opcionesBloqueo)
                    RadioListTile<int?>(
                      value: o.minutos,
                      title: Text(o.etiqueta),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar'))],
        ),
      ),
    );
    _dialogoConfigAbierto = false;
    if (guardado == true) {
      lock.guardarConfig(elegido);
    } else if (lock.config == null || lock.config!.modo != modo) {
      /* Cerrado sin elegir: se queda con el valor marcado. */
      lock.guardarConfig(actual);
    } else {
      lock.cerrarConfig();
    }
  }

  void _seleccionar(int i) {
    setState(() {
      _indice = i;
      _construidas[i] ??= _pestanas[i].construir();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      /* Atrás desde otra pestaña vuelve a "Vender" antes de cerrar la app. */
      canPop: _indice == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _seleccionar(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _indice,
          children: [for (final w in _construidas) w ?? const SizedBox.shrink()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indice,
          onDestinationSelected: _seleccionar,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final p in _pestanas)
              NavigationDestination(icon: Icon(p.icono), selectedIcon: Icon(p.iconoActivo), label: p.etiqueta),
          ],
        ),
      ),
    );
  }
}
