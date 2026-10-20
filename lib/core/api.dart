import 'package:dio/dio.dart';

/* URLs del backend -- las mismas que usaba la app Ionic (APP_VENTA_TICKETS). */
const urlMsLogin = 'https://api.t-ickets.com/ms_login';
const urlBase = '$urlMsLogin/api/v1';
const urlMikroti = 'https://api.t-ickets.com/mikroti';
const urlMikrotiV2 = 'https://api.t-ickets.com/mikrotiv2';
const urlUploadImg = 'https://codigomarret.online/upload/api/img';
const urlOcrComprobante = '$urlMikroti/Boleteria/imagenocr/analizar';
const urlTicketPdf = 'https://api.t-ickets.com/ticket/api/v1/ticket_pdf_link';

/* Cabeceras obligatorias para TODOS los servicios bajo
   https://api.t-ickets.com/ms_login -- mismas que usa app_tickets. No
   aplica a otros dominios/rutas del backend (mikroti/Boleteria, etc.). */
const msLoginAuthHeaders = <String, String>{
  'Authorization': 'Bearer 95035267341b4e54ad0abf6bd35e678ea3eb0c1b6d280f4e768484d6f3ba5b4e',
  'authorization-ticket': 'Basic Ym9sZXRlcmlhOmJvbGV0ZXJpYQ==',
};

Map<String, String> apiHdr() => {...msLoginAuthHeaders, 'Content-Type': 'application/json'};

const jsonHdr = <String, String>{'Content-Type': 'application/json'};

final dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 20),
  receiveTimeout: const Duration(seconds: 60),
  sendTimeout: const Duration(seconds: 60),
));

Options hdr(Map<String, String> headers) => Options(headers: headers);

/* Petición "best-effort": no se espera el resultado y se ignoran errores. */
void sinEsperar(Future<Object?> f) => f.then((_) {}, onError: (Object _) {});

/* Status HTTP de un error de dio (null si no hubo respuesta: red caída). */
int? statusDe(Object e) => e is DioException ? e.response?.statusCode : null;

/* `message` que mandó el backend en una respuesta de error (409/400...). */
String? mensajeBackend(Object e) {
  if (e is! DioException) return null;
  final data = e.response?.data;
  if (data is Map && data['message'] != null) return data['message'].toString();
  return null;
}

/* Sube una imagen al microservicio de imágenes (mismo que usa la web) y
   devuelve la URL pública, o null si falló. */
Future<String?> subirImagen(String rutaArchivo) async {
  try {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(rutaArchivo)});
    final r = await dio.post(urlUploadImg, data: form);
    final data = r.data;
    if (data is Map && data['success'] == true && data['url'] != null) return data['url'].toString();
    return null;
  } catch (_) {
    return null;
  }
}
