import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/tema.dart';

const logoAsset = 'assets/images/MARCA_TICKETS.png';

bool esOscuro(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

Color colorTexto(BuildContext context) => esOscuro(context) ? Colors.white : C.azulOscuro;

Color colorTenue(BuildContext context) => esOscuro(context) ? Colors.white60 : C.gris;

Color colorAcento(BuildContext context) => esOscuro(context) ? C.lila : C.azul;

/* Título de AppBar con el logo a la izquierda (como en la app Ionic). */
class TituloConLogo extends StatelessWidget {
  final String titulo;
  const TituloConLogo(this.titulo, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        Image.asset(logoAsset, height: 30),
        const SizedBox(width: 10),
        Flexible(child: Text(titulo, overflow: TextOverflow.ellipsis)),
      ]);
}

class Tarjeta extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borde;
  const Tarjeta({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.borde});

  @override
  Widget build(BuildContext context) {
    final contenido = Padding(padding: padding, child: child);
    return Card(
      color: color,
      shape: borde == null
          ? null
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: borde!, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? contenido : InkWell(onTap: onTap, child: contenido),
    );
  }
}

class TituloTarjeta extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final Widget? trailing;
  const TituloTarjeta(this.texto, {super.key, this.icono, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (icono != null) ...[Icon(icono, size: 18, color: colorAcento(context)), const SizedBox(width: 6)],
          Expanded(
            child: Text(texto,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: colorTexto(context))),
          ),
          ?trailing,
        ]),
      );
}

/* Fila "Etiqueta ...... valor". */
class FilaDato extends StatelessWidget {
  final String etiqueta;
  final String? valor;
  final Widget? valorWidget;
  final bool destacado;
  const FilaDato(this.etiqueta, this.valor, {super.key, this.valorWidget, this.destacado = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(etiqueta,
                style: TextStyle(
                    fontSize: destacado ? 16 : 13.5,
                    fontWeight: destacado ? FontWeight.w800 : FontWeight.w500,
                    color: destacado ? colorTexto(context) : colorTenue(context))),
          ),
          const SizedBox(width: 12),
          valorWidget ??
              Flexible(
                child: Text(valor ?? '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: destacado ? 17 : 13.5,
                        fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                        color: colorTexto(context))),
              ),
        ]),
      );
}

class Insignia extends StatelessWidget {
  final String texto;
  final Color fondo;
  final Color color;
  const Insignia(this.texto, {super.key, required this.fondo, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(20)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );
}

/* Insignia de estado de pago de una compra. */
Insignia insigniaEstadoPago(String estado) {
  switch (estado) {
    case 'Pagado':
      return Insignia(estado, fondo: const Color(0xFFD4F1DD), color: const Color(0xFF155724));
    case 'Pendiente':
      return Insignia(estado, fondo: C.naranjaFondo, color: const Color(0xFFB45309));
    case 'Comprobar':
      return Insignia(estado, fondo: const Color(0xFFE3E5F8), color: C.azul);
    case 'Expirado':
      return Insignia(estado, fondo: const Color(0xFFEDEFF3), color: C.gris);
    default:
      return Insignia(estado.isEmpty ? '—' : estado, fondo: C.rojoFondo, color: C.rojoOscuro);
  }
}

/* Insignia de estado de un evento (admin). */
Insignia insigniaEstadoEvento(String estado) {
  switch (estado) {
    case 'ACTIVO':
      return Insignia(estado, fondo: const Color(0xFFD4F1DD), color: const Color(0xFF155724));
    case 'PROXIMO':
      return Insignia(estado, fondo: const Color(0xFFE3E5F8), color: C.azul);
    case 'CANCELADO':
      return Insignia(estado, fondo: C.rojoFondo, color: C.rojoOscuro);
    case 'FINALIZADO':
      return Insignia(estado, fondo: const Color(0xFFEDEFF3), color: C.gris);
    default:
      return Insignia(estado, fondo: C.naranjaFondo, color: const Color(0xFFB45309));
  }
}

class Cargando extends StatelessWidget {
  final String? texto;
  const Cargando({super.key, this.texto});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (texto != null) ...[
              const SizedBox(height: 12),
              Text(texto!, style: TextStyle(color: colorTenue(context))),
            ],
          ]),
        ),
      );
}

class MensajeVacio extends StatelessWidget {
  final String texto;
  final bool error;
  final IconData? icono;
  const MensajeVacio(this.texto, {super.key, this.error = false, this.icono});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (icono != null) ...[Icon(icono, size: 56, color: colorTenue(context)), const SizedBox(height: 12)],
            Text(texto,
                textAlign: TextAlign.center,
                style: TextStyle(color: error ? C.rojo : colorTenue(context), fontSize: 14.5)),
          ]),
        ),
      );
}

class TextoError extends StatelessWidget {
  final String texto;
  const TextoError(this.texto, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(texto, style: const TextStyle(color: C.rojo, fontWeight: FontWeight.w600, fontSize: 13.5)),
      );
}

class Aviso extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Color color;
  final Color fondo;
  const Aviso(this.texto,
      {super.key, this.icono = Icons.error_outline, this.color = const Color(0xFFB45309), this.fondo = C.naranjaFondo});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      );
}

/* Spinner chico para poner dentro de un botón. */
class MiniSpinner extends StatelessWidget {
  final Color? color;
  const MiniSpinner({super.key, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: color ?? Colors.white),
      );
}

