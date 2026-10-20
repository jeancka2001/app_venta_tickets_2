import 'localidad_config.dart';

/* Agrupación del mapa de asientos: por fila, o por fila > mesa. */

String sillaNum(ItemAsiento item, int idx) {
  final partes = item.silla.split('-s-');
  if (partes.length > 1) return partes[1];
  final numero = item.raw['numero'];
  return numero != null ? numero.toString() : '${idx + 1}';
}

Map<String, Map<String, List<ItemAsiento>>> agruparMesas(List<ItemAsiento> items) {
  final r = <String, Map<String, List<ItemAsiento>>>{};
  for (final item in items) {
    final f = item.fila.isEmpty ? 'A' : item.fila;
    final m = (item.mesa == null || item.mesa!.isEmpty) ? 'M1' : item.mesa!;
    r.putIfAbsent(f, () => {}).putIfAbsent(m, () => []).add(item);
  }
  return r;
}

Map<String, List<ItemAsiento>> agruparFilas(List<ItemAsiento> items) {
  final r = <String, List<ItemAsiento>>{};
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final k = item.fila.isNotEmpty ? item.fila : String.fromCharCode(65 + i ~/ 20);
    r.putIfAbsent(k, () => []).add(item);
  }
  return r;
}

int colsMesa(int n) => n <= 6 ? n : (n <= 10 ? 5 : 6);

enum EstiloAsiento { disponible, reservado, bloqueado, ocupado, seleccionado }

EstiloAsiento estiloAsiento(ItemAsiento item) {
  if (item.estado == 'disponible') return EstiloAsiento.disponible;
  if (item.estado == 'reservado') return EstiloAsiento.reservado;
  if (item.estado == 'ocupado' && (item.cedula == null || item.cedula!.isEmpty)) return EstiloAsiento.bloqueado;
  return EstiloAsiento.ocupado;
}

/* "Fila A · Silla 5" / "Fila A · Mesa M2 · Silla 3". */
String etiquetaAsiento(ItemAsiento item, bool esMesa) {
  final partes = item.silla.split('-s-');
  final numero = partes.length > 1 ? partes[1] : item.silla;
  final r = [
    if (item.fila.isNotEmpty) 'Fila ${item.fila}',
    if (esMesa && item.mesa != null && item.mesa!.isNotEmpty) 'Mesa ${item.mesa}',
    if (numero.isNotEmpty) 'Silla $numero',
  ].join(' · ');
  return r.isNotEmpty ? r : 'Asiento #${item.idsilla}';
}
