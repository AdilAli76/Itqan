import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_text_styles.dart';

/// مسح الباركود بكاميرا الجهاز.
///
/// شاشة البيع كانت تفترض قارئاً سلكياً في كل جهاز: أيقونة الباركود في مربع
/// البحث كانت زخرفية (prefixIcon بلا مستقبِل نقر)، فالضغط عليها لا يفعل
/// شيئاً. وعلى هاتف أو جهاز لوحي — بلا قارئ ولا كاميرا — لم يكن للمسح سبيل
/// إطلاقاً، فيبقى الكاشير مضطراً لكتابة اسم الصنف كاملاً وصحيحاً.
///
/// تُعيد الرمز الممسوح نصاً، ويتولّى المستدعي تفسيره: يُجرَّب باركود صنف
/// أولاً ثم بطاقة عميل — نفس ترتيب القارئ السلكي تماماً، فلا يختلف سلوك
/// الجهازين.
class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  final _controller = MobileScannerController(
    // الرمز الواحد يُلتقط مرّة واحدة: بلا هذا يُطلق الحدث عشرات المرّات في
    // الثانية ما دامت الكاميرا مصوّبة عليه، فيُضاف الصنف عشرات المرّات.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (code == null) return;
    _handled = true;
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('امسح الباركود'),
        actions: [
          IconButton(
            tooltip: 'الإضاءة',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'تبديل الكاميرا',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // إذن مرفوض أو جهاز بلا كاميرا: رسالة تقول ماذا يفعل الكاشير،
            // لا شاشة سوداء صامتة يظنّها عطلاً.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'تعذّر فتح الكاميرا — اسمح للتطبيق بالوصول إليها من '
                      'إعدادات المتصفح أو الجهاز، أو اكتب اسم الصنف يدوياً.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // إطار تصويب: يضبط المسافة فيقلّ التقاط رمز مجاور على رفّ مزدحم.
          IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
