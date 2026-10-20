import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formato.dart';
import 'admin_eventos.dart';
import 'bloqueo_sesion.dart';

/* PDFs que antes se armaban con jsPDF. En vez de escribirlos a la carpeta
   Documentos (no existe en iPhone), se abre el diálogo del sistema para
   imprimir o guardar como PDF, o la hoja de compartir. */

class LocalidadFactura {
  final String nombre;
  final String cantidad;
  LocalidadFactura(this.nombre, this.cantidad);
}

class DatosFactura {
  final int id;
  final String nombreConcierto;
  final List<LocalidadFactura> localidades;
  final String formaPago;
  final double total;
  final String cliente;
  final String correo;
  final String cedula;
  final String fechaRegistro;
  final String? numeroComprobante;
  DatosFactura({
    required this.id,
    required this.nombreConcierto,
    required this.localidades,
    required this.formaPago,
    required this.total,
    required this.cliente,
    required this.correo,
    required this.cedula,
    required this.fechaRegistro,
    this.numeroComprobante,
  });
}

/* Datos fijos de la empresa. */
const _empresaNombre = 'T-ICKETS (TICKETSECUADOR S.A.)';
const _empresaRuc = '0993377293001';
const _empresaDireccion = 'Edificio City Office Oficina 310';

String _fechaImpresion() {
  final d = DateTime.now();
  return '${dosDigitos(d.day)}/${dosDigitos(d.month)}/${d.year}, '
      '${dosDigitos(d.hour)}:${dosDigitos(d.minute)}:${dosDigitos(d.second)}';
}

/* Recibo estilo ticket (240pt de ancho, fuente Courier) -- mismo formato que
   el botón de la impresora en el detalle de la orden en la web. */
Future<Uint8List> generarPdfRecibo(DatosFactura d) async {
  final doc = pw.Document();
  final normal = pw.Font.courier();
  final negrita = pw.Font.courierBold();

  pw.Widget centrado(String t, {bool bold = false, double tam = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Center(
            child: pw.Text(t, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold ? negrita : normal, fontSize: tam))),
      );
  pw.Widget izquierda(String t, {bool bold = false, double tam = 9}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text(t, style: pw.TextStyle(font: bold ? negrita : normal, fontSize: tam)),
      );
  pw.Widget dosLados(String a, String b) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Flexible(child: pw.Text(a, style: pw.TextStyle(font: normal, fontSize: 9))),
          pw.Text(b, style: pw.TextStyle(font: normal, fontSize: 9)),
        ]),
      );
  pw.Widget separador() => centrado('*' * 34, tam: 8);
  pw.Widget salto([int n = 1]) => pw.SizedBox(height: 14.0 * n);

  final locs = d.localidades.isNotEmpty ? d.localidades : [LocalidadFactura('—', '')];

  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(240, double.infinity, marginAll: 14),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      centrado(_empresaNombre, bold: true, tam: 10),
      centrado('RUC $_empresaRuc'),
      centrado(_empresaDireccion),
      centrado('Fecha:${_fechaImpresion()}'),
      separador(),
      centrado('DESCRIPCIÓN', bold: true),
      separador(),
      salto(),
      izquierda('Evento: ${d.nombreConcierto}'),
      for (final loc in locs) ...[
        salto(),
        dosLados('Localidad:${loc.nombre.isEmpty ? '—' : loc.nombre}', 'Cantidad:${loc.cantidad}'),
      ],
      salto(2),
      centrado('TOTAL: ${d.total.toStringAsFixed(2)}', tam: 10),
      centrado(r'SALDO: $0.00', tam: 10),
      salto(),
      izquierda('CLIENTE', bold: true),
      izquierda('Nombres: ${(d.cliente.isEmpty ? '—' : d.cliente).toUpperCase()}'),
      izquierda('Correo: ${d.correo.isEmpty ? '—' : d.correo}'),
      izquierda('Cédula: ${d.cedula.isEmpty ? '—' : d.cedula}'),
      salto(),
      izquierda('Fecha registro: ${d.fechaRegistro.isEmpty ? '—' : d.fechaRegistro}'),
      salto(),
      centrado('Impresión:${_fechaImpresion()}'),
      separador(),
      if (d.formaPago == 'Deposito') ...[
        salto(),
        centrado('Número de comprobante ${d.numeroComprobante ?? '—'}'),
        salto(),
        centrado('Forma de pago: ${d.formaPago}'),
      ] else ...[
        salto(),
        centrado('Forma de pago: ${d.formaPago.isEmpty ? '—' : d.formaPago}'),
      ],
      separador(),
      salto(),
      izquierda('Recibí conforme:'),
      salto(2),
      izquierda('_______________________'),
    ]),
  ));
  return doc.save();
}

/* Abre el diálogo del sistema (imprimir / guardar como PDF). */
Future<String?> imprimirRecibo(DatosFactura d) async {
  try {
    final bytes = await generarPdfRecibo(d);
    await sinBloqueo(() => Printing.layoutPdf(
          name: 'comprobante_tickets_${d.id}',
          format: const PdfPageFormat(240, 680),
          onLayout: (_) async => bytes,
        ));
    return null;
  } catch (e) {
    debugPrint('[factura] no se pudo generar: $e');
    return 'No se pudo generar el comprobante. Intenta de nuevo.';
  }
}

