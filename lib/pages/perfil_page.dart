import 'package:flutter/material.dart';

import '../core/nav.dart';
import '../core/tema.dart';
import '../services/app_lock.dart';
import '../services/biometric_auth.dart';
import '../services/bloqueo_sesion.dart';
import '../services/staff_auth.dart';
import '../widgets/comunes.dart';
import '../widgets/legal.dart';
import 'login_page.dart';

class PerfilPage extends StatelessWidget {
  const PerfilPage({super.key});

  Future<void> _cerrarSesion(BuildContext context) async {
    final ok = await confirmar(context,
        titulo: 'Cerrar sesión', mensaje: '¿Estás seguro de que deseas cerrar sesión?', si: 'Sí, salir');
    if (!ok) return;
    logoutStaff(renovable: false);
    /* Cerrar sesión también borra la huella guardada en este dispositivo --
       así el siguiente login siempre pide credenciales. */
    await eliminarCredencialesBiometricas();
    borrarConfigBloqueo();
    irComoRaiz(const LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    final staff = obtenerStaffData();
    final nombre = staff?.nombreVisible ?? 'Vendedor';
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';
    final lock = AppLock.instance;
    return Scaffold(
      appBar: AppBar(title: const TituloConLogo('Mi Perfil')),
      body: Contenido(children: [
        Column(children: [
          const SizedBox(height: 10),
          CircleAvatar(
            radius: 42,
            backgroundColor: C.azul,
            child: Text(inicial, style: const TextStyle(fontSize: 34, color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 12),
          Text(nombre, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: colorTexto(context))),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.account_circle_outlined, size: 16, color: colorTenue(context)),
            const SizedBox(width: 4),
            Text(staff?.perfil ?? '—', style: TextStyle(color: colorTenue(context))),
          ]),
        ]),
        Tarjeta(
          child: Column(children: [
            FilaDato('Usuario', staff?.username ?? '—'),
            FilaDato('Perfil', staff?.perfil ?? '—'),
          ]),
        ),
        ListenableBuilder(
          listenable: lock,
          builder: (context, _) => Tarjeta(
            padding: EdgeInsets.zero,
            onTap: lock.abrirConfig,
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(lock.modo == ModoBloqueo.huella ? 'Pedir huella después de' : 'Cerrar sesión después de',
                  style: TextStyle(fontSize: 13, color: colorTenue(context))),
              subtitle: Text(lock.config?.modo == lock.modo ? etiquetaBloqueo(lock.config) : 'Sin configurar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorTexto(context))),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
        BotonAccion('Cerrar Sesión',
            icono: Icons.logout, primario: true, color: C.rojo, onPressed: () => _cerrarSesion(context)),
        const Padding(padding: EdgeInsets.only(top: 6), child: EnlacesLegales()),
      ]),
    );
  }
}
