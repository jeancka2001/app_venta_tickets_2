import 'dart:convert';

import '../core/api.dart';
import '../core/json.dart';
import '../core/prefs.dart';
import 'biometric_auth.dart';

/* Login de personal (vendedores/admin/suscriptores-revendedores) -- es un
   login DISTINTO al de clientes de app_tickets: pega contra /auth_admin
   (tabla `admin`), no /auth_suscriptor. Misma cuenta que ya usan para
   entrar al panel web. */

const _storageKey = 'staffToken';

/* La sesión venció sola (JWT de 1 h) en un teléfono con login por huella:
   en vez de mandar al login, se pide la huella una vez y se renueva el
   token con las credenciales guardadas (ver LockScreen). */
const _keyPorRenovar = 'staffPorRenovar';

/* Se bloquea un poco antes de que venza el token, para renovarlo sin que
   ninguna pantalla llegue a recibir el 401. */
const _margenRenovacionMs = 2 * 60 * 1000;

/* Perfiles que pueden vender (mismo permiso[] que /Vender-Tickets en la web). */
const perfilesVenta = ['admin', 'super_admin', 'vendedores', 'vendedor_secundario', 'suscriptores'];

class StaffData {
  final int id;
  final String? name;
  final String? username;
  final String perfil;
  /* Segundos epoch -- lo agrega jwt.sign() por tener expiresIn:'1h'. */
  final int? exp;

  StaffData({required this.id, this.name, this.username, required this.perfil, this.exp});

  factory StaffData.fromJson(Map<String, dynamic> j) => StaffData(
        id: ent(j['id']),
        name: strN(j['name']),
        username: strN(j['username']),
        perfil: str(j['perfil']),
        exp: entN(j['exp']),
      );

  String get nombreVisible => name ?? username ?? 'Vendedor';
}

/* Decodifica el payload de un JWT sin verificar firma -- solo para leer
   claims (perfil, id, name) en el cliente. */
StaffData? decodificarJWT(String token) {
  try {
    final partes = token.split('.');
    if (partes.length < 2) return null;
    final json = utf8.decode(base64Url.decode(base64Url.normalize(partes[1])));
    return StaffData.fromJson(asMap(jsonDecode(json)));
  } catch (_) {
    return null;
  }
}

class ResultadoLogin {
  final bool success;
  final StaffData? data;
  final String? message;
  final bool sinConexion;
  ResultadoLogin({required this.success, this.data, this.message, this.sinConexion = false});
}

Future<ResultadoLogin> loginStaff(String username, String password) async {
  try {
    final r = await dio.post('$urlBase/auth_admin',
        data: {'username': username, 'password': password}, options: hdr(apiHdr()));
    final data = asMap(r.data);
    final token = strN(data['token']);
    if (data['success'] == true && token != null) {
      final staff = decodificarJWT(token);
      if (staff == null) return ResultadoLogin(success: false, message: 'No se pudo leer la sesión.');
      Prefs.set(_storageKey, token);
      Prefs.remove(_keyPorRenovar);
      return ResultadoLogin(success: true, data: staff);
    }
    return ResultadoLogin(success: false, message: strN(data['message']) ?? 'Usuario o contraseña incorrectos.');
  } catch (e) {
    /* El servidor respondió (401/400 con mensaje): credenciales rechazadas,
       no es falta de conexión. */
    final msg = mensajeBackend(e);
    if (statusDe(e) != null) {
      return ResultadoLogin(success: false, message: msg ?? 'Usuario o contraseña incorrectos.');
    }
    return ResultadoLogin(
      success: false,
      sinConexion: true,
      message: 'Error de conexión. Verifica tu internet e intenta de nuevo.',
    );
  }
}

/* El JWT dura 1h: un token vencido que se siguiera mandando haría que el
   backend tratara la llamada como ANÓNIMA y dejara de aplicar las
   restricciones por usuario (eventos_asignados, usuario_metodos_pago). */
bool _staffVencido(StaffData? staff) {
  final exp = staff?.exp;
  return exp != null && DateTime.now().millisecondsSinceEpoch >= exp * 1000;
}

StaffData? obtenerStaffData() {
  final token = Prefs.get(_storageKey);
  if (token == null) return null;
  final staff = decodificarJWT(token);
  if (staff != null && _staffVencido(staff)) {
    logoutStaff();
    return null;
  }
  return staff;
}

String? obtenerStaffToken() => obtenerStaffData() != null ? Prefs.get(_storageKey) : null;

/* Cabeceras para llamadas a ms_login que el backend filtra por usuario:
   llevan el JWT de sesión del propio vendedor, no el token de servicio
   (ese es de acceso global). */
Map<String, String> staffAuthHeaders() {
  final token = obtenerStaffToken();
  return {
    ...msLoginAuthHeaders,
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

Map<String, String> staffJsonHeaders() => {...staffAuthHeaders(), 'Content-Type': 'application/json'};

/* renovable=true (por defecto): la sesión se cae por vencimiento/401 -- si
   hay huella guardada, se ofrece renovarla con la huella.
   renovable=false: el usuario cerró sesión a propósito. */
void logoutStaff({bool renovable = true}) {
  final habiaSesion = Prefs.get(_storageKey) != null;
  Prefs.remove(_storageKey);
  if (!renovable) {
    Prefs.remove(_keyPorRenovar);
  } else if (habiaSesion && biometriaActivaLocalmente()) {
    Prefs.set(_keyPorRenovar, '1');
  }
}

/* Hay que pedir la huella para renovar: ya venció, o está por vencer. */
bool sesionStaffPorRenovar() {
  if (!biometriaActivaLocalmente()) return false;
  if (Prefs.get(_keyPorRenovar) == '1') return true;
  final token = Prefs.get(_storageKey);
  final exp = token != null ? decodificarJWT(token)?.exp : null;
  return exp != null && exp * 1000 - DateTime.now().millisecondsSinceEpoch < _margenRenovacionMs;
}

bool puedeVender(String? perfil) => perfil != null && perfilesVenta.contains(perfil);

/* Mismo criterio que GLOBAL_PROFILES en el backend. */
bool esAdmin(String? perfil) => perfil == 'admin' || perfil == 'super_admin';