class DatosFacturaEvento {
  final String codigoEvento;
  final String nombreEvento;
  final int ivaPercent;
  final List<FacturaLocalidadItem> filas;
  final int totalBoletos;
  final double subtotal;
  final double iva;
  final double total;
  DatosFacturaEvento(this.codigoEvento, this.nombreEvento, this.ivaPercent, this.filas, this.totalBoletos, this.subtotal,
      this.iva, this.total);
}

String _m(num n) => '\$ ${n.toStringAsFixed(2)}';

/* "Factura de Venta Final" de un evento -- misma estructura que la web
   (sección "DETALLE DEL EVENTO" + totales). */
Future<String?> compartirFacturaEvento(DatosFacturaEvento d) async {
  try {
    final doc = pw.Document();
    final bold = pw.Font.helveticaBold();
    final normal = pw.Font.helvetica();
    final ahora = DateTime.now();
    final generado = '${dosDigitos(ahora.day)}/${dosDigitos(ahora.month)}/${ahora.year} '
        '${dosDigitos(ahora.hour)}:${dosDigitos(ahora.minute)}';

    pw.Widget celda(String t, {bool b = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: pw.Text(t, style: pw.TextStyle(font: b ? bold : normal, fontSize: 8.5, color: color)),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Text('Factura de Venta Final', style: pw.TextStyle(font: bold, fontSize: 16)),
        pw.SizedBox(height: 10),
        pw.Text('Evento: ${d.nombreEvento}', style: pw.TextStyle(font: normal, fontSize: 10)),
        pw.Text('Código: ${d.codigoEvento}', style: pw.TextStyle(font: normal, fontSize: 10)),
        pw.Text('IVA aplicado a boletos: ${d.ivaPercent}%', style: pw.TextStyle(font: normal, fontSize: 10)),
        pw.Text('Generado: $generado', style: pw.TextStyle(font: normal, fontSize: 10)),
        pw.SizedBox(height: 14),
        pw.Container(
          color: const PdfColor.fromInt(0xFF2C3E50),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text('DETALLE DEL EVENTO', style: pw.TextStyle(font: bold, fontSize: 11, color: PdfColors.white)),
        ),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(155),
            1: pw.FlexColumnWidth(70),
            2: pw.FlexColumnWidth(70),
            3: pw.FlexColumnWidth(55),
            4: pw.FlexColumnWidth(165),
          },
          border: const pw.TableBorder(bottom: pw.BorderSide(color: PdfColors.grey400)),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
              children: ['Localidad', 'Tarifa', 'P. Unit.', 'Cant.', 'Subtotal'].map((t) => celda(t, b: true)).toList(),
            ),
            for (var i = 0; i < d.filas.length; i++)
              pw.TableRow(
                decoration: i.isEven ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F6FA)) : null,
                children: [
                  celda(d.filas[i].localidad.isEmpty ? '—' : d.filas[i].localidad),
                  celda(d.filas[i].tarifa.isEmpty ? '—' : d.filas[i].tarifa),
                  celda(_m(d.filas[i].precioUnitarioBase)),
                  celda('${d.filas[i].cantidad}'),
                  celda(_m(d.filas[i].subtotalSinIva)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(children: [
            _filaTotal('TOTAL BOLETOS', '${d.totalBoletos}', _m(d.subtotal), bold, 9),
            if (d.iva > 0) _filaTotal('IVA (${d.ivaPercent}%)', '', _m(d.iva), bold, 9),
            _filaTotal('TOTAL FINAL', '', _m(d.total), bold, 10.5),
          ]),
        ),
      ],
    ));
    final bytes = await doc.save();
    await sinBloqueo(() => Printing.sharePdf(bytes: bytes, filename: 'factura_final_${d.codigoEvento}.pdf'));
    return null;
  } catch (e) {
    debugPrint('[facturaEventoFinal] no se pudo generar: $e');
    return 'No se pudo generar la factura. Intenta de nuevo.';
  }
}

pw.Widget _filaTotal(String a, String b, String c, pw.Font bold, double tam) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(children: [
        pw.Expanded(flex: 295, child: pw.Text(a, style: pw.TextStyle(font: bold, fontSize: tam))),
        pw.Expanded(flex: 55, child: pw.Text(b, style: pw.TextStyle(font: bold, fontSize: tam))),
        pw.Expanded(flex: 165, child: pw.Text(c, style: pw.TextStyle(font: bold, fontSize: tam))),
      ]),
    );

/* Guarda un archivo en la carpeta temporal y abre la hoja de compartir
   (permite guardarlo en Archivos/Drive o mandarlo por WhatsApp/correo). */
Future<String?> compartirArchivo(Uint8List bytes, String nombre, String mime) async {
  try {
    final dir = await getTemporaryDirectory();
    final archivo = File('${dir.path}/$nombre');
    await archivo.writeAsBytes(bytes);
    await sinBloqueo(() => SharePlus.instance.share(ShareParams(files: [XFile(archivo.path, mimeType: mime)], title: nombre)));
    return null;
  } catch (e) {
    debugPrint('[compartirArchivo] $e');
    return 'No se pudo guardar el archivo.';
  }
}
