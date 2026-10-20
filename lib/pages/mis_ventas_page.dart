import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formato.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../models/venta.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_registro.dart';
import 'detalle_compra_page.dart';

const _size = 20;

/* Historial de ventas del vendedor logueado -- solo lo que ESE usuario
   registró (id_operador), y por defecto solo las de HOY (cierre de caja). */
class MisVentasPage extends StatefulWidget {
  const MisVentasPage({super.key});

  @override
  State<MisVentasPage> createState() => _MisVentasPageState();
}

class _MisVentasPageState extends State<MisVentasPage> {
  String _desde = hoyStr();
  String _hasta = hoyStr();
  List<Registro> _registros = [];
  int _total = 0;
  bool _cargando = true;
  bool _cargandoMas = false;
  String _error = '';
  bool _hasNext = false;
  int _nextInit = 0;
  final _cedula = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar(0, true);
  }

  @override
  void dispose() {
    _cedula.dispose();
    super.dispose();
  }

  Future<void> _cargar(int init, bool reset) async {
    final staff = obtenerStaffData();
    if (staff == null) {
      setState(() {
        _cargando = false;
        _error = 'No se pudo identificar al vendedor.';
      });
      return;
    }
    setState(() {
      if (reset) {
        _cargando = true;
        _error = '';
      } else {
        _cargandoMas = true;
      }
    });
    try {
      final ced = _cedula.text.trim();
      final r = await dio.post('$urlBase/listarRegistros',
          data: ced.isNotEmpty ? {'cedula': ced} : {},
          queryParameters: {
            'id_operador': staff.id,
            'init': init,
            'size': _size,
            if (_desde.isNotEmpty && _hasta.isNotEmpty) 'fecha_init': _desde,
            if (_desde.isNotEmpty && _hasta.isNotEmpty) 'fecha_fin': _hasta,
          },
          options: hdr(apiHdr()));
      final data = asMap(r.data);
      final nuevos = asMapList(data['data']).map(Registro.fromJson).toList();
      setState(() {
        _registros = reset ? nuevos : [..._registros, ...nuevos];
        _total = ent(data['total']);
        _hasNext = truthy(data['hasNext']);
        _nextInit = ent(data['next_init']);
      });
    } catch (_) {
      if (reset) setState(() => _error = 'Error al conectar con el servidor.');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _cargandoMas = false;
        });
      }
    }
  }

  void _aplicarRango(String d, String h) {
    setState(() {
      _desde = d;
      _hasta = h;
    });
    _cargar(0, true);
  }

  @override
  Widget build(BuildContext context) {
    final esHoy = _desde == hoyStr() && _hasta == hoyStr();
    return Scaffold(
      appBar: AppBar(
        title: const TituloConLogo('Mis ventas'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SearchBar(
              controller: _cedula,
              hintText: 'Filtrar por cédula del cliente…',
              leading: const Icon(Icons.search),
              keyboardType: TextInputType.number,
              elevation: const WidgetStatePropertyAll(0),
              onSubmitted: (_) => _cargar(0, true),
              trailing: [
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _cedula.clear();
                    _cargar(0, true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: Contenido(
        onRefresh: () => _cargar(0, true),
        children: [
          TarjetaRangoFechas(
            desde: _desde,
            hasta: _hasta,
            deshabilitado: _cargando,
            rangos: [rangoHoy, rangoAyer, rango7Dias],
            onCambiarDesdeHasta: _aplicarRango,
            onRangoRapido: _aplicarRango,
          ),
          if (!_cargando && _error.isEmpty)
            Text(
              '$_total venta${_total == 1 ? '' : 's'} tuya${_total == 1 ? '' : 's'}'
              '${esHoy ? ' hoy' : ' del ${formatFecha(_desde)} al ${formatFecha(_hasta)}'}',
              style: TextStyle(fontWeight: FontWeight.w700, color: colorTenue(context)),
            ),
          if (_cargando) const Cargando(texto: 'Cargando tus ventas…'),
          if (!_cargando && _error.isNotEmpty) MensajeVacio(_error, error: true),
          if (!_cargando && _error.isEmpty && _registros.isEmpty)
            const MensajeVacio('No registraste ventas en este rango de fechas.'),
          if (!_cargando && _error.isEmpty)
            for (final reg in _registros)
              TarjetaRegistro(reg: reg, mostrarFormaPago: true, onTap: () => ir(DetalleCompraPage(id: reg.id))),
          if (!_cargando && _hasNext)
            BotonAccion('Cargar más ventas', cargando: _cargandoMas, onPressed: () => _cargar(_nextInit, false)),
        ],
      ),
    );
  }
}
