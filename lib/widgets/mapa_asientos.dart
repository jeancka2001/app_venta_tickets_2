import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../services/localidad_config.dart';
import '../services/mapa_asientos.dart';

/* Mapa de asientos (filas o mesas) compartido por la venta (Localidad), el
   admin de asientos y "Sincronizar boletos físicos" -- misma estructura que
   el mapa de la app Ionic. Se acerca con pellizco o con los botones −/+. */

const zoomMin = 0.4;
const zoomMax = 3.0;

class _Colores {
  final Color fondo;
  final Color texto;
  final Color borde;
  final double opacidad;
  const _Colores(this.fondo, this.texto, this.borde, [this.opacidad = 1]);
}

const _coloresPorEstilo = {
  EstiloAsiento.disponible: _Colores(Color(0xFFD4F1DD), Color(0xFF155724), C.verde),
  EstiloAsiento.reservado: _Colores(Color(0xFFE3E5F8), Color(0xFF40456F), Color(0xFF8890C9), 0.75),
  EstiloAsiento.ocupado: _Colores(Color(0xFFFDE8E8), C.rojo, C.rojo, 0.65),
  EstiloAsiento.seleccionado: _Colores(Color(0xFFFEF08A), Color(0xFF78350F), C.ambar),
  EstiloAsiento.bloqueado: _Colores(Color(0xFFFDE3C7), Color(0xFF8A4B00), Color(0xFFF0AD4E)),
};

class LeyendaItem {
  final String texto;
  final EstiloAsiento estilo;
  const LeyendaItem(this.texto, this.estilo);
}

class Leyenda extends StatelessWidget {
  final List<LeyendaItem> items;
  const Leyenda(this.items, {super.key});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 4, runSpacing: 4, children: [
        for (final i in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: _coloresPorEstilo[i.estilo]!.fondo,
              border: Border.all(color: _coloresPorEstilo[i.estilo]!.borde),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(i.texto,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _coloresPorEstilo[i.estilo]!.texto)),
          ),
      ]);
}

class MapaAsientos extends StatefulWidget {
  final List<ItemAsiento> items;
  final bool esMesa;
  final Map<String, String> alineacion;
  final Map<String, bool> ordenSillas;
  final EstiloAsiento Function(ItemAsiento) estilo;
  final void Function(ItemAsiento) onTap;
  /* Tocar la etiqueta de una fila o la cabecera de una mesa. */
  final void Function(List<ItemAsiento>)? onTapGrupo;
  final bool Function(ItemAsiento)? deshabilitado;
  /* Disponible pero sin poder elegirse (llegó al máximo). */
  final bool Function(ItemAsiento)? atenuado;
  final bool Function(ItemAsiento)? procesando;
  final double alto;
  final double zoomInicial;

  const MapaAsientos({
    super.key,
    required this.items,
    required this.esMesa,
    required this.alineacion,
    required this.ordenSillas,
    required this.estilo,
    required this.onTap,
    this.onTapGrupo,
    this.deshabilitado,
    this.atenuado,
    this.procesando,
    this.alto = 420,
    this.zoomInicial = 0.8,
  });

  @override
  State<MapaAsientos> createState() => _MapaAsientosState();
}

class _MapaAsientosState extends State<MapaAsientos> {
  late final TransformationController _ctrl;
  late double _zoom;

