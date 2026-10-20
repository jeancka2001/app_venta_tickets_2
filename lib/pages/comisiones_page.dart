import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/nav.dart';
import '../core/tema.dart';
import '../services/reportes.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import 'login_page.dart';

/* "Comisiones de vendedores" -- el backend devuelve solo lo que este usuario
   puede ver: admin recibe el árbol nivel1/nivel2 completo; cualquier otro
   perfil, su propia fila (si es nivel 1, con sus nivel 2 embebidos). */
class ComisionesPage extends StatefulWidget {
  const ComisionesPage({super.key});

  @override
  State<ComisionesPage> createState() => _ComisionesPageState();
}

class _ComisionesPageState extends State<ComisionesPage> {
  final bool _esAdmin = esAdmin(obtenerStaffData()?.perfil);
  String _desde = inicioMesStr();
  String _hasta = hoyStr();
  bool _cargando = false;
  String _error = '';
  bool _buscado = false;
  List<FilaComision> _filas = [];
  final Set<int> _expandido = {};

  @override
  void initState() {
    super.initState();
    _generar();
  }

  Future<void> _generar([String? d, String? h]) async {
    setState(() {
      _cargando = true;
      _error = '';
      _buscado = false;
    });
    final resp = await obtenerReporteComisiones(d ?? _desde, h ?? _hasta);
    if (!mounted) return;
    if (resp.sesionExpirada) {
      logoutStaff();
      irComoRaiz(const LoginPage());
      return;
    }
    setState(() {
      if (!resp.success) {
        _error = resp.message ?? 'No se pudo generar el reporte.';
        _filas = [];
      } else {
        _filas = resp.data;
        _buscado = true;
      }
      _cargando = false;
    });
  }

  void _aplicarRango(String d, String h) {
    setState(() {
      _desde = d;
      _hasta = h;
    });
    _generar(d, h);
  }

  Widget _kpi(String etiqueta, String valor) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: esOscuro(context) ? const Color(0xFF1A2035) : const Color(0xFFF4F6FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiqueta, style: TextStyle(fontSize: 11.5, color: colorTenue(context))),
          const SizedBox(height: 2),
          Text(valor, style: TextStyle(fontWeight: FontWeight.w800, color: colorTexto(context))),
        ]),
      );

  Widget _tarjetaFila(FilaComision fila, bool esRaiz) {
    final abierto = _expandido.contains(fila.id);
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_esAdmin)
                Insignia(esRaiz ? 'Nivel 1' : 'Nivel 2',
                    fondo: esRaiz ? const Color(0xFFE3E5F8) : C.naranjaFondo,
                    color: esRaiz ? C.azul : const Color(0xFFB45309)),
              const SizedBox(height: 4),
              Text(fila.name, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: colorTexto(context))),
              Text(fila.perfil, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: C.verde, borderRadius: BorderRadius.circular(20)),
            child: Text('\$${f2(fila.comisionTotal)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.6,
          children: [
            _kpi('% propio', pct(fila.comisionPorcentaje)),
            _kpi('Ventas propias', '\$${f2(fila.ventasPropias)} (${fila.cantidadVentasPropias})'),
            _kpi('Comisión directa', '\$${f2(fila.comisionDirecta)}'),
            if (fila.nivel2.isNotEmpty) _kpi('Por nivel 2', '\$${f2(fila.comisionNivel1Total)}'),
          ],
        ),
        if (fila.nivel2.isNotEmpty) ...[
          TextButton.icon(
            onPressed: () => setState(() => abierto ? _expandido.remove(fila.id) : _expandido.add(fila.id)),
            icon: Icon(abierto ? Icons.expand_less : Icons.expand_more),
            label: Text('${abierto ? 'Ocultar' : 'Ver'} vendedores nivel 2 (${fila.nivel2.length})'),
          ),
          if (abierto)
            for (final n2 in fila.nivel2)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: C.borde), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n2.name, style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
                  Text('Ventas propias: \$${f2(n2.ventas)} (${n2.cantidadVentas}) · ${pct(n2.comisionPorcentaje)}',
                      style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                  Text('Comisión propia: \$${f2(n2.comisionDirecta)}', style: const TextStyle(fontSize: 12.5)),
                  Text('Te genera (${pct(n2.comisionNivel1Porcentaje)}): \$${f2(n2.comisionGeneradaNivel1)}',
                      style: const TextStyle(fontSize: 12.5, color: C.verde, fontWeight: FontWeight.w700)),
                ]),
              ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raices = _esAdmin ? _filas.where((f) => f.idNivel1 == null).toList() : _filas;
    final totalGeneral = _filas.fold<double>(0, (acc, f) => acc + f.comisionTotal);
    return Scaffold(
      appBar: AppBar(title: const Text('Comisiones')),
      body: Contenido(children: [
        TarjetaRangoFechas(
          desde: _desde,
          hasta: _hasta,
          deshabilitado: _cargando,
          rangos: [rangoHoy, rango7Dias, rangoMes],
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
        if (_buscado && _filas.isEmpty && _error.isEmpty) const MensajeVacio('No hay comisiones registradas en este rango.'),
        if (_filas.isNotEmpty)
          Tarjeta(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TituloTarjeta('Total ${_esAdmin ? '(todos los niveles)' : 'a cobrar'}', icono: Icons.payments_outlined),
              Text('\$${f2(totalGeneral)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: C.verde)),
            ]),
          ),
        for (final f in raices) _tarjetaFila(f, f.idNivel1 == null),
      ]),
    );
  }
}
