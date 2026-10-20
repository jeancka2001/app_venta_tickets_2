import '../core/api.dart';
import '../core/json.dart';
import 'staff_auth.dart';

/* ── Reporte de ventas por usuario (mismo endpoint que "Reporte por
   Usuario" en la web) ── */

class BucketVentas {
  final int compras;
  final int boletos;
  final double monto;
  final double comision;
  BucketVentas(this.compras, this.boletos, this.monto, this.comision);
  factory BucketVentas.fromJson(dynamic v) {
    final j = asMap(v);
    return BucketVentas(ent(j['compras']), ent(j['boletos']), dbl(j['monto']), dbl(j['comision']));
  }
}

class Agregado {
  final String nombre;
  final int compras;
  final int boletos;
  final double monto;
  Agregado(this.nombre, this.compras, this.boletos, this.monto);
}

class UsuarioAgg {
  final int? id;
  final String nombre;
  final String? perfil;
  final BucketVentas pagado;
  final BucketVentas pendiente;
  final BucketVentas comprobar;
  final BucketVentas expirado;
  final List<Agregado> eventos;
  final List<Agregado> formasPago;

  UsuarioAgg(this.id, this.nombre, this.perfil, this.pagado, this.pendiente, this.comprobar, this.expirado,
      this.eventos, this.formasPago);

  factory UsuarioAgg.fromJson(dynamic v) {
    final j = asMap(v);
    return UsuarioAgg(
      entN(j['id']),
      str(j['nombre']),
      strN(j['perfil']),
      BucketVentas.fromJson(j['pagado']),
      BucketVentas.fromJson(j['pendiente']),
      BucketVentas.fromJson(j['comprobar']),
      BucketVentas.fromJson(j['expirado']),
      asMapList(j['eventos'])
          .map((e) => Agregado(str(e['evento']), ent(e['compras']), ent(e['boletos']), dbl(e['monto'])))
          .toList(),
      asMapList(j['formas_pago'])
          .map((e) => Agregado(str(e['forma']), ent(e['compras']), ent(e['boletos']), dbl(e['monto'])))
          .toList(),
    );
  }
}

class ReporteVentas {
  final bool success;
  final String? message;
  final List<UsuarioAgg> operadores;
  final UsuarioAgg? autogestion;
  ReporteVentas(this.success, this.message, this.operadores, this.autogestion);
}

Future<ReporteVentas> obtenerReporteVentas(String fechaInit, String fechaFin) async {
  final r = await dio.post('$urlBase/reporte_ventas_usuario',
      queryParameters: {'fecha_init': fechaInit, 'fecha_fin': fechaFin}, data: {}, options: hdr(apiHdr()));
  final data = asMap(r.data);
  final auto = asMap(data['autogestion'])['resumen'];
  return ReporteVentas(
    data['success'] == true,
    strN(data['message']),
    asList(data['operadores']).map(UsuarioAgg.fromJson).toList(),
    auto != null ? UsuarioAgg.fromJson(auto) : null,
  );
}

/* ── Comisiones de vendedores (nivel 1 / nivel 2) -- el backend ya filtra
   por quién pregunta: admin recibe todo; cualquier otro perfil, solo su fila. ── */

class Nivel2Resumen {
  final int id;
  final String name;
  final double ventas;
  final int cantidadVentas;
  final double? comisionPorcentaje;
  final double comisionDirecta;
  final double? comisionNivel1Porcentaje;
  final double comisionGeneradaNivel1;
  Nivel2Resumen(this.id, this.name, this.ventas, this.cantidadVentas, this.comisionPorcentaje, this.comisionDirecta,
      this.comisionNivel1Porcentaje, this.comisionGeneradaNivel1);
}

class FilaComision {
  final int id;
  final String name;
  final String perfil;
  final int? idNivel1;
  final double? comisionPorcentaje;
  final double ventasPropias;
  final int cantidadVentasPropias;
  final double comisionDirecta;
  final List<Nivel2Resumen> nivel2;
  final double comisionNivel1Total;
  final double comisionTotal;

  FilaComision(this.id, this.name, this.perfil, this.idNivel1, this.comisionPorcentaje, this.ventasPropias,
      this.cantidadVentasPropias, this.comisionDirecta, this.nivel2, this.comisionNivel1Total, this.comisionTotal);

  factory FilaComision.fromJson(Map<String, dynamic> j) => FilaComision(
        ent(j['id']),
        str(j['name']),
        str(j['perfil']),
        entN(j['id_nivel1']),
        dblN(j['comision_porcentaje']),
        dbl(j['ventas_propias']),
        ent(j['cantidad_ventas_propias']),
        dbl(j['comision_directa']),
        asMapList(j['nivel2'])
            .map((n) => Nivel2Resumen(
                  ent(n['id']),
                  str(n['name']),
                  dbl(n['ventas']),
                  ent(n['cantidad_ventas']),
                  dblN(n['comision_porcentaje']),
                  dbl(n['comision_directa']),
                  dblN(n['comision_nivel1_porcentaje']),
                  dbl(n['comision_generada_nivel1']),
                ))
            .toList(),
        dbl(j['comision_nivel1_total']),
        dbl(j['comision_total']),
      );
}

class ReporteComisiones {
  final bool success;
  final String? message;
  final bool sesionExpirada;
  final List<FilaComision> data;
  ReporteComisiones(this.success, this.message, this.sesionExpirada, this.data);
}

Future<ReporteComisiones> obtenerReporteComisiones(String? fechaInit, String? fechaFin) async {
  try {
    final r = await dio.get('$urlBase/reporte_comisiones_vendedores',
        queryParameters: {'fecha_init': ?fechaInit, 'fecha_fin': ?fechaFin}, options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return ReporteComisiones(data['success'] == true, strN(data['message']), data['sesion_expirada'] == true,
        asMapList(data['data']).map(FilaComision.fromJson).toList());
  } catch (e) {
    final s = statusDe(e);
    return ReporteComisiones(
        false, s == 401 ? 'Tu sesión expiró.' : 'Error de conexión al generar el reporte.', s == 401, []);
  }
}

String pct(double? n) {
  if (n == null) return '—';
  return n == n.roundToDouble() ? '${n.toStringAsFixed(0)}%' : '$n%';
}
