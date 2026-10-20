import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../services/reportes.dart';
import '../../widgets/comunes.dart';

/* Reporte por usuario para admin -- todos los operadores del rango. */
class AdminReporteUsuariosPage extends StatefulWidget {
  const AdminReporteUsuariosPage({super.key});

  @override
  State<AdminReporteUsuariosPage> createState() => _AdminReporteUsuariosPageState();
}

class _AdminReporteUsuariosPageState extends State<AdminReporteUsuariosPage> {
  String _desde = inicioMesStr();
  String _hasta = hoyStr();
  bool _cargando = false;
  String _error = '';
  bool _buscado = false;
  List<UsuarioAgg> _operadores = [];
  UsuarioAgg? _autogestion;
  int? _expandido;

  Future<void> _generar([String? d, String? h]) async {
    setState(() {
      _cargando = true;
      _error = '';
      _buscado = false;
    });
    try {
      final data = await obtenerReporteVentas(d ?? _desde, h ?? _hasta);
      setState(() {
        if (!data.success) {
          _error = data.message ?? 'No se pudo generar el reporte.';
          _operadores = [];
          _autogestion = null;
        } else {
          _operadores = [...data.operadores]..sort((a, b) => b.pagado.monto.compareTo(a.pagado.monto));
          _autogestion = data.autogestion;
          _buscado = true;
        }
      });
    } catch (_) {
      setState(() {
        _error = 'Error de conexión al generar el reporte.';
        _operadores = [];
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _aplicarRango(String d, String h) {
    setState(() {
      _desde = d;
      _hasta = h;
    });
    _generar(d, h);
  }

  Widget _fila(String nombre, String sub, String monto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
              Text(sub, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
            ]),
          ),
          Text(monto, style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context))),
        ]),
      );

  Widget _kpi(IconData icono, String valor, String etiqueta) => Expanded(
        child: Column(children: [
          Icon(icono, color: colorAcento(context)),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colorTexto(context))),
          Text(etiqueta, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: colorTenue(context))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final boletos = _operadores.fold<int>(0, (a, o) => a + o.pagado.boletos);
    final monto = _operadores.fold<double>(0, (a, o) => a + o.pagado.monto);
    final compras = _operadores.fold<int>(0, (a, o) => a + o.pagado.compras);
    return Scaffold(
      appBar: AppBar(title: const Text('Reporte por usuario')),
      body: Contenido(children: [
        TarjetaRangoFechas(
          desde: _desde,
          hasta: _hasta,
          deshabilitado: _cargando,
          rangos: [rangoHoy, rangoAyer, rango7Dias, rangoMes],
          onCambiarDesdeHasta: (d, h) => setState(() {
            _desde = d;
            _hasta = h;
          }),
          onRangoRapido: _aplicarRango,
          pie: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            BotonAccion('Generar reporte', primario: true, cargando: _cargando, onPressed: () => _generar()),
            if (_error.isNotEmpty) TextoError(_error),
          ]),
        ),
        if (_buscado && _operadores.isEmpty && _autogestion == null)
          const MensajeVacio('No hay ventas registradas en este rango.'),
        if (_operadores.isNotEmpty)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TituloTarjeta('Total combinado (${_operadores.length} operadores)', icono: Icons.groups_outlined),
              Row(children: [
                _kpi(Icons.confirmation_number_outlined, '$boletos', 'Boletos pagados'),
                _kpi(Icons.payments_outlined, '\$${f2(monto)}', 'Recaudado'),
                _kpi(Icons.receipt_long_outlined, '$compras', 'Compras'),
              ]),
            ]),
          ),
        for (final (i, op) in _operadores.indexed)
          Tarjeta(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                onTap: () => setState(() => _expandido = _expandido == i ? null : i),
                title: Text(op.nombre.isEmpty ? 'Sin nombre' : op.nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(op.perfil ?? '—'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('\$${f2(op.pagado.monto)}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context))),
                    Text('${op.pagado.boletos} boletos', style: TextStyle(fontSize: 12, color: colorTenue(context))),
                  ]),
                  Icon(_expandido == i ? Icons.expand_less : Icons.expand_more),
                ]),
              ),
              if (_expandido == i)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (op.pendiente.compras > 0 || op.comprobar.compras > 0)
                      Aviso(
                        'Además tiene ${op.pendiente.compras + op.comprobar.compras} compra(s) pendiente(s)/por comprobar '
                        'por \$${f2(op.pendiente.monto + op.comprobar.monto)} (no incluidas arriba).',
                      ),
                    if (op.eventos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Por evento', style: TextStyle(fontWeight: FontWeight.w800)),
                      for (final ev in op.eventos)
                        _fila(ev.nombre, '${ev.compras} compras · ${ev.boletos} boletos', '\$${f2(ev.monto)}'),
                    ],
                    if (op.formasPago.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Por método de pago', style: TextStyle(fontWeight: FontWeight.w800)),
                      for (final fp in op.formasPago)
                        _fila(fp.nombre, '${fp.compras} compras · ${fp.boletos} boletos', '\$${f2(fp.monto)}'),
                    ],
                  ]),
                ),
            ]),
          ),
        if (_autogestion != null)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('Autogestión (clientes que compraron solos)'),
              _fila('Pagado', '${_autogestion!.pagado.compras} compras · ${_autogestion!.pagado.boletos} boletos',
                  '\$${f2(_autogestion!.pagado.monto)}'),
            ]),
          ),
      ]),
    );
  }
}
