import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';

/// عرض باركود Code128 على الشاشة — نفس المكتبة المستخدَمة في توليد PDF
/// الطباعة، فما يظهر على شاشة الهاتف يُمسح بنفس القارئ الذي يمسح البطاقة
/// الورقية تماماً.
class BarcodeView extends StatelessWidget {
  const BarcodeView({
    super.key,
    required this.data,
    this.height = 64,
    this.color = Colors.black,
  });

  final String data;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _BarcodePainter(data, color)),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data, this.color);
  final String data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || data.isEmpty) return;
    final paint = Paint()..color = color;
    for (final el in bc.Barcode.code128().make(data, width: size.width, height: size.height)) {
      if (el is bc.BarcodeBar && el.black) {
        canvas.drawRect(Rect.fromLTWH(el.left, el.top, el.width, el.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.data != data || old.color != color;
}
