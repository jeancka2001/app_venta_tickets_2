import 'dart:convert';

import '../core/prefs.dart';
import 'biometric_auth.dart';
import 'staff_auth.dart';

/* ── Bloqueo / cierre de sesión por tiempo sin uso ──
   Cada usuario elige cuánto tiempo puede estar la app cerrada o sin tocarse
   antes de volver a pedir acceso:
   - "huella": teléfonos donde se guardó el login con huella -> se bloquea y
     se desbloquea con la huella (la sesión sigue viva).
   - "sesion": teléfonos sin huella -> se cierra la sesión y se vuelve a
     entrar con usuario y contraseña. */

enum ModoBloqueo { huella, sesion }

class ConfigBloqueo {
  final ModoBloqueo modo;
  /* null = nunca. (0 = al salir de la app: solo sesiones antiguas sin config.) */
  final int? minutos;
  const ConfigBloqueo(this.modo, this.minutos);
}

class OpcionBloqueo {
  final int? minutos;
  final String etiqueta;
  const OpcionBloqueo(this.minutos, this.etiqueta);
}

const opcionesBloqueo = <OpcionBloqueo>[
  OpcionBloqueo(2, '2 minutos'),
  OpcionBloqueo(5, '5 minutos'),
  OpcionBloqueo(15, '15 minutos'),
  OpcionBloqueo(30, '30 minutos'),
  OpcionBloqueo(60, '1 hora'),
  OpcionBloqueo(null, 'Nunca (hasta cerrar sesión)'),
];

int? minutosPorDefecto(ModoBloqueo modo) => modo == ModoBloqueo.huella ? 2 : null;

String etiquetaBloqueo(ConfigBloqueo? config) {
  if (config == null) return 'Sin configurar';
  for (final o in opcionesBloqueo) {
    if (o.minutos == config.minutos) return o.etiqueta;
  }
  return 'Sin configurar';
}

bool haySesion() => obtenerStaffData() != null;
void cerrarSesionLocal() => logoutStaff(renovable: false);

bool sesionPorRenovar() => sesionStaffPorRenovar();

/* Si el teléfono tiene login con huella guardado, el bloqueo es con huella;
   si no, es por cierre de sesión. */
ModoBloqueo modoDelDispositivo() => biometriaActivaLocalmente() ? ModoBloqueo.huella : ModoBloqueo.sesion;

const _keyConfig = 'configBloqueo';
const _keyActividad = 'ultimaActividad';

ConfigBloqueo? leerConfigBloqueo() {
  try {
    final raw = Prefs.get(_keyConfig);
    if (raw == null) return null;
    final c = jsonDecode(raw);
    if (c is! Map) return null;
    final modo = c['modo'] == 'huella'
        ? ModoBloqueo.huella
        : c['modo'] == 'sesion'
            ? ModoBloqueo.sesion
            : null;
    final minutos = c['minutos'];
    if (modo == null || (minutos != null && minutos is! num)) return null;
    return ConfigBloqueo(modo, (minutos as num?)?.toInt());
  } catch (_) {
    return null;
  }
}

void guardarConfigBloqueo(ConfigBloqueo config) =>
    Prefs.set(_keyConfig, jsonEncode({'modo': config.modo.name, 'minutos': config.minutos}));

void borrarConfigBloqueo() {
  Prefs.remove(_keyConfig);
  Prefs.remove(_keyActividad);
}

void registrarActividad([int? ts]) =>
    Prefs.set(_keyActividad, (ts ?? DateTime.now().millisecondsSinceEpoch).toString());

int? _ultimaActividad() {
  final n = int.tryParse(Prefs.get(_keyActividad) ?? '');
  return (n != null && n > 0) ? n : null;
}

/* Sesiones con huella de antes de que existiera esta opción siguen
   bloqueándose al salir. */
ConfigBloqueo? configEfectiva() =>
    leerConfigBloqueo() ?? (biometriaActivaLocalmente() ? const ConfigBloqueo(ModoBloqueo.huella, 0) : null);

enum AccionBloqueo { nada, bloquear, expirar }

enum MotivoBloqueo { inicio, reanudar, inactividad }

AccionBloqueo evaluarBloqueo(MotivoBloqueo motivo) {
  if (!haySesion()) return AccionBloqueo.nada;
  final config = configEfectiva();
  if (config == null || config.minutos == null) return AccionBloqueo.nada;
  if (motivo == MotivoBloqueo.inactividad && config.minutos == 0) return AccionBloqueo.nada;

  final ultima = _ultimaActividad();
  final transcurrido = ultima == null ? double.infinity : DateTime.now().millisecondsSinceEpoch - ultima;
  if (transcurrido < config.minutos! * 60 * 1000) return AccionBloqueo.nada;

  /* Config de huella pero ya no hay login con huella guardado: no hay forma
     de desbloquear, así que se cierra la sesión. */
  if (config.modo == ModoBloqueo.huella && biometriaActivaLocalmente()) return AccionBloqueo.bloquear;
  return AccionBloqueo.expirar;
}

/* Operaciones que abren otra pantalla del sistema (cámara de fotos, hoja de
   compartir, diálogo de huella…) mandan la app a segundo plano sin que el
   usuario haya "salido". Mientras dure una, el regreso no cuenta como salida. */
int _operacionesExternas = 0;

bool hayOperacionExterna() => _operacionesExternas > 0;

Future<T> sinBloqueo<T>(Future<T> Function() fn) async {
  _operacionesExternas++;
  try {
    return await fn();
  } finally {
    _operacionesExternas--;
    registrarActividad();
  }
}
