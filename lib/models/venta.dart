import '../core/json.dart';

class EventoVenta {
  final int id;
  final String nombreConcierto;
  final String fechaConcierto;
  final String horaConcierto;
  final String lugarConcierto;
  final String cuidadConcert;
  final String imagenConcierto;
  final String mapaConcierto;
  final String codigoEvento;
  final String iva;

  EventoVenta({
    required this.id,
    required this.nombreConcierto,
    required this.fechaConcierto,
    required this.horaConcierto,
    required this.lugarConcierto,
    required this.cuidadConcert,
    required this.imagenConcierto,
    required this.mapaConcierto,
    required this.codigoEvento,
    required this.iva,
  });

  factory EventoVenta.fromJson(Map<String, dynamic> j) => EventoVenta(
        id: ent(j['id']),
        nombreConcierto: str(j['nombreConcierto']),
        fechaConcierto: str(j['fechaConcierto']),
        horaConcierto: str(j['horaConcierto']),
        lugarConcierto: str(j['lugarConcierto']),
        cuidadConcert: str(j['cuidadConcert']),
        imagenConcierto: str(j['imagenConcierto']),
        mapaConcierto: str(j['mapaConcierto']),
        codigoEvento: str(j['codigoEvento']),
        iva: str(j['iva'], '1.00'),
      );
}

class Modalidad {
  final String codigo;
  final String nombre;
  final String precio;
  final int factor;
  Modalidad(this.codigo, this.nombre, this.precio, this.factor);
}

class PrecioLocalidad {
  final int id;
  final int idLocalidad;
  final String localidad;
  final String precioNormal;
  final int cantidadDisponible;
  final String tipoLocalidad;
  final String comisionBoleto;
  /* Boletos por precio (x2: dos entradas por un precio). */
  final int factorBoletos;
  /* Opciones de compra de la localidad (promociones con las mismas sillas). */
  final List<Modalidad> modalidades;
  final String? modalidadCodigo;
  final String? modalidadNombre;

  PrecioLocalidad({
    required this.id,
    required this.idLocalidad,
    required this.localidad,
    required this.precioNormal,
    required this.cantidadDisponible,
    required this.tipoLocalidad,
    required this.comisionBoleto,
    required this.factorBoletos,
    required this.modalidades,
    this.modalidadCodigo,
    this.modalidadNombre,
  });

  factory PrecioLocalidad.fromJson(Map<String, dynamic> j) => PrecioLocalidad(
        id: ent(j['id']),
        idLocalidad: ent(j['id_localidad']),
        localidad: str(j['localidad']),
        precioNormal: str(j['precio_normal'], '0'),
        cantidadDisponible: ent(j['cantidad_disponible']),
        tipoLocalidad: str(j['tipo_localidad'], 'correlativo'),
        comisionBoleto: str(j['comision_boleto'], '0'),
        factorBoletos: ent(j['factor_boletos']) > 0 ? ent(j['factor_boletos']) : 1,
        modalidades: asMapList(j['modalidades'])
            .map((m) => Modalidad(str(m['codigo']), str(m['nombre']), str(m['precio']), ent(m['factor'])))
            .toList(),
      );

  PrecioLocalidad conModalidad(Modalidad m) => PrecioLocalidad(
        id: id,
        idLocalidad: idLocalidad,
        localidad: localidad,
        precioNormal: m.precio,
        cantidadDisponible: cantidadDisponible,
        tipoLocalidad: tipoLocalidad,
        comisionBoleto: comisionBoleto,
        factorBoletos: m.factor > 0 ? m.factor : 1,
        modalidades: modalidades,
        modalidadCodigo: m.codigo,
        modalidadNombre: m.nombre,
      );
}

class Cliente {
  final int id;
  final String cedula;
  final String nombreCompleto;
  final String email;
  final String movil;
  final String ciudad;
  final bool esNuevo;
  Cliente({
    required this.id,
    required this.cedula,
    required this.nombreCompleto,
    required this.email,
    required this.movil,
    this.ciudad = '',
    required this.esNuevo,
  });

  String get nombreOCedula => nombreCompleto.isNotEmpty ? nombreCompleto : cedula;
}

/* Datos que pasan de Localidad a Pago. */
class DatosPago {
  final String idLocalidad;
  final String codigoEvento;
  final int idPrecio;
  final String nombreEvento;
  final String localidadNombre;
  final double precio;
  /* Entradas (asientos), no paquetes. */
  final int cantidad;
  final int factorBoletos;
  final String modalidadCodigo;
  final List<int> idSillas;
  /* Etiqueta cruda de cada asiento en idSillas (mismo orden). */
  final List<String?> sillasSeleccionadas;
  final double comisionBoleto;
  final String iva;
  final Cliente cliente;

  DatosPago({
    required this.idLocalidad,
    required this.codigoEvento,
    required this.idPrecio,
    required this.nombreEvento,
    required this.localidadNombre,
    required this.precio,
    required this.cantidad,
    required this.factorBoletos,
    required this.modalidadCodigo,
    required this.idSillas,
    required this.sillasSeleccionadas,
    required this.comisionBoleto,
    required this.iva,
    required this.cliente,
  });
}

/* Compra (registraCompra) tal como la devuelve listarRegistros. */
class Registro {
  final int id;
  final String cedula;
  final String formaPago;
  final String totalPago;
  final List<Map<String, dynamic>> infoConcierto;
  final String estadoPago;
  final String fechaCreacion;
  final List<Map<String, dynamic>> ticketUsuarios;
  final Map<String, dynamic> raw;

  Registro(this.id, this.cedula, this.formaPago, this.totalPago, this.infoConcierto, this.estadoPago,
      this.fechaCreacion, this.ticketUsuarios, this.raw);

  factory Registro.fromJson(Map<String, dynamic> j) => Registro(
        ent(j['id']),
        str(j['cedula']),
        str(j['forma_pago']),
        str(j['total_pago'], '0'),
        asMapList(j['info_concierto']),
        str(j['estado_pago']),
        str(j['fechaCreacion']),
        asMapList(j['ticket_usuarios']),
        j,
      );

  String get nombreEvento => infoConcierto.isNotEmpty ? str(infoConcierto[0]['nombreConcierto'], '—') : '—';
  String get localidadNombre => infoConcierto.isNotEmpty ? str(infoConcierto[0]['localidad_nombre']) : '';
  String get codigoEvento => infoConcierto.isNotEmpty ? str(infoConcierto[0]['CODIGEVENTO']) : '';
  int get boletosGenerados => ticketUsuarios.length;
  int get boletosEsperados => infoConcierto.fold(0, (acc, c) => acc + ent(c['cantidad']));
  bool get faltanBoletos => estadoPago == 'Pagado' && boletosGenerados < boletosEsperados;
  double get total => dbl(totalPago);
}
