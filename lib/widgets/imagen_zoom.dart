import 'package:flutter/material.dart';

/* Imagen a pantalla completa con pellizco para acercar (mapa del lugar,
   división por bloques, comprobantes). */
Future<void> verImagen(BuildContext context, String url, String titulo) => Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, title: Text(titulo)),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) =>
                    p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (c, e, s) =>
                    const Text('No se pudo cargar la imagen.', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
