import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/json.dart';
import '../../core/nav.dart';
import '../../core/tema.dart';
import '../../services/admin_eventos.dart';
import '../../services/documentos.dart';
import '../../widgets/comunes.dart';
import '../detalle_compra_page.dart';
import 'admin_descuentos_page.dart';
import 'admin_evento_form_page.dart';
import 'admin_localidad_asientos_page.dart';
import 'admin_sincronizar_fisicos_page.dart';

/* eventos.iva guarda el multiplicador legado (1.15 = 15%); se tolera también
   un % entero (15) o ya-decimal (0.15). */
double _normalizarIva(String? raw) {
  final n = double.tryParse(raw ?? '');
  if (n == null || n <= 0) return 0;
  if (n >= 1 && n < 2) return n - 1;
  if (n >= 2) return n / 100;
  return n;
}

class AdminEventoDetallePage extends StatefulWidget {
  final String codigoEvento;
  final EventoAdmin? evento;
  const AdminEventoDetallePage({super.key, required this.codigoEvento, this.evento});

  @override
  State<AdminEventoDetallePage> createState() => _AdminEventoDetallePageState();
}

class _AdminEventoDetallePageState extends State<AdminEventoDetallePage> {
  late EventoAdmin? _evento = widget.evento;
  late bool _cargandoEvento = widget.evento == null;
  List<LocalidadAdmin> _localidades = [];
  bool _cargandoLocalidades = true;
  String? _procesando;

  int? _editandoId;
  final Map<String, TextEditingController> _draft = {};
  bool _draftCortesia = false;

  bool _cargandoResumen = false;
  FacturaFinalEvento? _resumen;
  String _errorResumen = '';
  bool _descargandoPdf = false;

  bool _cargandoDiscrepancias = false;
  DiscrepanciasEvento? _discrepancias;
  bool _descargandoExcel = false;

  @override
  void initState() {
    super.initState();
    if (_evento == null) _recargarEvento();
    _cargarLocalidades();
  }

