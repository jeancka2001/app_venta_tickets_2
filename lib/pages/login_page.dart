import 'package:flutter/material.dart';

import '../core/nav.dart';
import '../core/tema.dart';
import '../services/app_lock.dart';
import '../services/biometric_auth.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/legal.dart';
import '../widgets/lock_screen.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usuario = TextEditingController();
  final _contrasena = TextEditingController();
  bool _guardarSesion = true;
  bool _cargando = false;
  bool _verContrasena = false;

  /* ── Huella digital ── Nada automático: la huella solo se pide si el
     vendedor toca el botón "Huella" o si guarda una nueva sesión. */
  bool _biometriaLista = false;
  bool _verificandoHuella = false;

  @override
  void initState() {
    super.initState();
    rutaLoginActiva = true;
    _revisarHuella();
  }

  @override
  void dispose() {
    rutaLoginActiva = false;
    _usuario.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  /* Solo determina si mostrar el botón "Huella". */
  Future<void> _revisarHuella() async {
    final disponible = await biometriaDisponible();
    final guardado = disponible && await hayCredencialesGuardadas();
    if (mounted) setState(() => _biometriaLista = guardado);
  }

  void _finalizarLogin([int esperarMs = 0]) {
    AppLock.instance.sesionIniciada();
    if (esperarMs > 0) {
      Future.delayed(Duration(milliseconds: esperarMs), () => irComoRaiz(const DashboardPage()));
    } else {
      irComoRaiz(const DashboardPage());
    }
  }

  Future<void> _loginConCredenciales(String usuario, String contrasena, bool guardar) async {
    setState(() => _cargando = true);
    try {
      final r = await loginStaff(usuario, contrasena);
      if (!r.success || r.data == null) {
        toast(r.message ?? 'No se pudo iniciar sesión.', color: C.rojo);
        return;
      }
      if (!puedeVender(r.data!.perfil)) {
        toast('Esta cuenta no tiene permiso para vender entradas.', color: C.rojo);
        return;
      }

      /* Solo se intenta guardar con huella si el teléfono realmente la tiene. */
      if (guardar && !guardadoBiometricoNoSoportado() && await biometriaDisponible()) {
        if (await hayCredencialesGuardadas()) {
          /* Ya hay una cuenta con huella en este teléfono -- no se sobreescribe
             sin preguntar (podría ser la de otro vendedor). */
          if (!mounted) return;
          await _preguntarReemplazo(usuario, contrasena);
          return;
        }
        final res = await guardarCredencialesBiometricas(usuario, contrasena);
        if (!res.ok && res.mensaje.isNotEmpty) {
          toast(res.mensaje, color: C.naranja);
          _finalizarLogin(2600);
          return;
        }
      }
      _finalizarLogin();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _preguntarReemplazo(String usuario, String contrasena) async {
    final reemplazar = await confirmar(
      context,
      titulo: '¿Reemplazar sesión guardada?',
      mensaje:
          'Ya hay una cuenta guardada con huella en este dispositivo. Si continúas, se reemplazará por esta cuenta.',
      si: 'Sí, reemplazar',
      no: 'No, mantener la anterior',
      peligro: true,
    );
    if (!reemplazar) {
      _finalizarLogin();
      return;
    }
    final res = await guardarCredencialesBiometricas(usuario, contrasena);
    if (!res.ok && res.mensaje.isNotEmpty) {
      toast(res.mensaje, color: C.naranja);
      _finalizarLogin(2600);
    } else {
      _finalizarLogin();
    }
  }

  void _iniciarSesion() {
    FocusScope.of(context).unfocus();
    if (_usuario.text.isEmpty || _contrasena.text.isEmpty) {
      toast('Ingresa tu usuario y contraseña', color: C.rojo);
      return;
    }
    _loginConCredenciales(_usuario.text.trim(), _contrasena.text, _guardarSesion);
  }

  Future<void> _ingresarConHuella() async {
    setState(() => _verificandoHuella = true);
    try {
      final creds = await obtenerCredencialesBiometricas();
      /* guardar=false: estas credenciales ya vienen del almacenamiento seguro. */
      if (creds != null) await _loginConCredenciales(creds.usuario, creds.contrasena, false);
    } finally {
      if (mounted) setState(() => _verificandoHuella = false);
    }
  }

  Widget _botonCuadrado({
    required IconData icono,
    required String texto,
    required VoidCallback? onTap,
    required bool primario,
    bool cargando = false,
  }) {
    final color = primario ? Colors.white : C.azul;
    return Expanded(
      child: SizedBox(
        height: 84,
        child: primario
            ? FilledButton(onPressed: onTap, child: _contenidoCuadrado(icono, texto, color, cargando))
            : OutlinedButton(onPressed: onTap, child: _contenidoCuadrado(icono, texto, color, cargando)),
      ),
    );
  }

  Widget _contenidoCuadrado(IconData icono, String texto, Color color, bool cargando) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      cargando ? MiniSpinner(color: color) : Icon(icono, size: 26),
      const SizedBox(height: 6),
      Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    Image.asset(logoAsset, width: 180),
                    const SizedBox(height: 12),
                    const Text(
                      'PANEL DE VENTAS',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 32),
                    Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      elevation: 12,
                      shadowColor: Colors.black54,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Iniciar Sesión',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: colorTexto(context)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Acceso de personal de venta',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: colorTenue(context)),
                              ),
                              const SizedBox(height: 22),
                              TextField(
                                controller: _usuario,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                decoration: const InputDecoration(labelText: 'Usuario'),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _contrasena,
                                obscureText: !_verContrasena,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _iniciarSesion(),
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  suffixIcon: IconButton(
                                    icon: Icon(_verContrasena ? Icons.visibility_off : Icons.visibility),
                                    onPressed: () => setState(() => _verContrasena = !_verContrasena),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              CheckboxListTile(
                                value: _guardarSesion,
                                onChanged: (v) => setState(() => _guardarSesion = v ?? false),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity: ListTileControlAffinity.leading,
                                dense: true,
                                title: const Text('Recordar acceso en este dispositivo'),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (_biometriaLista) ...[
                                    _botonCuadrado(
                                      icono: Icons.fingerprint,
                                      texto: _verificandoHuella ? 'Verificando…' : 'Huella',
                                      primario: false,
                                      cargando: _verificandoHuella,
                                      onTap: (_verificandoHuella || _cargando) ? null : _ingresarConHuella,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  _botonCuadrado(
                                    icono: Icons.login,
                                    texto: _cargando ? 'Ingresando…' : 'Iniciar Sesión',
                                    primario: true,
                                    onTap: _cargando ? null : _iniciarSesion,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const EnlacesLegales(claro: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
