import '../core/api.dart';
import '../core/json.dart';
import 'staff_auth.dart';

/* CRUD de "tipos de descuento" por evento -- mismo backend que TicketsWeb,
   acotado a lo esencial. El link/QR público y el reporte de usos se siguen
   gestionando solo desde la web (sus campos se reenvían tal cual). */

class UsuarioAutorizado {
  final int idAdmin;
  final String nombre;
  UsuarioAutorizado(this.idAdmin, this.nombre);
}

class DescuentoEventoAdmin {
  final int id;
  final String nombre;
  final double porcentaje;
  final String? mensajeMotivo;
  final bool activo;
  final String aplicaSobre;
  final List<UsuarioAutorizado> usuarios;
  final int usosValidos;
  final String? fechaInicio;
  final String? fechaFin;
  final int? maxUsos;
  final int? usosPorCedula;

  DescuentoEventoAdmin(this.id, this.nombre, this.porcentaje, this.mensajeMotivo, this.activo, this.aplicaSobre,
      this.usuarios, this.usosValidos, this.fechaInicio, this.fechaFin, this.maxUsos, this.usosPorCedula);

  factory DescuentoEventoAdmin.fromJson(Map<String, dynamic> j) => DescuentoEventoAdmin(
        ent(j['id']),
        str(j['nombre']),
        dbl(j['porcentaje']),
        strN(j['mensaje_motivo']),
        truthy(j['activo']),
        j['aplica_sobre'] == 'base' ? 'base' : 'final',
        asMapList(j['usuarios']).map((u) => UsuarioAutorizado(ent(u['id_admin']), str(u['nombre']))).toList(),
        ent(j['usos_validos']),
        strN(j['fecha_inicio']),
        strN(j['fecha_fin']),
        entN(j['max_usos']),
        entN(j['usos_por_cedula']),
      );

  String get porcentajeTexto => porcentaje == porcentaje.roundToDouble() ? porcentaje.toStringAsFixed(0) : '$porcentaje';
}

Future<List<DescuentoEventoAdmin>> listarDescuentosEvento(String codigoEvento) async {
  try {
    final r = await dio.get('$urlBase/evento_descuentos',
        queryParameters: {'codigoEvento': codigoEvento}, options: hdr(staffAuthHeaders()));
    return asMapList(asMap(r.data)['data']).map(DescuentoEventoAdmin.fromJson).toList();
  } catch (_) {
    return [];
  }
}

Future<({bool success, String? message})> guardarDescuentoEvento(Map<String, dynamic> payload) async {
  try {
    final r = await dio.post('$urlBase/evento_descuentos', data: payload, options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return (success: data['success'] == true, message: strN(data['message']));
  } catch (e) {
    final s = statusDe(e);
    return (
      success: false,
      message: (s == 401 || s == 403)
          ? 'Tu sesión expiró o no tienes permiso para gestionar los descuentos de este evento.'
          : 'Error de conexión al guardar el descuento.',
    );
  }
}

Future<({bool success, String? message})> eliminarDescuentoEvento(int id) async {
  try {
    final r = await dio.post('$urlBase/evento_descuentos/eliminar', data: {'id': id}, options: hdr(staffAuthHeaders()));
    final data = asMap(r.data);
    return (success: data['success'] == true, message: strN(data['message']));
  } catch (_) {
    return (success: false, message: 'Error de conexión al eliminar el descuento.');
  }
}

class UsuarioParaAutorizar {
  final int id;
  final String nombre;
  final String username;
  final String perfil;
  UsuarioParaAutorizar(this.id, this.nombre, this.username, this.perfil);
}

Future<List<UsuarioParaAutorizar>> listarUsuariosParaAutorizar() async {
  try {
    final r = await dio.get('$urlBase/listas_user', options: hdr(staffAuthHeaders()));
    return asMapList(asMap(r.data)['users']).map((u) {
      final id = ent(u['id']);
      final nombre = str(u['name']).isNotEmpty ? str(u['name']) : (str(u['username']).isNotEmpty ? str(u['username']) : '#$id');
      return UsuarioParaAutorizar(id, nombre, str(u['username']), str(u['perfil']));
    }).toList();
  } catch (_) {
    return [];
  }
}
