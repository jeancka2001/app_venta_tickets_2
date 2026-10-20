import 'package:flutter/material.dart';

import '../core/nav.dart';
import '../core/tema.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../services/app_lock.dart';
import '../services/biometric_auth.dart';
import '../services/bloqueo_sesion.dart';
import '../services/staff_auth.dart';
import 'comunes.dart';

/* Pantalla de bloqueo que se dibuja ENCIMA de toda la app. El JWT de
   personal dura solo 1 h, así que al desbloquear con huella se vuelve a
   hacer login con las credenciales guardadas para renovar el token. Por eso
   también aparece (renovando=true) cuando el token vence o está por vencer. */
class CapaBloqueo extends StatefulWidget {
  const CapaBloqueo({super.key});

  @override
  State<CapaBloqueo> createState() => _CapaBloqueoState();
}

class _CapaBloqueoState extends State<CapaBloqueo> {
  final _lock = AppLock.instance;
  bool _verificando = false;
  bool _intentadoAuto = false;
  bool _estabaBloqueado = false;

  @override
  void initState() {
    super.initState();
    _lock.addListener(_alCambiar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _alCambiar());
  }

  @override
  void dispose() {
    _lock.removeListener(_alCambiar);
    super.dispose();
  }

  void _alCambiar() {
    if (!mounted) return;
    /* Teléfonos sin huella: pasó el tiempo elegido y se cerró la sesión. */
    if (_lock.sesionExpirada) {
      _lock.confirmarExpiracion();
      _irAlLogin('Tu sesión se cerró por inactividad. Vuelve a iniciar sesión.');
      return;
    }
    if (_lock.locked && !_estabaBloqueado) {
      _estabaBloqueado = true;
      if (!_intentadoAuto) {
        _intentadoAuto = true;
        /* Pequeña espera: al volver de segundo plano el sensor a veces aún no
           está listo y el primer intento falla solo. */
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _lock.locked) _intentarHuella();
        });
      }
    }
    if (!_lock.locked) {
      _estabaBloqueado = false;
      _intentadoAuto = false;
    }
    setState(() {});
  }

  void _irAlLogin([String mensaje = '']) {
    cerrarSesionLocal();
    _lock.unlock();
    irComoRaiz(const LoginPage());
    if (mensaje.isNotEmpty) toast(mensaje);
  }

  Future<void> _intentarHuella() async {
    if (_verificando) return;
    setState(() => _verificando = true);
    try {
      final creds = await obtenerCredencialesBiometricas();
      if (creds == null) return;
      final r = await loginStaff(creds.usuario, creds.contrasena);
      if (r.success && r.data != null && puedeVender(r.data!.perfil)) {
        final enLogin = !haySesionEnPantalla;
        _lock.unlock();
        /* Si el token ya se había caído, las pantallas mandaron al login por
           debajo del bloqueo: se vuelve al panel. */
        if (enLogin) irComoRaiz(const DashboardPage());
      } else if (r.sinConexion) {
        /* Sin conexión: si el token aún sirve, la huella ya confirmó identidad. */
        if (!_lock.renovando && obtenerStaffData() != null) {
          _lock.unlock();
        } else {
          toast('Sin conexión. Revisa tu internet e inténtalo de nuevo.');
        }
      } else {
        /* El servidor rechazó las credenciales guardadas (contraseña cambiada). */
        _irAlLogin('No se pudo renovar tu sesión. Inicia sesión con tu usuario y contraseña.');
      }
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_lock.locked) return const SizedBox.shrink();
    final renovando = _lock.renovando;
    return Positioned.fill(
      child: Material(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [C.azulOscuro, C.azulMedio, C.azul],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset(logoAsset, width: 150),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.lock_outline, size: 46, color: colorAcento(context)),
                        const SizedBox(height: 10),
                        Text(renovando ? 'Tu sesión venció' : 'Sesión bloqueada',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colorTexto(context))),
                        const SizedBox(height: 6),
                        Text(
                          renovando ? 'Confirma con tu huella para seguir trabajando' : 'Usa tu huella para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colorTenue(context)),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: BotonAccion(
                            _verificando ? 'Verificando…' : 'Ingresar con huella',
                            icono: Icons.fingerprint,
                            primario: true,
                            cargando: _verificando,
                            onPressed: _intentarHuella,
                          ),
                        ),
                        const SizedBox(height: 8),
                        /* Cierra la sesión (no solo oculta el bloqueo). La huella queda guardada. */
                        TextButton(onPressed: () => _irAlLogin(), child: const Text('Usar usuario y contraseña')),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* true si debajo del bloqueo hay una pantalla con sesión (no el login). */
bool get haySesionEnPantalla => !rutaLoginActiva;

bool rutaLoginActiva = false;
