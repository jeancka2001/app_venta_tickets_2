import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../core/tema.dart';
import '../../services/metodos_pago.dart';
import '../../widgets/comunes.dart';

/* Solo consulta/activación: credenciales y webhooks de cada pasarela se
   siguen gestionando desde la web (Ajustes > Métodos de Pago). */
class AdminMetodosPagoPage extends StatefulWidget {
  const AdminMetodosPagoPage({super.key});

  @override
  State<AdminMetodosPagoPage> createState() => _AdminMetodosPagoPageState();
}

class _AdminMetodosPagoPageState extends State<AdminMetodosPagoPage> {
  Map<String, MetodoPagoActivo> _estados = {};
  bool _cargando = true;
  bool _sesionExpirada = false;
  String? _cambiando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resp = await listarMetodosPagoAdmin();
    if (!mounted) return;
    setState(() {
      _estados = {for (final m in resp.data) m.metodo: m};
      _sesionExpirada = resp.sesionExpirada;
      _cargando = false;
    });
  }

  Future<void> _cambiarEstado(String metodo, bool activo) async {
    setState(() => _cambiando = metodo);
    final resp = await toggleMetodoPagoActivo(metodo, activo);
    toast(resp.success
        ? (activo ? '$metodo activado' : '$metodo desactivado')
        : (resp.message ?? 'No se pudo cambiar el estado'));
    if (resp.success) await _cargar();
    if (mounted) setState(() => _cambiando = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const TituloConLogo('Métodos de Pago')),
      body: _sesionExpirada
          ? const Contenido(children: [
              Aviso('Tu sesión expiró. Cierra sesión y vuelve a iniciar sesión para ver esta página.'),
            ])
          : _cargando
              ? const Cargando()
              : Contenido(onRefresh: _cargar, children: [
                  for (final m in metodosConfigurables)
                    Builder(builder: (_) {
                      final estado = _estados[m.key];
                      final activo = estado?.activo ?? false;
                      return Tarjeta(
                        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                        child: Row(children: [
                          Icon(m.categoria == CategoriaMetodo.local ? Icons.payments_outlined : Icons.credit_card,
                              color: colorAcento(context)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(m.label, style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
                              Text(
                                  'Comisión: ${((estado?.comisionPorcentaje ?? m.pctDefault) * 100).toStringAsFixed(2)}%',
                                  style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                            ]),
                          ),
                          Insignia(activo ? 'Activo' : 'Desactivado',
                              fondo: activo ? const Color(0xFFD4F1DD) : const Color(0xFFEDEFF3),
                              color: activo ? const Color(0xFF155724) : C.gris),
                          Switch(
                            value: activo,
                            onChanged: _cambiando == m.key ? null : (v) => _cambiarEstado(m.key, v),
                          ),
                        ]),
                      );
                    }),
                  Text(
                    'Las credenciales y el webhook de cada pasarela se configuran desde la página web (Ajustes → Métodos de Pago).',
                    style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
                  ),
                ]),
    );
  }
}