/* Botón con ícono que muestra spinner mientras `cargando`. */
class BotonAccion extends StatelessWidget {
  final String texto;
  final IconData? icono;
  final VoidCallback? onPressed;
  final bool cargando;
  final bool primario;
  final Color? color;
  const BotonAccion(this.texto,
      {super.key, this.icono, this.onPressed, this.cargando = false, this.primario = false, this.color});

  @override
  Widget build(BuildContext context) {
    final hijo = cargando
        ? MiniSpinner(color: primario ? Colors.white : colorAcento(context))
        : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            if (icono != null) ...[Icon(icono, size: 19), const SizedBox(width: 8)],
            Flexible(child: Text(texto, textAlign: TextAlign.center)),
          ]);
    final accion = cargando ? null : onPressed;
    if (primario) {
      return FilledButton(
        style: color != null ? FilledButton.styleFrom(backgroundColor: color) : null,
        onPressed: accion,
        child: hijo,
      );
    }
    return OutlinedButton(
      style: color != null
          ? OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color!))
          : null,
      onPressed: accion,
      child: hijo,
    );
  }
}

/* Campo de fecha (reemplaza <input type="date">). */
class CampoFecha extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final String? min;
  final String? max;
  final ValueChanged<String> onChanged;
  const CampoFecha(
      {super.key, required this.etiqueta, required this.valor, required this.onChanged, this.min, this.max});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final actual = DateTime.tryParse(valor) ?? DateTime.now();
          final primera = (min != null ? DateTime.tryParse(min!) : null) ?? DateTime(2020);
          final ultima = (max != null ? DateTime.tryParse(max!) : null) ?? DateTime(2100);
          final elegido = await showDatePicker(
            context: context,
            initialDate: actual.isBefore(primera) ? primera : (actual.isAfter(ultima) ? ultima : actual),
            firstDate: primera,
            lastDate: ultima,
          );
          if (elegido != null) onChanged(fechaStr(elegido));
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: etiqueta, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
          child: Text(valor.isEmpty ? '—' : formatFecha(valor)),
        ),
      );
}

class RangoRapido {
  final String etiqueta;
  final (String, String) Function() calcular;
  const RangoRapido(this.etiqueta, this.calcular);
}

final rangoHoy = RangoRapido('Hoy', () => (hoyStr(), hoyStr()));
final rangoAyer = RangoRapido('Ayer', () => (haceDiasStr(1), haceDiasStr(1)));
final rango7Dias = RangoRapido('Últimos 7 días', () => (haceDiasStr(6), hoyStr()));
final rangoMes = RangoRapido('Este mes', () => (inicioMesStr(), hoyStr()));

/* Tarjeta "Rango de fechas" con Desde/Hasta y atajos. */
class TarjetaRangoFechas extends StatelessWidget {
  final String desde;
  final String hasta;
  final List<RangoRapido> rangos;
  final bool deshabilitado;
  final void Function(String desde, String hasta) onCambiarDesdeHasta;
  final void Function(String desde, String hasta) onRangoRapido;
  final Widget? pie;

  const TarjetaRangoFechas({
    super.key,
    required this.desde,
    required this.hasta,
    required this.rangos,
    required this.onCambiarDesdeHasta,
    required this.onRangoRapido,
    this.deshabilitado = false,
    this.pie,
  });

  @override
  Widget build(BuildContext context) => Tarjeta(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TituloTarjeta('Rango de fechas', icono: Icons.calendar_month_outlined),
          Row(children: [
            Expanded(
              child: CampoFecha(
                  etiqueta: 'Desde', valor: desde, max: hasta, onChanged: (v) => onCambiarDesdeHasta(v, hasta)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CampoFecha(
                  etiqueta: 'Hasta',
                  valor: hasta,
                  min: desde,
                  max: hoyStr(),
                  onChanged: (v) => onCambiarDesdeHasta(desde, v)),
            ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final r in rangos)
              ActionChip(
                label: Text(r.etiqueta),
                onPressed: deshabilitado
                    ? null
                    : () {
                        final (d, h) = r.calcular();
                        onRangoRapido(d, h);
                      },
              ),
          ]),
          if (pie != null) ...[const SizedBox(height: 12), pie!],
        ]),
      );
}

/* Contenedor estándar de una lista de tarjetas con ancho máximo (tablets). */
class Contenido extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;
  const Contenido({super.key, required this.children, this.padding = const EdgeInsets.all(14), this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final lista = ListView(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
    return onRefresh == null ? lista : RefreshIndicator(onRefresh: onRefresh!, child: lista);
  }
}

/* Diálogo de confirmación (equivalente a IonAlert con dos botones). */
Future<bool> confirmar(BuildContext context,
    {required String titulo, required String mensaje, String si = 'Aceptar', String no = 'Cancelar', bool peligro = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SingleChildScrollView(child: Text(mensaje)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(no)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: peligro ? TextButton.styleFrom(foregroundColor: C.rojo) : null,
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<void> informar(BuildContext context, {required String titulo, required String mensaje, String ok = 'Entendido'}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(child: Text(mensaje)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ok))],
      ),
    );

/* Hoja de opciones (equivalente a IonActionSheet). Devuelve el índice elegido. */
Future<int?> elegirOpcion(BuildContext context, {required String titulo, required List<String> opciones}) =>
    showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          for (var i = 0; i < opciones.length; i++)
            ListTile(title: Text(opciones[i]), onTap: () => Navigator.pop(ctx, i)),
          ListTile(
            title: const Text('Cancelar', style: TextStyle(color: C.rojo)),
            onTap: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
