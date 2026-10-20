import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formato.dart';
import '../../core/nav.dart';
import '../../services/admin_eventos.dart';
import '../../services/bloqueo_sesion.dart';
import '../../widgets/comunes.dart';

const _ivaOpciones = [('1.00', 'Sin IVA (0%)'), ('1.12', '12%'), ('1.15', '15%')];
const _estadoOpciones = ['PROCESO', 'PROXIMO', 'ACTIVO'];

/* Crear evento (sin localidades) o editar sus datos básicos. */
class AdminEventoFormPage extends StatefulWidget {
  final EventoAdmin? evento;
  const AdminEventoFormPage({super.key, this.evento});

  @override
  State<AdminEventoFormPage> createState() => _AdminEventoFormPageState();
}

class _AdminEventoFormPageState extends State<AdminEventoFormPage> {
  late final bool _esEdicion = widget.evento != null;
  late final _nombre = TextEditingController(text: widget.evento?.nombreConcierto ?? '');
  late String _fecha = widget.evento?.fechaConcierto ?? '';
  late String _hora = widget.evento?.horaConcierto ?? '';
  late final _lugar = TextEditingController(text: widget.evento?.lugarConcierto ?? '');
  late final _ciudad = TextEditingController(text: widget.evento?.cuidadConcert ?? '');
  late final _descripcion = TextEditingController(text: widget.evento?.descripcionConcierto ?? '');
  late String _iva = widget.evento?.iva ?? '1.00';
  String _estado = 'ACTIVO';
  late String _imagenUrl = widget.evento?.imagenConcierto ?? '';
  late String _mapaUrl = widget.evento?.mapaConcierto ?? '';
  bool _subiendoImagen = false;
  bool _subiendoMapa = false;
  bool _guardando = false;
  String _error = '';