  @override
  void initState() {
    super.initState();
    _zoom = widget.zoomInicial;
    _ctrl = TransformationController(Matrix4.diagonal3Values(_zoom, _zoom, 1));
    _ctrl.addListener(_alCambiarTransformacion);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_alCambiarTransformacion);
    _ctrl.dispose();
    super.dispose();
  }

  void _alCambiarTransformacion() {
    final z = _ctrl.value.getMaxScaleOnAxis();
    if ((z - _zoom).abs() > 0.005) setState(() => _zoom = z);
  }

  void _cambiarZoom(double delta) {
    final nuevo = (_zoom + delta).clamp(zoomMin, zoomMax);
    final m = _ctrl.value.clone();
    final factor = nuevo / _zoom;
    m.scaleByDouble(factor, factor, 1, 1);
    _ctrl.value = m;
  }

  Widget _asiento(ItemAsiento item, int idx, {bool chico = false}) {
    final estilo = widget.estilo(item);
    final colores = _coloresPorEstilo[estilo]!;
    final deshab = widget.deshabilitado?.call(item) ?? false;
    final aten = widget.atenuado?.call(item) ?? false;
    final cargando = widget.procesando?.call(item) ?? false;
    final tam = chico ? 20.0 : 26.0;
    var opacidad = colores.opacidad;
    if (aten) opacidad = 0.3;
    if (cargando) opacidad = 0.55;
    return Opacity(
      opacity: opacidad,
      child: GestureDetector(
        onTap: (deshab || cargando) ? null : () => widget.onTap(item),
        child: Container(
          width: tam,
          height: tam,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colores.fondo,
            border: Border.all(color: colores.borde, width: 1.5),
            borderRadius: BorderRadius.circular(chico ? 3 : 5),
            boxShadow: estilo == EstiloAsiento.seleccionado
                ? [BoxShadow(color: C.ambar.withValues(alpha: 0.25), spreadRadius: 2)]
                : null,
          ),
          child: Text(
            cargando ? '…' : sillaNum(item, idx),
            style: TextStyle(fontSize: chico ? 8 : 9.5, fontWeight: FontWeight.w700, color: colores.texto, height: 1),
          ),
        ),
      ),
    );
  }

  Widget _vistaFilas() {
    final grupos = agruparFilas(widget.items);
    return IntrinsicWidth(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFC5CFE0), width: 3))),
          child: const Text('▲ ESCENARIO ▲',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.gris, letterSpacing: 2)),
        ),
        for (final entry in grupos.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              GestureDetector(
                onTap: widget.onTapGrupo == null ? null : () => widget.onTapGrupo!(entry.value),
                child: SizedBox(
                  width: 46,
                  child: Column(children: [
                    Text('Fila ${entry.key}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.azul)),
                    Text('${entry.value.where((i) => i.estado == 'disponible').length} disp.',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: C.verde)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: alineacionDe(widget.alineacion, entry.key),
                  children: [
                    for (final (i, item) in enOrdenVisual(widget.ordenSillas, entry.key, entry.value).indexed) ...[
                      if (i > 0) const SizedBox(width: 3),
                      _asiento(item, i),
                    ],
                  ],
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _vistaMesas() {
    final grupos = agruparMesas(widget.items);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final fila in grupos.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.only(bottom: 4),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFC5CFE0), width: 2))),
              child: Text('FILA ${fila.key}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.azul, letterSpacing: 1)),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (i, mesa) in fila.value.entries.indexed) ...[
                if (i > 0) const SizedBox(width: 7),
                _mesa(mesa.key, mesa.value),
              ],
            ]),
          ]),
        ),
    ]);
  }

  Widget _mesa(String nombre, List<ItemAsiento> items) {
    final disp = items.where((i) => i.estado == 'disponible').length;
    final selCnt = items.where((i) => widget.estilo(i) == EstiloAsiento.seleccionado).length;
    final llena = disp == 0;
    final cols = colsMesa(items.length);
    final borde = llena ? C.rojo : (selCnt > 0 ? C.ambar : C.verde);
    final filas = <List<(int, ItemAsiento)>>[];
    for (final (i, item) in items.indexed) {
      if (i % cols == 0) filas.add([]);
      filas.last.add((i, item));
    }
    return Opacity(
      opacity: llena ? 0.65 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: selCnt > 0 ? const Color(0xFFFEFCE8) : Colors.white,
          border: Border.all(color: borde, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: widget.onTapGrupo == null ? null : () => widget.onTapGrupo!(items),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFEEF0FB), borderRadius: BorderRadius.circular(4)),
                child: Text(nombre, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.azul)),
              ),
              const SizedBox(width: 6),
              if (selCnt > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFFEF08A), borderRadius: BorderRadius.circular(8)),
                  child: Text('$selCnt★',
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                )
              else
                Text(llena ? 'Llena' : '$disp',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: llena ? C.rojo : C.verde)),
            ]),
          ),
          const SizedBox(height: 4),
          for (final fila in filas)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final (j, (idx, item)) in fila.indexed) ...[
                  if (j > 0) const SizedBox(width: 2),
                  _asiento(item, idx, chico: true),
                ],
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: C.borde),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove),
              onPressed: _zoom <= zoomMin + 0.001 ? null : () => _cambiarZoom(-0.15),
            ),
            SizedBox(
              width: 44,
              child: Text('${(_zoom * 100).round()}%',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              onPressed: _zoom >= zoomMax - 0.001 ? null : () => _cambiarZoom(0.15),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      Container(
        height: widget.alto,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.borde),
        ),
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          transformationController: _ctrl,
          constrained: false,
          minScale: zoomMin,
          maxScale: zoomMax,
          boundaryMargin: const EdgeInsets.all(120),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: widget.esMesa ? _vistaMesas() : _vistaFilas(),
          ),
        ),
      ),
    ]);
  }
}
