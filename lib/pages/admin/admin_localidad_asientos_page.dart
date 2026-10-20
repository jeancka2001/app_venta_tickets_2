import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../services/admin_eventos.dart';
import '../../services/localidad_config.dart';
import '../../services/mapa_asientos.dart';
import '../../widgets/comunes.dart';
import '../../widgets/mapa_asientos.dart';

/* Mismo mapa visual que usa el vendedor al comprar, pero tocar un asiento
   abre opciones para bloquear/liberar en vez de agregarlo al carrito. */
class AdminLocalidadAsientosPage extends StatefulWidget {
  final int idLocalidad;
  final String localidadNombre;
  final String tipoLocalidad;
  const AdminLocalidadAsientosPage(
      {super.key, required this.idLocalidad, required this.localidadNombre, required this.tipoLocalidad});

  @override
  State<AdminLocalidadAsientosPage> createState() => _AdminLocalidadAsientosPageState();
}

class _AdminLocalidadAsientosPageState extends State<AdminLocalidadAsientosPage> {
  List<ItemAsiento> _items = [];
  ResumenLocalidad _resumen = const ResumenLocalidad(0, 0, 0);
  Map<String, String> _alineacion = {};
  Map<String, bool> _ordenSillas = {};
  int? _idEspacio;
  bool _cargando = true;

  bool get _esMesa => widget.tipoLocalidad == 'mesa';

  @override
  void initState() {
    super.initState();
    obtenerConfiguracionLocalidad(widget.idLocalidad).then((cfg) {
      if (!mounted) return;
      setState(() {
        _alineacion = cfg.alineacion;
        _ordenSillas = cfg.ordenSillas;
        _idEspacio = cfg.idEspacio;
      });
      if (cfg.idEspacio != null) {
        _cargar();
      } else {
        setState(() => _cargando = false);
      }
    });
  }

  Future<void> _cargar() async {
    if (_idEspacio == null) return;
    setState(() => _cargando = true);
    final r = await obtenerMapaLocalidad(_idEspacio!, widget.idLocalidad);
    if (!mounted) return;
    setState(() {
      _items = r.items;
      _resumen = r.resumen;
      _cargando = false;
    });
  }

  Future<void> _tocarAsiento(ItemAsiento item) async {
    if (item.estado == 'ocupado' && (item.cedula ?? '').isNotEmpty) {
      toast('No puedes editar este asiento: está ocupado por un cliente.');
      return;
    }
    final disponible = item.estado == 'disponible';
    final i = await elegirOpcion(context,
        titulo: 'Asiento ${item.silla} · ${item.estado}',
        opciones: [disponible ? 'Bloquear (reservar sin venta)' : 'Liberar asiento']);
    if (i == null) return;
    if (disponible) {
      final ok = await cambiarEstadoAsiento(item.idsilla, 'Ocupado');
      toast(ok ? 'Asiento bloqueado.' : 'No se pudo bloquear el asiento.');
      if (ok) await _cargar();
    } else {
      final r = await liberarAsientosAdmin([item.idsilla]);
      if (r.success) {
        toast('Asiento liberado.');
        await _cargar();
      } else {
        toast(r.message ?? 'No se pudo liberar el asiento.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.localidadNombre.isEmpty ? 'Asientos' : widget.localidadNombre),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Cargando(texto: 'Cargando mapa...')
          : _items.isEmpty
              ? const MensajeVacio('No se encontraron asientos para esta localidad.')
              : Contenido(children: [
                  Text(
                      '${_resumen.disponibles} de ${_resumen.total} disponibles. Toca un asiento para bloquearlo o liberarlo.',
                      style: TextStyle(color: colorTenue(context))),
                  const Leyenda([
                    LeyendaItem('Disponible', EstiloAsiento.disponible),
                    LeyendaItem('Reservada', EstiloAsiento.reservado),
                    LeyendaItem('Bloqueada', EstiloAsiento.bloqueado),
                    LeyendaItem('Vendida', EstiloAsiento.ocupado),
                  ]),
                  MapaAsientos(
                    items: _items,
                    esMesa: _esMesa,
                    alineacion: _alineacion,
                    ordenSillas: _ordenSillas,
                    estilo: estiloAsiento,
                    onTap: _tocarAsiento,
                    deshabilitado: (i) => i.estado == 'ocupado' && (i.cedula ?? '').isNotEmpty,
                    alto: MediaQuery.sizeOf(context).height * 0.62,
                  ),
                ]),
    );
  }
}
