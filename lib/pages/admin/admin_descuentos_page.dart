import 'package:flutter/material.dart';

import '../../core/nav.dart';
import '../../core/tema.dart';
import '../../services/descuentos_admin.dart';
import '../../widgets/comunes.dart';

/* Tipos de descuento (%) por evento -- solo admin. El link/QR público y el
   reporte de usos se gestionan solo desde la web; al editar se conservan. */

class _Form {
  int? id;
  final nombre = TextEditingController();
  final porcentaje = TextEditingController();
  final motivo = TextEditingController();
  bool activo = true;
  String aplicaSobre = 'final';
  Set<int> usuarios = {};
  String? fechaInicio;
  String? fechaFin;
  int? maxUsos;
  int? usosPorCedula = 1;

  void dispose() {
    nombre.dispose();
    porcentaje.dispose();
    motivo.dispose();
  }
}

/* Perfiles que venden, primero en la lista. */
const _perfilesVenta = ['vendedores', 'vendedor_secundario', 'admin', 'super_admin', 'suscriptores'];

class AdminDescuentosPage extends StatefulWidget {
  final String codigoEvento;
  const AdminDescuentosPage({super.key, required this.codigoEvento});

  @override
  State<AdminDescuentosPage> createState() => _AdminDescuentosPageState();
}