  @override
  void dispose() {
    for (final c in _draft.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _recargarEvento() async {
    setState(() => _cargandoEvento = true);
    try {
      final lista = await listarEventosAdmin();
      _evento = lista.where((e) => e.codigoEvento == widget.codigoEvento).firstOrNull ?? _evento;
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoEvento = false);
    }
  }

  Future<void> _cargarLocalidades() async {
    setState(() => _cargandoLocalidades = true);
    final lista = await listarLocalidadesAdmin(widget.codigoEvento);
    if (mounted) {
      setState(() {
        _localidades = lista;
        _cargandoLocalidades = false;
      });
    }
  }

  TextEditingController _c(String k) => _draft.putIfAbsent(k, TextEditingController.new);

  void _iniciarEdicion(LocalidadAdmin loc) {
    setState(() {
      _editandoId = loc.id;
      _c('precio_normal').text = loc.precioNormal;
      _c('precio_tarjeta').text = loc.precioTarjeta;
      _c('precio_discapacidad').text = loc.precioDiscapacidad;
      _c('precio_descuento').text = loc.precioDescuento;
      _c('comision_boleto').text = loc.comisionBoleto;
      _draftCortesia = loc.habilitarCortesia == '1';
    });
  }

  Future<void> _guardarEdicion(LocalidadAdmin loc) async {
    setState(() => _procesando = 'editar-${loc.id}');
    try {
      final r = await actualizarPrecioLocalidadAdmin({
        'id_precios': loc.id,
        'precio_normal': _c('precio_normal').text,
        'precio_discapacidad': _c('precio_discapacidad').text,
        'precio_tarjeta': _c('precio_tarjeta').text,
        'precio_descuento': _c('precio_descuento').text,
        'habilitar_cortesia': _draftCortesia ? '1' : '0',
        'comision_boleto': _c('comision_boleto').text,
        'mensaje_promocion': loc.mensajePromocion,
      });
      if (r.success) {
        toast('Localidad actualizada.');
        setState(() => _editandoId = null);
        await _cargarLocalidades();
      } else {
        toast(r.message ?? 'No se pudo actualizar la localidad.');
      }
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  Future<void> _eliminarLocalidad(LocalidadAdmin loc) async {
    final si = await confirmar(
      context,
      titulo: '¿Eliminar esta localidad?',
      mensaje: 'Se eliminará "${loc.localidad}" de este evento. Si ya hay boletos vendidos con esta localidad, no se '
          'tocan, pero quedarán sin precio asociado. Esta acción no se puede deshacer.',
      si: 'Sí, eliminar',
      peligro: true,
    );
    if (!si) return;
    setState(() => _procesando = 'eliminar-${loc.id}');
    try {
      final r = await eliminarLocalidadAdmin(widget.codigoEvento, loc.localidad);
      if (r.success) {
        toast('Localidad eliminada.');
        await _cargarLocalidades();
      } else {
        toast(r.message ?? 'No se pudo eliminar la localidad.');
      }
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  Future<void> _cambiarEstado() async {
    final i = await elegirOpcion(context, titulo: 'Cambiar estado del evento', opciones: estadosCambiables);
    if (i == null) return;
    final estado = estadosCambiables[i];
    setState(() => _procesando = 'estado');
    try {
      final r = await actualizarEstadoEvento(widget.codigoEvento, estado);
      if (r.success) {
        toast('Estado cambiado a $estado.');
        setState(() => _evento = _evento?.conEstado(estado));
      } else {
        toast(r.message ?? 'No se pudo cambiar el estado.');
      }
    } finally {
      if (mounted) setState(() => _procesando = null);
    }
  }

  Future<void> _generarResumen() async {
    setState(() {
      _cargandoResumen = true;
      _errorResumen = '';
      _resumen = null;
    });
    try {
      final data = await obtenerFacturaFinalEvento(widget.codigoEvento);
      if (data.porFormaPago.isEmpty && data.porLocalidad.isEmpty && data.porOperador.isEmpty) {
        setState(() => _errorResumen = 'Todavía no hay ventas pagadas registradas para este evento.');
        return;
      }
      setState(() => _resumen = data);
    } catch (_) {
      setState(() => _errorResumen = 'Error de conexión al generar el resumen.');
    } finally {
      if (mounted) setState(() => _cargandoResumen = false);
    }
  }

  Future<void> _generarDiscrepancias() async {
    setState(() {
      _cargandoDiscrepancias = true;
      _discrepancias = null;
    });
    final data = await obtenerDiscrepanciasEvento(widget.codigoEvento);
    if (mounted) {
      setState(() {
        _discrepancias = data;
        _cargandoDiscrepancias = false;
      });
    }
  }

  Future<void> _descargarExcel() async {
    setState(() => _descargandoExcel = true);
    try {
      final bytes = await descargarReporteEventoExcel(widget.codigoEvento);
      if (bytes == null) {
        toast('No se pudo descargar el reporte. Intenta de nuevo.');
        return;
      }
      final error = await compartirArchivo(bytes, 'reporte_registros_${widget.codigoEvento}.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (error != null) toast(error);
    } finally {
      if (mounted) setState(() => _descargandoExcel = false);
    }
  }

  String _filaResumenTexto(Map<String, dynamic> fila) {
    final cedula = str(fila['cedula']);
    final partes = fila.entries
        .where((e) => e.key != 'cedula' && e.key != 'motivos')
        .map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}');
    return [if (cedula.isNotEmpty) cedula, ...partes].join(' · ');
  }

  Widget _campoNumero(String clave, String etiqueta) => TextField(
        controller: _c(clave),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etiqueta),
      );

  Widget _localidad(LocalidadAdmin loc) {
    final abierto = _editandoId == loc.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border.all(color: C.borde), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          onTap: () => abierto ? setState(() => _editandoId = null) : _iniciarEdicion(loc),
          title: Text(loc.localidad, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('\$${f2(dbl(loc.precioNormal))}',
              style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context))),
          trailing: Icon(abierto ? Icons.expand_less : Icons.expand_more),
        ),
        if (loc.esNumerada)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: OutlinedButton.icon(
              onPressed: () => ir(AdminLocalidadAsientosPage(
                idLocalidad: loc.idLocalidad!,
                localidadNombre: loc.localidad,
                tipoLocalidad: loc.tipoLocalidad ?? 'fila',
              )),
              icon: const Icon(Icons.grid_view),
              label: const Text('Ver / editar asientos'),
            ),
          ),
        if (abierto)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: _campoNumero('precio_normal', 'Precio normal')),
                const SizedBox(width: 8),
                Expanded(child: _campoNumero('precio_tarjeta', 'Precio tarjeta')),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _campoNumero('precio_discapacidad', 'Precio discapacidad')),
                const SizedBox(width: 8),
                Expanded(child: _campoNumero('precio_descuento', 'Precio descuento')),
              ]),
              const SizedBox(height: 10),
              _campoNumero('comision_boleto', 'Comisión por boleto'),
              CheckboxListTile(
                value: _draftCortesia,
                onChanged: (v) => setState(() => _draftCortesia = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Habilitar cortesías'),
              ),
              Row(children: [
                Expanded(
                  child: BotonAccion('Guardar',
                      icono: Icons.save_outlined,
                      primario: true,
                      cargando: _procesando == 'editar-${loc.id}',
                      onPressed: () => _guardarEdicion(loc)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BotonAccion('Eliminar',
                      icono: Icons.delete_outline,
                      color: C.rojo,
                      cargando: _procesando == 'eliminar-${loc.id}',
                      onPressed: () => _eliminarLocalidad(loc)),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }

  Widget _fila(String nombre, String sub, String monto, {Widget? extra}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
              Text(sub, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(monto, style: TextStyle(fontWeight: FontWeight.w800, color: colorAcento(context))),
            ?extra,
          ]),
        ]),
      );

  Future<void> _verRegistros(FacturaLocalidadItem f) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => ListView(controller: scroll, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('${f.localidad} · ${f.tarifa}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final r in f.registrosOrigen)
              ListTile(
                title: Text('Compra #${r.idRegistraCompra}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${r.cedula.isEmpty ? '—' : r.cedula} · ${r.cantidad} boleto${r.cantidad == 1 ? '' : 's'}'),
                trailing: Text('\$${f2(r.subtotalItem)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: () {
                  Navigator.pop(ctx);
                  ir(DetalleCompraPage(id: r.idRegistraCompra));
                },
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ev = _evento;
    final ivaMult = _normalizarIva(ev?.iva);
    final ivaPercent = (ivaMult * 100).round();
    final filas = _resumen?.porLocalidad ?? [];
    final totalBoletos = filas.fold<int>(0, (a, f) => a + f.cantidad);
    final subtotal = filas.fold<double>(0, (a, f) => a + f.subtotalSinIva);
    final iva = ivaMult > 0 ? subtotal * ivaMult : 0.0;
    final totalFinal = subtotal + iva;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del evento')),
      body: _cargandoEvento
          ? const Cargando()
          : ev == null
              ? const MensajeVacio('No se encontró el evento.', error: true)
              : Contenido(children: [
                  Tarjeta(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Text(ev.nombreConcierto,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colorTexto(context))),
                        ),
                        insigniaEstadoEvento(ev.estado),
                      ]),
                      const SizedBox(height: 8),
                      FilaDato('Fecha', '${formatFecha(ev.fechaConcierto)} · ${ev.horaConcierto}'),
                      FilaDato('Lugar', '${ev.lugarConcierto}, ${ev.cuidadConcert}'),
                      FilaDato('Código', ev.codigoEvento),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final cambio = await ir<bool>(AdminEventoFormPage(evento: ev));
                            if (cambio == true) _recargarEvento();
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _procesando == 'estado' ? null : _cambiarEstado,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Cambiar estado'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _descargandoExcel ? null : _descargarExcel,
                          icon: _descargandoExcel ? const MiniSpinner(color: C.azul) : const Icon(Icons.description_outlined),
                          label: const Text('Registros (Excel)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => ir(AdminDescuentosPage(codigoEvento: ev.codigoEvento)),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('Descuentos'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => ir(AdminSincronizarFisicosPage(codigoEvento: ev.codigoEvento)),
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('Sincronizar físicos'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'El Excel de registros incluye las compras pagadas de este evento (mismo reporte que "Descargar '
                        'registros" en la página admin).',
                        style: TextStyle(fontSize: 12, color: colorTenue(context)),
                      ),
                    ]),
                  ),
                  Tarjeta(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TituloTarjeta('Localidades (${_localidades.length})'),
                      if (_cargandoLocalidades) const Center(child: CircularProgressIndicator()),
                      if (!_cargandoLocalidades && _localidades.isEmpty)
                        Text('Este evento todavía no tiene localidades.', style: TextStyle(color: colorTenue(context))),
                      if (!_cargandoLocalidades) ..._localidades.map(_localidad),
                    ]),
                  ),
                  Tarjeta(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const TituloTarjeta('Discrepancias', icono: Icons.error_outline),
                      Text(
                        'Compara boletos comprados, generados y asientos vinculados para detectar compras con problemas. '
                        'Solo informa, no corrige nada automáticamente.',
                        style: TextStyle(color: colorTenue(context), fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      BotonAccion('Analizar discrepancias',
                          icono: Icons.search, cargando: _cargandoDiscrepancias, onPressed: _generarDiscrepancias),
                      if (_discrepancias != null)
                        for (final (titulo, lista) in [
                          ('Boletos comprados vs. generados', _discrepancias!.discrepancias),
                          ('Cantidad generada vs. esperada', _discrepancias!.discrepanciasGeneracion),
                          ('Compras con problemas', _discrepancias!.comprasEvento),
                        ]) ...[
                          const SizedBox(height: 12),
                          Text('$titulo (${lista.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                          if (lista.isEmpty) Text('Sin discrepancias.', style: TextStyle(color: colorTenue(context))),
                          for (final f in lista)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(_filaResumenTexto(f), style: const TextStyle(fontSize: 12.5)),
                            ),
                        ],
                    ]),
                  ),
                  Tarjeta(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Factura de Venta Final',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colorTexto(context))),
                            if (_resumen != null) ...[
                              Text('Evento: ${ev.nombreConcierto}', style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                              Text('IVA aplicado a boletos: $ivaPercent%',
                                  style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                            ],
                          ]),
                        ),
                        if (_resumen != null)
                          FilledButton.icon(
                            onPressed: _descargandoPdf
                                ? null
                                : () async {
                                    setState(() => _descargandoPdf = true);
                                    final error = await compartirFacturaEvento(DatosFacturaEvento(ev.codigoEvento,
                                        ev.nombreConcierto, ivaPercent, filas, totalBoletos, subtotal, iva, totalFinal));
                                    if (error != null) toast(error);
                                    if (mounted) setState(() => _descargandoPdf = false);
                                  },
                            icon: _descargandoPdf ? const MiniSpinner() : const Icon(Icons.download),
                            label: const Text('PDF'),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      if (_resumen == null)
                        BotonAccion('Generar factura final',
                            primario: true, cargando: _cargandoResumen, onPressed: _generarResumen),
                      if (_errorResumen.isNotEmpty) TextoError(_errorResumen),
                      if (_resumen != null) ...[
                        const Text('Detalle del evento', style: TextStyle(fontWeight: FontWeight.w800)),
                        if (filas.isEmpty)
                          Text('No hay boletos pagados todavía para este evento.', style: TextStyle(color: colorTenue(context))),
                        for (final f in filas)
                          _fila(
                            '${f.localidad} · ${f.tarifa}',
                            '${f.cantidad} boletos × \$${f2(f.precioUnitarioBase)}',
                            '\$${f2(f.subtotalSinIva)}',
                            extra: f.registrosOrigen.isEmpty
                                ? null
                                : TextButton.icon(
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                    onPressed: () => _verRegistros(f),
                                    icon: const Icon(Icons.list, size: 16),
                                    label: const Text('Ver registros', style: TextStyle(fontSize: 12)),
                                  ),
                          ),
                        if (filas.isNotEmpty) ...[
                          const Divider(),
                          FilaDato('TOTAL BOLETOS', '$totalBoletos · \$${f2(subtotal)}'),
                          if (iva > 0) FilaDato('IVA ($ivaPercent%)', '\$${f2(iva)}'),
                          FilaDato('TOTAL FINAL', '\$${f2(totalFinal)}', destacado: true),
                        ],
                        if (_resumen!.porFormaPago.isNotEmpty || _resumen!.porOperador.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Por método de pago', style: TextStyle(fontWeight: FontWeight.w800)),
                          for (final fp in _resumen!.porFormaPago)
                            _fila(fp.formaPago, '${fp.cantidad} compras · ${fp.boleto} boletos · IVA \$${f2(fp.iva)}',
                                '\$${f2(fp.total)}'),
                          const SizedBox(height: 12),
                          const Text('Por vendedor', style: TextStyle(fontWeight: FontWeight.w800)),
                          if (_resumen!.porOperador.isEmpty)
                            Text('Sin ventas asignadas a un operador (autogestión / bot).',
                                style: TextStyle(color: colorTenue(context))),
                          for (final op in _resumen!.porOperador)
                            _fila(op.operador, '${op.formaPago} · ${op.cantidad} compras · ${op.boleto} boletos',
                                '\$${f2(op.total)}'),
                        ],
                      ],
                    ]),
                  ),
                  const SizedBox(height: 16),
                ]),
    );
  }
}
