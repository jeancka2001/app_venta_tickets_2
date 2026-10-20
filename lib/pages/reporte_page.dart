import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/nav.dart';
import '../services/reportes.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import 'comisiones_page.dart';

class ReportePage extends StatefulWidget {
  const ReportePage({super.key});

  @override
  State<ReportePage> createState() => _ReportePageState();
}

class _ReportePageState extends State<ReportePage> {
  String _desde = inicioMesStr();
  String _hasta = hoyStr();
  bool _cargando = false;
  String _error = '';
  bool _buscado = false;
  UsuarioAgg? _miReporte;
  /* Comisión de VENDEDOR (jerarquía nivel1/nivel2). null = este usuario no
     tiene rol en esa jerarquía -- se oculta la tarjeta. */
  FilaComision? _comisionPropia;

  Future<void> _generar([String? d, String? h]) async {
    final desde = d ?? _desde;
    final hasta = h ?? _hasta;
    setState(() {
      _cargando = true;
      _error = '';
      _buscado = false;
    });
    try {
      final res = await Future.wait<Object>([obtenerReporteVentas(desde, hasta), obtenerReporteComisiones(desde, hasta)]);
      final data = res[0] as ReporteVentas;
      final comisiones = res[1] as ReporteComisiones;
      final staff = obtenerStaffData();
      setState(() {
        _comisionPropia = comisiones.success && comisiones.data.isNotEmpty ? comisiones.data.first : null;
        if (!data.success) {
          _error = data.message ?? 'No se pudo generar el reporte.';
          _miReporte = null;
        } else {
          _miReporte = data.operadores.where((o) => o.id == staff?.id).firstOrNull;
          _buscado = true;
        }
      });
    } catch (_) {
      setState(() {
        _error = 'Error de conexión al generar el reporte.';
        _miReporte = null;
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

  Widget _kpi(IconData icono, String valor, String etiqueta) => Tarjeta(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Icon(icono, color: colorAcento(context)),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorTexto(context))),
          Text(etiqueta, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: colorTenue(context))),
        ]),
      );

  Widget _fila(String nombre, String sub, String monto, {bool total = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre,
                  style: TextStyle(fontWeight: total ? FontWeight.w800 : FontWeight.w700, color: colorTexto(context))),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
            ]),
          ),
          Text(monto, style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context), fontSize: total ? 17 : 15)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final r = _miReporte;
    final otrosCompras = r == null ? 0 : r.pendiente.compras + r.comprobar.compras + r.expirado.compras;
    final otrosMonto = r == null ? 0.0 : r.pendiente.monto + r.comprobar.monto + r.expirado.monto;
    final cp = _comisionPropia;
    return Scaffold(
      appBar: AppBar(
        title: const TituloConLogo('Mi Reporte'),
        actions: [
          IconButton(
              tooltip: 'Comisiones', icon: const Icon(Icons.groups_outlined), onPressed: () => ir(const ComisionesPage())),
        ],
      ),
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
            BotonAccion('Generar reporte',
                icono: Icons.bar_chart, primario: true, cargando: _cargando, onPressed: () => _generar()),
            if (_error.isNotEmpty) TextoError(_error),
          ]),
        ),
        if (_buscado && r == null) const MensajeVacio('No tienes ventas registradas en este rango de fechas.'),
        if (r != null) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _kpi(Icons.payments_outlined, '\$${f2(r.pagado.monto)}', 'Total vendido'),
              _kpi(Icons.receipt_long_outlined, '${r.pagado.compras}', 'Compras pagadas'),
              _kpi(Icons.confirmation_number_outlined, '${r.pagado.boletos}', 'Boletos'),
              _kpi(Icons.sell_outlined, '\$${f2(r.pagado.comision)}', 'Comisión de boleto'),
            ],
          ),
          if (cp != null)
            Tarjeta(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const TituloTarjeta('Mi comisión de vendedor', icono: Icons.groups_outlined),
                _fila('Directa (mis ventas)', '${pct(cp.comisionPorcentaje)} sobre \$${f2(cp.ventasPropias)}',
                    '\$${f2(cp.comisionDirecta)}'),
                if (cp.nivel2.isNotEmpty)
                  _fila('Por vendedores nivel 2 a mi cargo', '${cp.nivel2.length} vendedor(es)',
                      '\$${f2(cp.comisionNivel1Total)}'),
                const Divider(),
                _fila('Total a cobrar', '', '\$${f2(cp.comisionTotal)}', total: true),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => ir(const ComisionesPage()), child: const Text('Ver detalle')),
                ),
              ]),
            ),
          if (otrosCompras > 0)
            Aviso(
              'Además tienes $otrosCompras compra${otrosCompras > 1 ? 's' : ''} pendiente(s)/por comprobar '
              'por \$${f2(otrosMonto)}, que no suman al total (aún no están pagadas).',
              icono: Icons.schedule,
            ),
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('Por método de pago'),
              if (r.formasPago.isEmpty) Text('Sin datos.', style: TextStyle(color: colorTenue(context))),
              for (final fp in r.formasPago)
                _fila(fp.nombre, '${fp.compras} compras · ${fp.boletos} boletos', '\$${f2(fp.monto)}'),
            ]),
          ),
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const TituloTarjeta('Por evento'),
              if (r.eventos.isEmpty) Text('Sin datos.', style: TextStyle(color: colorTenue(context))),
              for (final ev in r.eventos)
                _fila(ev.nombre, '${ev.compras} compras · ${ev.boletos} boletos', '\$${f2(ev.monto)}'),
            ]),
          ),
        ],
        if (!_buscado && !_cargando && r == null)
          const MensajeVacio('Elige un rango de fechas y toca "Generar reporte".', icono: Icons.insights),
      ]),
    );
  }
}
