import 'dart:async';

import 'package:flutter/widgets.dart';

import 'bloqueo_sesion.dart';

/* Cada cuánto se revisa el tiempo sin uso con la app abierta, y cada cuánto
   como máximo se persiste un toque. */
const _intervaloChequeo = Duration(seconds: 15);
const _intervaloGuardarActividadMs = 5 * 1000;

enum _Pausa { normal, externa }

/* Bloqueo estilo banco según el tiempo que eligió el usuario (ver
   bloqueo_sesion.dart): con huella se bloquea la pantalla, sin huella se
   cierra la sesión. Equivale al AppLockContext de la app Ionic. */
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();
  static final instance = AppLock._();

  bool locked = false;
  /* El bloqueo es para renovar una sesión vencida (no por tiempo sin uso). */
  bool renovando = false;
  /* La sesión se cerró por tiempo sin uso (teléfonos sin huella). */
  bool sesionExpirada = false;
  ConfigBloqueo? config;
  ModoBloqueo modo = ModoBloqueo.sesion;
  bool _configManual = false;

  _Pausa? _pausa;
  int _ultimoGuardado = 0;
  Timer? _timer;

  /* Decisión síncrona al arrancar: si ya pasó el tiempo, se bloquea (o se
     cierra la sesión) antes de mostrar contenido. */
  void init() {
    if (sesionPorRenovar()) {
      locked = true;
      renovando = true;
    } else {
      final accion = evaluarBloqueo(MotivoBloqueo.inicio);
      if (accion == AccionBloqueo.expirar) cerrarSesionLocal();
      if (accion == AccionBloqueo.bloquear) locked = true;
    }
    config = leerConfigBloqueo();
    modo = modoDelDispositivo();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_intervaloChequeo, (_) {
      if (locked || hayOperacionExterna()) return;
      if (!_revisarRenovacion()) _aplicar(evaluarBloqueo(MotivoBloqueo.inactividad));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /* Cada toque en pantalla cuenta como actividad. */
  void marcarActividad() {
    if (locked || !haySesion()) return;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    if (ahora - _ultimoGuardado < _intervaloGuardarActividadMs) return;
    _ultimoGuardado = ahora;
    registrarActividad(ahora);
  }

  /* Vale en cualquier opción de tiempo (incluida "Nunca"): la sesión del
     servidor venció y solo la huella puede renovarla sin pedir contraseña. */
  bool _revisarRenovacion() {
    if (locked || !sesionPorRenovar()) return false;
    renovando = true;
    locked = true;
    notifyListeners();
    return true;
  }

  void _aplicar(AccionBloqueo accion) {
    if (accion == AccionBloqueo.bloquear) {
      locked = true;
      notifyListeners();
    }
    if (accion == AccionBloqueo.expirar) {
      cerrarSesionLocal();
      sesionExpirada = true;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (_pausa != null || locked || !haySesion()) return;
      if (hayOperacionExterna()) {
        _pausa = _Pausa.externa;
        return;
      }
      _pausa = _Pausa.normal;
      registrarActividad();
      /* "Al salir de la app": se bloquea ya, no al volver, para que la vista
         de apps recientes muestre la pantalla de bloqueo. */
      final c = configEfectiva();
      if (c?.modo == ModoBloqueo.huella && c?.minutos == 0) _aplicar(evaluarBloqueo(MotivoBloqueo.reanudar));
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final tipo = _pausa;
    _pausa = null;
    if (locked || _revisarRenovacion() || tipo == null) return;
    if (tipo == _Pausa.externa) {
      /* Volvió de la cámara/compartir: solo cuenta si se pasó del tiempo sin uso. */
      final accion = evaluarBloqueo(MotivoBloqueo.inactividad);
      if (accion == AccionBloqueo.nada) {
        registrarActividad();
      } else {
        _aplicar(accion);
      }
      return;
    }
    _aplicar(evaluarBloqueo(MotivoBloqueo.reanudar));
  }

  /* Con la app bloqueada, el botón atrás no debe navegar por debajo. */
  @override
  Future<bool> didPopRoute() async => locked;

  void unlock() {
    registrarActividad();
    locked = false;
    renovando = false;
    notifyListeners();
  }

  void confirmarExpiracion() {
    sesionExpirada = false;
    notifyListeners();
  }

  /* Llamar al terminar un login exitoso. */
  void sesionIniciada() {
    registrarActividad();
    locked = false;
    renovando = false;
    sesionExpirada = false;
    modo = modoDelDispositivo();
    config = leerConfigBloqueo();
    notifyListeners();
  }

  void guardarConfig(int? minutos) {
    final nueva = ConfigBloqueo(modoDelDispositivo(), minutos);
    guardarConfigBloqueo(nueva);
    registrarActividad();
    config = nueva;
    modo = nueva.modo;
    _configManual = false;
    notifyListeners();
  }

  /* Primera vez (o cambió el tipo de login: p.ej. activó la huella) -> se
     pide elegir. Nunca con la app bloqueada o sin sesión. */
  bool get configPendiente =>
      !locked && haySesion() && (_configManual || config == null || config!.modo != modo);

  void abrirConfig() {
    _configManual = true;
    notifyListeners();
  }

  void cerrarConfig() {
    _configManual = false;
    notifyListeners();
  }
}
