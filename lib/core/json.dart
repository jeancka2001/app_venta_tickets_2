/* Lectura tolerante de JSON del backend: los campos llegan a veces como
   número y a veces como texto ("12.50"), o vienen null. */

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? v.map((k, e) => MapEntry(k.toString(), e)) : <String, dynamic>{};

List<dynamic> asList(dynamic v) => v is List ? v : const [];

List<Map<String, dynamic>> asMapList(dynamic v) => asList(v).map(asMap).toList();

String str(dynamic v, [String def = '']) => v == null ? def : v.toString();

String? strN(dynamic v) => v?.toString();

/* Equivalente a parseFloat(): "12.5abc" -> 12.5, basura -> 0. */
double dbl(dynamic v) {
  if (v is num) return v.toDouble();
  final s = str(v).trim();
  final d = double.tryParse(s);
  if (d != null) return d;
  final m = RegExp(r'^-?\d+(\.\d+)?').firstMatch(s);
  return m != null ? double.parse(m.group(0)!) : 0;
}

double? dblN(dynamic v) => v == null ? null : dbl(v);

int ent(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = str(v).trim();
  return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
}

int? entN(dynamic v) => v == null ? null : ent(v);

/* Truthy al estilo JS (para banderas como `success`, `estado`). */
bool truthy(dynamic v) => v != null && v != false && v != 0 && v != '' && v != '0';
