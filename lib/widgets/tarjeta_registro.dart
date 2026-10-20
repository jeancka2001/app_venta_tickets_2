import 'package:flutter/material.dart';

import '../core/formato.dart';
import '../core/tema.dart';
import '../models/venta.dart';
import 'comunes.dart';

/* Tarjeta de una compra en las listas (Buscar cliente / Mis ventas). */
class TarjetaRegistro extends StatelessWidget {
  final Registro reg;
  final VoidCallback onTap;
  final bool mostrarFormaPago;
  const TarjetaRegistro({super.key, required this.reg, required this.onTap, this.mostrarFormaPago = false});

  @override
  Widget build(BuildContext context) {
    final faltan = reg.faltanBoletos;
    return Tarjeta(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text(reg.nombreEvento,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: colorTexto(context))),
          ),
          const SizedBox(width: 8),
          insigniaEstadoPago(reg.estadoPago),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Text(
              mostrarFormaPago
                  ? '${reg.localidadNombre} · ${reg.formaPago.isEmpty ? '—' : reg.formaPago}'
                  : reg.localidadNombre,
              style: TextStyle(color: colorTenue(context), fontSize: 13),
            ),
          ),
          Text(formatFecha(reg.fechaCreacion), style: TextStyle(color: colorTenue(context), fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('\$${f2(reg.total)}',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colorAcento(context))),
          const Spacer(),
          Icon(Icons.confirmation_number_outlined, size: 16, color: faltan ? C.naranja : colorTenue(context)),
          const SizedBox(width: 4),
          Text('${reg.boletosGenerados}/${reg.boletosEsperados} generados${faltan ? ' ⚠' : ''}',
              style: TextStyle(
                  fontSize: 12.5,
                  color: faltan ? C.naranja : colorTenue(context),
                  fontWeight: faltan ? FontWeight.w700 : FontWeight.w500)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: colorTenue(context)),
        ]),
      ]),
    );
  }
}
