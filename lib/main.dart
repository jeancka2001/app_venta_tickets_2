import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/nav.dart';
import 'core/prefs.dart';
import 'core/tema.dart';
import 'pages/dashboard_page.dart';
import 'pages/login_page.dart';
import 'services/app_lock.dart';
import 'services/staff_auth.dart';
import 'widgets/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await Prefs.init();
  /* Decide el bloqueo antes de mostrar cualquier pantalla. */
  AppLock.instance.init();
  runApp(const VentasApp());
}

class VentasApp extends StatelessWidget {
  const VentasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T-ickets Ventas',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: temaClaro(),
      darkTheme: temaOscuro(),
      themeMode: ThemeMode.system,
      locale: const Locale('es', 'EC'),
      supportedLocales: const [Locale('es', 'EC'), Locale('es'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: obtenerStaffData() != null ? const DashboardPage() : const LoginPage(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        /* Cada toque cuenta como actividad para el bloqueo por inactividad. */
        onPointerDown: (_) => AppLock.instance.marcarActividad(),
        child: Stack(children: [child!, const CapaBloqueo()]),
      ),
    );
  }
}
