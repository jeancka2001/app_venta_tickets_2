import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/json.dart';
import '../core/nav.dart';
import '../models/venta.dart';
import '../widgets/comunes.dart';
import '../widgets/tarjeta_registro.dart';
import 'canjear_entradas_page.dart';
import 'detalle_compra_page.dart';
import 'escanear_boleto_page.dart';

class BuscarClientePage extends StatefulWidget {
  const BuscarClientePage({super.key});

  @override
  State<BuscarClientePage> createState() => _BuscarClientePageState();
}

class _BuscarClientePageState extends State<BuscarClientePage> {
  final _cedula = TextEditingController();
  bool _buscando = false;
  bool _buscado = false;
  List<Registro> _registros = [];
  String _nombreCliente = '';
  String _cedulaBuscada = '';
  String _error = '';

  @override
  void dispose() {
    _cedula.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final ced = _cedula.text.trim();
    FocusScope.of(context).unfocus();
    if (ced.isEmpty) {
      setState(() => _error = 'Ingresa una cédula.');
      return;
    }
    setState(() {
      _buscando = true;
      _error = '';
      _buscado = false;
    });
    try {
      final res = await Future.wait([
        dio.post('$urlBase/listarRegistros', data: {'cedula': ced}, options: hdr(apiHdr())),
        dio.post('$urlBase/consultar_cedula', data: {'cedula': ced, 'email': ''}, options: hdr(apiHdr())),
      ]);
      final regs = asMap(res[0].data);
      final cli = asMap(res[1].data);
      setState(() {
        _registros = asMapList(regs['data']).map(Registro.fromJson).toList();
        _nombreCliente = cli['success'] == true ? str(asMap(cli['data'])['nombreCompleto']) : '';
        _cedulaBuscada = ced;
        _buscado = true;
      });
    } catch (_) {
      setState(() => _error = 'Error de conexión al buscar el cliente.');
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TituloConLogo('Buscar Cliente'),
        actions: [
          IconButton(
            tooltip: 'Canjear entradas',
            icon: const Icon(Icons.done_all),
            onPressed: () => ir(const CanjearEntradasPage()),
          ),
          IconButton(
            tooltip: 'Escanear boleto',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => ir(const EscanearBoletoPage()),
          ),
        ],
      ),
      body: Contenido(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _cedula,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: const InputDecoration(hintText: 'Cédula del cliente'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _buscando ? null : _buscar,
              child: _buscando ? const MiniSpinner() : const Icon(Icons.search),
            ),
          ),
        ]),
        if (_error.isNotEmpty) TextoError(_error),
        if (_buscado && _nombreCliente.isNotEmpty)
          Text('$_nombreCliente · $_cedulaBuscada',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colorTexto(context))),
        if (_buscado && _registros.isEmpty) const MensajeVacio('Este cliente no tiene compras registradas.'),
        if (_buscado)
          for (final reg in _registros) TarjetaRegistro(reg: reg, onTap: () => ir(DetalleCompraPage(id: reg.id))),
      ]),
    );
  }
}
