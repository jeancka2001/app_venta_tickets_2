const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

/* "2026-10-20 14:35:00" -> "20 Oct 2026" (con hora: "20 Oct 2026 · 14:35"). */
String formatFecha(String? fecha, {bool conHora = false}) {
  if (fecha == null || fecha.isEmpty) return '—';
  final solo = fecha.split(' ')[0].split('T')[0];
  final partes = solo.split('-');
  if (partes.length < 3) return fecha;
  final m = int.tryParse(partes[1]);
  final mes = (m != null && m >= 1 && m <= 12) ? meses[m - 1] : partes[1];
  var r = '${partes[2]} $mes ${partes[0]}';
  if (conHora) {
    final resto = fecha.contains(' ') ? fecha.split(' ')[1] : (fecha.contains('T') ? fecha.split('T')[1] : '');
    final hora = resto.length >= 5 ? resto.substring(0, 5) : '';
    if (hora.isNotEmpty) r += ' · $hora';
  }
  return r;
}

String f2(num? n) => (n ?? 0).toStringAsFixed(2);

String dosDigitos(int n) => n.toString().padLeft(2, '0');

/* Fecha local en formato yyyy-MM-dd (la app Ionic usaba toISOString, que
   en Ecuador después de las 19:00 ya daba el día siguiente). */
String fechaStr(DateTime d) => '${d.year}-${dosDigitos(d.month)}-${dosDigitos(d.day)}';

String hoyStr() => fechaStr(DateTime.now());

String inicioMesStr() {
  final d = DateTime.now();
  return fechaStr(DateTime(d.year, d.month, 1));
}

String haceDiasStr(int dias) => fechaStr(DateTime.now().subtract(Duration(days: dias)));

/* Los nombres de localidad traen "__" de relleno en la base. */
String limpiarLocalidad(String? s) => (s ?? '').replaceAll(RegExp(r'__+'), '').trim();