  @override
  void dispose() {
    for (final c in [_nombre, _lugar, _ciudad, _descripcion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirImagen(bool esMapa) async {
    final foto = await sinBloqueo(() => ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90));
    if (foto == null) return;
    setState(() => esMapa ? _subiendoMapa = true : _subiendoImagen = true);
    final url = await subirImagenEvento(foto.path);
    if (!mounted) return;
    setState(() {
      if (url != null) {
        if (esMapa) {
          _mapaUrl = url;
        } else {
          _imagenUrl = url;
        }
      }
      esMapa ? _subiendoMapa = false : _subiendoImagen = false;
    });
    if (url == null) toast('No se pudo subir la imagen.');
  }

  Future<void> _elegirHora() async {
    final partes = _hora.split(':');
    final inicial = partes.length >= 2
        ? TimeOfDay(hour: int.tryParse(partes[0]) ?? 20, minute: int.tryParse(partes[1]) ?? 0)
        : const TimeOfDay(hour: 20, minute: 0);
    final t = await showTimePicker(context: context, initialTime: inicial);
    if (t != null) setState(() => _hora = '${dosDigitos(t.hour)}:${dosDigitos(t.minute)}');
  }

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty ||
        _fecha.isEmpty ||
        _hora.isEmpty ||
        _lugar.text.trim().isEmpty ||
        _ciudad.text.trim().isEmpty) {
      setState(() => _error = 'Completa nombre, fecha, hora, lugar y ciudad.');
      return;
    }
    if (!_esEdicion && _imagenUrl.isEmpty) {
      setState(() => _error = 'Sube la imagen principal del evento.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = '';
    });
    try {
      if (_esEdicion) {
        final r = await actualizarDescripcionEvento({
          'id_evento': widget.evento!.id,
          'nombreConcierto': _nombre.text.trim(),
          'fechaConcierto': _fecha,
          'horaConcierto': _hora,
          'lugarConcierto': _lugar.text.trim(),
          'cuidadConcert': _ciudad.text.trim(),
          'descripcionConcierto': _descripcion.text.trim(),
          if (_imagenUrl.isNotEmpty) 'imagenConcierto': _imagenUrl,
          if (_mapaUrl.isNotEmpty) 'mapaConcierto': _mapaUrl,
        });
        if (r.success) {
          toast('Evento actualizado.');
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() => _error = r.message ?? 'No se pudo actualizar el evento.');
        }
      } else {
        final r = await crearEventoAdmin({
          'nombreConcierto': _nombre.text.trim(),
          'fechaConcierto': _fecha,
          'horaConcierto': _hora,
          'lugarConcierto': _lugar.text.trim(),
          'cuidadConcert': _ciudad.text.trim(),
          'descripcionConcierto': _descripcion.text.trim(),
          'imagenConcierto': _imagenUrl,
          'mapaConcierto': _mapaUrl,
          'iva': _iva,
          'estado': _estado,
        });
        if (r.success) {
          toast('Evento creado. Ahora añade sus localidades.');
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() => _error = r.message ?? 'No se pudo crear el evento.');
        }
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _campoImagen(String titulo, String url, bool subiendo, bool esMapa) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: TextStyle(fontWeight: FontWeight.w700, color: colorTexto(context))),
          const SizedBox(height: 6),
          if (url.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(url, height: 160, fit: BoxFit.cover, errorBuilder: (c, e, s) => const SizedBox()),
            ),
          const SizedBox(height: 6),
          BotonAccion(
            url.isNotEmpty ? (esMapa ? 'Cambiar mapa' : 'Cambiar imagen') : (esMapa ? 'Subir mapa' : 'Subir imagen'),
            icono: Icons.cloud_upload_outlined,
            cargando: subiendo,
            onPressed: () => _elegirImagen(esMapa),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_esEdicion ? 'Editar evento' : 'Nuevo evento')),
      body: Contenido(children: [
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre del evento')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: CampoFecha(etiqueta: 'Fecha', valor: _fecha, onChanged: (v) => setState(() => _fecha = v))),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _elegirHora,
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Hora', suffixIcon: Icon(Icons.schedule, size: 18)),
                    child: Text(_hora.isEmpty ? '—' : _hora),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _lugar, decoration: const InputDecoration(labelText: 'Lugar')),
            const SizedBox(height: 12),
            TextField(controller: _ciudad, decoration: const InputDecoration(labelText: 'Ciudad')),
            const SizedBox(height: 12),
            TextField(
                controller: _descripcion, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Descripción')),
            if (!_esEdicion) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _iva,
                    decoration: const InputDecoration(labelText: 'IVA'),
                    items: [for (final (v, l) in _ivaOpciones) DropdownMenuItem(value: v, child: Text(l))],
                    onChanged: (v) => setState(() => _iva = v ?? _iva),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _estado,
                    decoration: const InputDecoration(labelText: 'Estado inicial'),
                    items: [for (final e in _estadoOpciones) DropdownMenuItem(value: e, child: Text(e))],
                    onChanged: (v) => setState(() => _estado = v ?? _estado),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        Tarjeta(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const TituloTarjeta('Imágenes', icono: Icons.image_outlined),
            _campoImagen('Imagen principal${_esEdicion ? '' : ' *'}', _imagenUrl, _subiendoImagen, false),
            const SizedBox(height: 16),
            _campoImagen('Mapa / plano de localidades', _mapaUrl, _subiendoMapa, true),
          ]),
        ),
        if (!_esEdicion)
          Text('El evento se crea sin localidades — luego de guardarlo, entra a su detalle para añadirlas con sus precios.',
              style: TextStyle(color: colorTenue(context), fontSize: 12.5)),
        if (_error.isNotEmpty) TextoError(_error),
        BotonAccion(_esEdicion ? 'Guardar cambios' : 'Crear evento',
            primario: true, cargando: _guardando, onPressed: _guardar),
        const SizedBox(height: 20),
      ]),
    );
  }
}
