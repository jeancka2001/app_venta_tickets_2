import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/prefs.dart';
import 'bloqueo_sesion.dart';

/* Login con huella / Face ID: usuario y contraseña se guardan en el
   almacenamiento seguro del sistema (Android Keystore / iOS Keychain) y
   solo se leen después de que el usuario se autentica con biometría. */

const _keyUsuario = 'ventas_bio_usuario';
const _keyContrasena = 'ventas_bio_contrasena';

const _storage = FlutterSecureStorage();
final _auth = LocalAuthentication();

/* Bandera NO sensible (solo un "sí/no") para saber sincrónicamente si hay
   que bloquear la app al pasar a segundo plano/reanudar. */
const _flagBiometriaActiva = 'biometriaActiva';

bool biometriaActivaLocalmente() => Prefs.get(_flagBiometriaActiva) == '1';

/* Si este dispositivo ya demostró que no puede guardar credenciales seguras,
   se deja de insistir en cada login. */
const _flagGuardadoNoSoportado = 'biometriaGuardadoNoSoportado';

bool guardadoBiometricoNoSoportado() => Prefs.get(_flagGuardadoNoSoportado) == '1';

Future<bool> biometriaDisponible() async {
  try {
    if (!await _auth.canCheckBiometrics) return false;
    final tipos = await _auth.getAvailableBiometrics();
    return tipos.isNotEmpty;
  } catch (e) {
    debugPrint('[biometria] disponible falló: $e');
    return false;
  }
}

Future<bool> hayCredencialesGuardadas() async {
  try {
    return await _storage.containsKey(key: _keyUsuario) && await _storage.containsKey(key: _keyContrasena);
  } catch (e) {
    debugPrint('[biometria] hayCredencialesGuardadas falló: $e');
    return false;
  }
}

class ResultadoGuardadoBiometrico {
  final bool ok;
  /* Mensaje listo para mostrarle al usuario. Vacío si no aplica. */
  final String mensaje;
  const ResultadoGuardadoBiometrico(this.ok, this.mensaje);
}

Future<ResultadoGuardadoBiometrico> guardarCredencialesBiometricas(String usuario, String contrasena) async {
  try {
    await _storage.write(key: _keyUsuario, value: usuario);
    await _storage.write(key: _keyContrasena, value: contrasena);
    Prefs.set(_flagBiometriaActiva, '1');
    return const ResultadoGuardadoBiometrico(true, '');
  } catch (e) {
    debugPrint('[biometria] guardar falló: $e');
    Prefs.set(_flagGuardadoNoSoportado, '1');
    return const ResultadoGuardadoBiometrico(
      false,
      'No se pudo activar el inicio de sesión con huella en este dispositivo. Puedes seguir entrando con usuario y contraseña.',
    );
  }
}

Future<void> eliminarCredencialesBiometricas() async {
  Prefs.remove(_flagBiometriaActiva);
  Prefs.remove(_flagGuardadoNoSoportado);
  try {
    await _storage.delete(key: _keyUsuario);
    await _storage.delete(key: _keyContrasena);
  } catch (e) {
    debugPrint('[biometria] eliminar falló: $e');
  }
}

class CredencialesGuardadas {
  final String usuario;
  final String contrasena;
  CredencialesGuardadas(this.usuario, this.contrasena);
}

/* Muestra el diálogo de huella y, si el usuario se autentica, devuelve las
   credenciales guardadas. null si cancela, falla o no hay nada guardado. */
Future<CredencialesGuardadas?> obtenerCredencialesBiometricas() async {
  try {
    /* sinBloqueo: el diálogo del sistema no cuenta como salir de la app. */
    final ok = await sinBloqueo(() => _auth.authenticate(
          localizedReason: 'Inicia sesión en T-ickets Ventas',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        ));
    if (!ok) return null;
    final u = await _storage.read(key: _keyUsuario);
    final c = await _storage.read(key: _keyContrasena);
    if (u == null || c == null) return null;
    return CredencialesGuardadas(u, c);
  } catch (e) {
    debugPrint('[biometria] autenticar falló/cancelado: $e');
    return null;
  }
}