class _AdminDescuentosPageState extends State<AdminDescuentosPage> {
  List<DescuentoEventoAdmin> _descuentos = [];
  bool _cargando = true;
  int? _cambiandoActivoId;
  _Form? _form;
  bool _guardando = false;
  List<UsuarioParaAutorizar> _usuarios = [];
  String _usuariosEstado = 'loading';
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final lista = await listarDescuentosEvento(widget.codigoEvento);
    if (mounted) {
      setState(() {
        _descuentos = lista;
        _cargando = false;
      });
    }
  }

  Future<void> _cargarUsuarios() async {
    setState(() => _usuariosEstado = 'loading');
    final lista = await listarUsuariosParaAutorizar();
    if (!mounted) return;
    setState(() {
      _usuarios = lista;
      _usuariosEstado = lista.isEmpty ? 'error' : 'ok';
    });
  }

  List<UsuarioParaAutorizar> get _usuariosOrdenados {
    final q = _filtro.trim().toLowerCase();
    int rango(String p) {
      final i = _perfilesVenta.indexOf(p.toLowerCase());
      return i == -1 ? 99 : i;
    }

    return _usuarios
        .where((u) =>
            q.isEmpty ||
            u.nombre.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            u.perfil.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final r = rango(a.perfil).compareTo(rango(b.perfil));
        return r != 0 ? r : a.nombre.compareTo(b.nombre);
      });
  }

  String _nombreUsuario(int id) => _usuarios.where((u) => u.id == id).firstOrNull?.nombre ?? '#$id';

  void _abrirNuevo() {
    _form?.dispose();
    setState(() => _form = _Form());
  }

  void _abrirEdicion(DescuentoEventoAdmin d) {
    _form?.dispose();
    final f = _Form()
      ..id = d.id
      ..activo = d.activo
      ..aplicaSobre = d.aplicaSobre
      ..usuarios = d.usuarios.map((u) => u.idAdmin).toSet()
      ..fechaInicio = d.fechaInicio
      ..fechaFin = d.fechaFin
      ..maxUsos = d.maxUsos
      ..usosPorCedula = d.usosPorCedula;
    f.nombre.text = d.nombre;
    f.porcentaje.text = d.porcentajeTexto;
    f.motivo.text = d.mensajeMotivo ?? '';
    setState(() => _form = f);
  }

  void _cerrarForm() {
    _form?.dispose();
    setState(() => _form = null);
  }

  Future<void> _guardar() async {
    final f = _form!;
    final nombre = f.nombre.text.trim();
    final pct = double.tryParse(f.porcentaje.text.replaceAll(',', '.')) ?? 0;
    if (nombre.isEmpty) return toast('Ponle un nombre al descuento.');
    if (!(pct > 0 && pct <= 100)) return toast('El porcentaje debe estar entre 0 y 100.');
    setState(() => _guardando = true);
    final resp = await guardarDescuentoEvento({
      if (f.id != null) 'id': f.id else 'codigoEvento': widget.codigoEvento,
      'nombre': nombre,
      'porcentaje': pct,
      'mensaje_motivo': f.motivo.text.trim(),
      'activo': f.activo,
      'aplica_sobre': f.aplicaSobre,
      'usuarios': f.usuarios.toList(),
      'fecha_inicio': f.fechaInicio,
      'fecha_fin': f.fechaFin,
      'max_usos': f.maxUsos,
      'usos_por_cedula': f.usosPorCedula,
    });
    if (!mounted) return;
    setState(() => _guardando = false);
    if (resp.success) {
      toast(f.id != null ? 'Descuento actualizado.' : 'Descuento creado.');
      _cerrarForm();
      _cargar();
    } else {
      toast(resp.message ?? 'No se pudo guardar el descuento.');
    }
  }

  Future<void> _cambiarActivo(DescuentoEventoAdmin d) async {
    setState(() => _cambiandoActivoId = d.id);
    final resp = await guardarDescuentoEvento({
      'id': d.id,
      'nombre': d.nombre,
      'porcentaje': d.porcentaje,
      'mensaje_motivo': d.mensajeMotivo ?? '',
      'activo': !d.activo,
      'aplica_sobre': d.aplicaSobre,
      'usuarios': d.usuarios.map((u) => u.idAdmin).toList(),
      'fecha_inicio': d.fechaInicio,
      'fecha_fin': d.fechaFin,
      'max_usos': d.maxUsos,
      'usos_por_cedula': d.usosPorCedula,
    });
    if (resp.success) {
      await _cargar();
    } else {
      toast(resp.message ?? 'No se pudo cambiar el estado.');
    }
    if (mounted) setState(() => _cambiandoActivoId = null);
  }

  Future<void> _eliminar(DescuentoEventoAdmin d) async {
    final si = await confirmar(context,
        titulo: '¿Eliminar descuento?',
        mensaje: 'Se eliminará "${d.nombre}". Los usos ya registrados se conservan.',
        si: 'Eliminar',
        peligro: true);
    if (!si) return;
    final resp = await eliminarDescuentoEvento(d.id);
    toast(resp.success ? 'Descuento eliminado.' : (resp.message ?? 'No se pudo eliminar.'));
    if (resp.success) _cargar();
  }

  Widget _formulario(_Form f) {
    final ordenados = _usuariosOrdenados;
    return Tarjeta(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TituloTarjeta(f.id != null ? 'Editar descuento' : 'Nuevo descuento'),
        TextField(controller: f.nombre, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Promo radio X')),
        const SizedBox(height: 10),
        TextField(
          controller: f.porcentaje,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Porcentaje *', hintText: 'Ej: 10'),
        ),
        CheckboxListTile(
          value: f.activo,
          onChanged: (v) => setState(() => f.activo = v ?? true),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Activo (disponible para vender)'),
        ),
        Text('¿Sobre qué se aplica el %?', style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
        RadioGroup<String>(
          groupValue: f.aplicaSobre,
          onChanged: (v) => setState(() => f.aplicaSobre = v ?? 'final'),
          child: const Column(children: [
            RadioListTile<String>(
              value: 'final',
              contentPadding: EdgeInsets.zero,
              title: Text('Precio final'),
              subtitle: Text('precio + IVA + comisiones, como siempre'),
            ),
            RadioListTile<String>(
              value: 'base',
              contentPadding: EdgeInsets.zero,
              title: Text('Precio base'),
              subtitle: Text('solo el precio del boleto; IVA y comisiones se calculan después, sobre el precio ya rebajado'),
            ),
          ]),
        ),
        TextField(
          controller: f.motivo,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Mensaje / motivo (opcional)',
              hintText: 'Ej: Obtuviste un 10% de descuento por ser oyente de Radio X'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text('Vendedores autorizados${f.usuarios.isNotEmpty ? ' (${f.usuarios.length})' : ''}',
                style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
          ),
          if (_usuariosEstado == 'ok' && _usuarios.isNotEmpty) ...[
            TextButton(
              onPressed: () => setState(() => f.usuarios.addAll(ordenados.map((u) => u.id))),
              child: const Text('Marcar todos'),
            ),
            TextButton(
              onPressed: () => setState(() => f.usuarios.clear()),
              style: TextButton.styleFrom(foregroundColor: C.rojo),
              child: const Text('Quitar todos'),
            ),
          ],
        ]),
        if (_usuariosEstado == 'ok' && _usuarios.length > 6)
          TextField(
            onChanged: (v) => setState(() => _filtro = v),
            decoration: const InputDecoration(
                hintText: 'Buscar por nombre, usuario o perfil…', prefixIcon: Icon(Icons.search)),
          ),
        if (_usuariosEstado == 'loading') const Padding(padding: EdgeInsets.all(8), child: Text('Cargando usuarios…')),
        if (_usuariosEstado == 'error')
          Row(children: [
            const Expanded(child: Text('No se pudo cargar la lista de usuarios.')),
            TextButton(onPressed: _cargarUsuarios, child: const Text('Reintentar')),
          ]),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView(shrinkWrap: true, children: [
            for (final u in ordenados)
              CheckboxListTile(
                dense: true,
                value: f.usuarios.contains(u.id),
                onChanged: (v) => setState(() => v == true ? f.usuarios.add(u.id) : f.usuarios.remove(u.id)),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(u.nombre),
                subtitle: Text(u.perfil.isEmpty ? 'sin perfil' : u.perfil),
              ),
          ]),
        ),
        Text('Si no marcas a nadie, ningún vendedor podrá aplicarlo a mano.',
            style: TextStyle(fontSize: 12, color: colorTenue(context))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: BotonAccion('Guardar', primario: true, cargando: _guardando, onPressed: _guardar)),
          const SizedBox(width: 10),
          Expanded(child: BotonAccion('Cancelar', onPressed: _guardando ? null : _cerrarForm)),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;
    return Scaffold(
      appBar: AppBar(title: const Text('Descuentos')),
      body: Contenido(children: [
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Tipos de descuento (%) que un vendedor puede marcar a mano al vender un boleto de este evento. Solo pueden '
              'aplicarlo los vendedores que marques como autorizados abajo.',
              style: TextStyle(color: colorTenue(context)),
            ),
            if (f == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _abrirNuevo, icon: const Icon(Icons.add), label: const Text('Nuevo descuento')),
            ],
          ]),
        ),
        if (f != null) _formulario(f),
        if (_cargando) const Center(child: CircularProgressIndicator()),
        if (!_cargando && _descuentos.isEmpty && f == null) const MensajeVacio('Todavía no hay descuentos para este evento.'),
        if (!_cargando)
          for (final d in _descuentos)
            Tarjeta(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(d.nombre, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: colorTexto(context))),
                      if ((d.mensajeMotivo ?? '').isNotEmpty)
                        Text(d.mensajeMotivo!, style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                    ]),
                  ),
                  Text('-${d.porcentajeTexto}%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.verde)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Insignia(d.aplicaSobre == 'base' ? 'Sobre precio base' : 'Sobre precio final',
                      fondo: d.aplicaSobre == 'base' ? C.naranjaFondo : const Color(0xFFE3E5F8),
                      color: d.aplicaSobre == 'base' ? const Color(0xFFB45309) : C.azul),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: _cambiandoActivoId == d.id
                        ? const MiniSpinner(color: C.azul)
                        : Text(d.activo ? 'Activo' : 'Inactivo'),
                    backgroundColor: d.activo ? const Color(0xFFD4F1DD) : const Color(0xFFEDEFF3),
                    onPressed: _cambiandoActivoId == d.id ? null : () => _cambiarActivo(d),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.groups_outlined, size: 16, color: colorTenue(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d.usuarios.isEmpty
                          ? 'Ningún vendedor autorizado'
                          : d.usuarios.map((u) => u.nombre.isNotEmpty ? u.nombre : _nombreUsuario(u.idAdmin)).join(', '),
                      style: TextStyle(fontSize: 12.5, color: colorTenue(context)),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.local_offer_outlined, size: 16, color: colorTenue(context)),
                  const SizedBox(width: 6),
                  Text('${d.usosValidos} uso${d.usosValidos == 1 ? '' : 's'} registrado${d.usosValidos == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12.5, color: colorTenue(context))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _abrirEdicion(d), icon: const Icon(Icons.edit_outlined), label: const Text('Editar')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: C.rojo, side: const BorderSide(color: C.rojo)),
                      onPressed: () => _eliminar(d),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                  ),
                ]),
              ]),
            ),
      ]),
    );
  }
}
