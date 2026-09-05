import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:kinetic_enterprise/core/pdf/arabic_pdf_theme.dart';
import 'package:kinetic_enterprise/core/printing/receipt_printer.dart';
import 'package:kinetic_enterprise/core/printing/receipt_template.dart';

/// الطباعة تعمل بلا إنترنت.
///
/// <para><b>العطب الذي يحرسه:</b> خطوط الـPDF كانت تُجلب من خطوط قوقل وقت
/// الطباعة، والنظام يُنشر داخل متجر قد لا شبكة فيه. فأوّل إيصال يقف
/// انتظاراً ثم يخرج بخطٍّ بديل والزبون واقف — والطباعة آخر خطوة في البيع،
/// أحوجُ ما يكون إلى ألّا تتعلّق بشبكة.</para>
///
/// <para>ولا يُفحَص «هل الكود يستدعي الشبكة؟» بالقراءة: يُبنى إيصالٌ فعلي
/// ويُفتَّش في بايتاته عن اسم الخطّ المضمَّن. فلو عاد أحدٌ إلى الجلب
/// الشبكي سقط هذا الاختبار — وبيئة الاختبار بلا شبكة أصلاً، فسيسقط
/// بانتظارٍ أو باستثناء لا بخطٍّ خاطئ يمرّ.</para>
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('خطّ الإيصال مضمَّن في الحزمة لا مُنزَّل', () async {
    final theme = await arabicPdfTheme();
    final document = pw.Document(theme: theme);

    document.addPage(buildReceiptPage(
      invoice: {
        'invoiceNumber': 'INV-1',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'items': [
          {'productName': 'أرز 5كغ', 'quantity': 2, 'lineTotal': 90},
        ],
        'totalAmount': 90,
      },
      orgName: 'متجر الاختبار',
      currencySymbol: 'د.ل',
      template: ReceiptTemplate.fallback,
    ));

    final bytes = await document.save();
    expect(bytes.length, greaterThan(1000));

    // اسم الخطّ يُكتب في جدول الخطوط داخل الملف، فوجودُه دليلُ التضمين.
    final raw = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
    expect(raw.contains('IBMPlex'), isTrue,
        reason: 'الإيصال لم يُضمَّن فيه خطّ الحزمة — أعاد أحدهم الجلب الشبكي؟');
  });

  test('القالب الجاهز يغيّر شكل الإيصال فعلاً', () async {
    // ليست فحص شكل: القوالب تُبدّل قيماً تقرؤها دالّة الطباعة، وقالبٌ
    // يُختار ولا يغيّر بايتاً واحداً يعني خياراً معطوباً في الشاشة.
    final theme = await arabicPdfTheme();
    Future<int> sizeOf(ReceiptTemplate template) async {
      final document = pw.Document(theme: theme);
      document.addPage(buildReceiptPage(
        invoice: {
          'invoiceNumber': 'INV-2',
          'items': [
            {'productName': 'أرز', 'quantity': 1, 'lineTotal': 45},
            {'productName': 'سكر', 'quantity': 3, 'lineTotal': 30},
          ],
          'totalAmount': 75,
        },
        orgName: 'متجر الاختبار',
        currencySymbol: 'د.ل',
        template: template,
      ));
      return (await document.save()).length;
    }

    final classic = await sizeOf(ReceiptTemplate.fallback.applyPreset(ReceiptPresets.classic));
    final modern = await sizeOf(ReceiptTemplate.fallback.applyPreset(ReceiptPresets.modern));

    expect(classic, isNot(equals(modern)));
  });
}
