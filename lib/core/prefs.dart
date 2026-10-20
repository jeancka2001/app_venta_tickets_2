import 'package:shared_preferences/shared_preferences.dart';

/* Reemplazo de localStorage: SharedPreferences mantiene los valores en
   memoria, así que las lecturas son síncronas (igual que en la app Ionic,
   donde el bloqueo se decidía en el primer render). */
class Prefs {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static String? get(String key) => _p.getString(key);

  static void set(String key, String value) => _p.setString(key, value);

  static void remove(String key) => _p.remove(key);
}
