import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/nav.dart';
import '../core/tema.dart';

/* Escaneo de QR / código de barras con la cámara (ML Kit en Android, Vision
   en iPhone). Complementa al lector de código de barras por teclado y al
   tecleo manual. */

class ResultadoEscaneo {
  final bool ok;
  final String? codigo;
  final String? mensaje;
  const ResultadoEscaneo({required this.ok, this.codigo, this.mensaje});
}

Future<ResultadoEscaneo> escanearBoletoFisico({String? titulo}) async {
  final codigo = await nav.push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PantallaEscaner(titulo: titulo ?? 'Escanear código'),
  ));
  /* Cerrar la cámara sin escanear no es un error. */
  if (codigo == null) return const ResultadoEscaneo(ok: false);
  if (codigo.trim().isEmpty) return const ResultadoEscaneo(ok: false, mensaje: 'No se detectó ningún código.');
  return ResultadoEscaneo(ok: true, codigo: codigo.trim());
}

class PantallaEscaner extends StatefulWidget {
  final String titulo;
  const PantallaEscaner({super.key, required this.titulo});

  @override
  State<PantallaEscaner> createState() => _PantallaEscanerState();
}

class _PantallaEscanerState extends State<PantallaEscaner> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _listo = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture captura) {
    if (_listo) return;
    for (final b in captura.barcodes) {
      final valor = b.displayValue ?? b.rawValue;
      if (valor != null && valor.isNotEmpty) {
        _listo = true;
        Navigator.of(context).pop(valor);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ventana = Rect.fromCenter(
      center: MediaQuery.sizeOf(context).center(const Offset(0, -40)),
      width: 280,
      height: 280,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Linterna',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Se necesita permiso de cámara para escanear. Actívalo en los ajustes del teléfono.'
                    : 'No se pudo abrir la cámara.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: ventana,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: C.verdeClaro, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Apunta al código QR o de barras del boleto',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/* Usado por pantallas que no tienen contexto propio a mano. */
void avisoEscaneo(ResultadoEscaneo r) {
  if (r.mensaje != null) toast(r.mensaje!);
}
