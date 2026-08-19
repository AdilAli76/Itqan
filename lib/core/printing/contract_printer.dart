import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pdf/arabic_pdf_theme.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');
final _money = NumberFormat('#,##0.00', 'en');

const _editionNames = {
  'standard': 'الإصدار القياسي',
  'wallet': 'إصدار المحفظة',
  'trial': 'الإصدار التجريبي',
  'enterprise': 'إصدار المؤسسات',
};

const _editionScope = {
  'standard': 'إدارة الأصناف والمخزون والمشتريات ونقطة البيع والعملاء والتقارير.',
  'wallet': 'بطاقات وأرصدة المنتسبين والخصم منها ونقطة بيع بالقيمة، بلا وحدات مخزون أو مشتريات.',
  'trial': 'كامل وحدات الإصدار القياسي لمدّة التجربة المذكورة أدناه.',
  'enterprise': 'كامل وحدات الإصدار القياسي بحدود موسّعة للفروع والمستخدمين.',
};

/// عقد اشتراك في النظام — يُنشأ آلياً عند تزويد عميل جديد.
///
/// ⚠ هذا **نموذج تشغيلي** يصف ما يفعله النظام فعلياً وما اتُّفق عليه من
/// رسوم، لا صياغة قانونية معتمَدة. راجعه مع محامٍ قبل أول توقيع: بنود
/// المسؤولية والإنهاء وحماية البيانات تختلف باختلاف قوانين البلد، وخطؤها
/// لا يظهر إلا في نزاع.
///
/// وبنود البيانات والنسخ الاحتياطي مكتوبة كما هو النظام فعلاً لا كما يُشتهى:
/// النسخة الاحتياطية تُؤخذ على قرص الخادم نفسه، ونسخُها خارجه مسؤولية
/// العميل. الوعد بما لا يُنفَّذ هو ما يُخسر النزاعات.
Future<void> printSubscriptionContract({
  required String orgLegalName,
  required String orgDisplayName,
  required String edition,
  required String planTier,
  required DateTime issuedAt,
  required DateTime expiresAt,
  required int maxBranches,
  required int maxUsers,
  required double monthlyFee,
  required double storageFee,
  required double maintenanceRate,
  required String currencySymbol,
  // بيانات مزوّد النظام — من إعدادات المنصة.
  required String providerName,
  String? providerOwner,
  String? providerPhone,
  String? providerEmail,
  String? providerAddress,
  Uint8List? providerLogo,
}) async {
  final doc = pw.Document(theme: await arabicPdfTheme());
  final contractNo = 'C-${_dateFormat.format(issuedAt).replaceAll('-', '')}-'
      '${orgLegalName.hashCode.abs() % 10000}';

  pw.Widget clause(int n, String title, List<String> lines) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('البند $n — $title',
                style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            ...lines.map((l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text('•  $l',
                      style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.6)),
                )),
          ],
        ),
      );

  pw.Widget partyBox(String title, List<String> lines) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: PdfColors.grey600)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.SizedBox(height: 3),
              ...lines.where((l) => l.isNotEmpty).map(
                    (l) => pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
                  ),
            ],
          ),
        ),
      );

  final months = ((expiresAt.difference(issuedAt).inDays) / 30).round();
  final total = (monthlyFee + storageFee) * (months <= 0 ? 1 : months);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 44),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.2))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (providerLogo != null) ...[
              pw.SizedBox(
                width: 46,
                height: 46,
                child: pw.Image(pw.MemoryImage(providerLogo), fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(providerName,
                      style: const pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('عقد اشتراك في نظام إدارة', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pdfLtr(pw.Text(contractNo,
                    style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold))),
                pw.SizedBox(height: 2),
                pdfLtr(pw.Text(_dateFormat.format(issuedAt), style: const pw.TextStyle(fontSize: 9))),
              ],
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(width: 0.6))),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                [
                  if (providerPhone != null && providerPhone.isNotEmpty) 'هاتف: $providerPhone',
                  if (providerEmail != null && providerEmail.isNotEmpty) providerEmail,
                ].join('   •   '),
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pdfLtr(pw.Text('${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            partyBox('الطرف الأول — مزوّد النظام', [
              providerName,
              if (providerOwner != null) providerOwner,
              if (providerPhone != null) 'هاتف: $providerPhone',
              if (providerAddress != null) providerAddress,
            ]),
            pw.SizedBox(width: 10),
            partyBox('الطرف الثاني — المشترك', [
              orgLegalName,
              if (orgDisplayName != orgLegalName) '($orgDisplayName)',
            ]),
          ],
        ),
        pw.SizedBox(height: 14),

        clause(1, 'محلّ العقد', [
          'يمنح الطرف الأول الطرف الثاني حقّ استخدام ${_editionNames[edition] ?? edition} '
              'من النظام طوال مدّة سريان هذا العقد.',
          'نطاق الإصدار: ${_editionScope[edition] ?? '-'}',
          'باقة الترخيص: $planTier — بحدّ أقصى $maxBranches فرعاً و$maxUsers مستخدماً نشطاً.',
          'الحقّ الممنوح هو حقّ استخدام لا تملّك: تبقى ملكية النظام وشيفرته للطرف الأول.',
        ]),

        clause(2, 'المدّة والتجديد', [
          'يبدأ سريان العقد من ${_dateFormat.format(issuedAt)} وينتهي في ${_dateFormat.format(expiresAt)}.',
          'يُجدَّد باتفاق الطرفين قبل تاريخ الانتهاء، وقد تُراجَع الرسوم عند كل تجديد.',
          'يتوقّف الوصول إلى النظام عند انتهاء المدّة دون تجديد، وتبقى بيانات المشترك محفوظة '
              'مدّة لا تقلّ عن ثلاثين يوماً من تاريخ التوقّف تُسلَّم له خلالها عند طلبها.',
        ]),

        clause(3, 'الرسوم وطريقة السداد', [
          'اشتراك النظام: ${_money.format(monthlyFee)} $currencySymbol شهرياً.',
          'رسوم التخزين السحابي: ${_money.format(storageFee)} $currencySymbol شهرياً، '
              'تُستحق عن كل شهر يستضيف فيه الطرف الأول بيانات المشترك.',
          'إجمالي مدّة العقد التقديري: ${_money.format(total)} $currencySymbol عن $months شهراً.',
          'تُسدَّد الرسوم مقدَّماً في بداية كل دورة، والتأخّر عن السداد أكثر من خمسة عشر يوماً '
              'يخوّل الطرف الأول إيقاف الخدمة بعد إشعار كتابي.',
        ]),

        clause(4, 'الميزات الإضافية', [
          'يشمل هذا العقد وحدات الإصدار المذكور في البند الأول دون غيرها.',
          'أي ميزة أو وحدة أو تقرير أو تكامل يطلبه المشترك خارج هذا النطاق يُسعَّر ويُتَّفق '
              'عليه كتابةً قبل تنفيذه، ويُلحَق بهذا العقد.',
          'التعديلات التي يطلبها المشترك على سير عمل قائم تُعامَل معاملة الميزة الإضافية.',
        ]),

        clause(5, 'الصيانة والدعم الفني', [
          maintenanceRate > 0
              ? 'رسوم الصيانة الدورية: ${_money.format(maintenanceRate)}٪ من قيمة الاشتراك.'
              : 'تُحدَّد أعمال الصيانة وتُسعَّر بالتفاهم مع قسم الدعم الفني لدى الطرف الأول.',
          'يشمل الدعم: معالجة الأعطال، وتحديثات النظام، والإرشاد على الاستخدام خلال أوقات العمل.',
          'لا يشمل الدعم: أعطال أجهزة المشترك أو شبكته أو نظام تشغيله، ولا إدخال بياناته، '
              'ولا استرجاع بيانات أتلفها مستخدموه.',
        ]),

        clause(6, 'البيانات والنسخ الاحتياطي', [
          'بيانات المشترك ملكٌ له وحده، ولا يستخدمها الطرف الأول لغير تشغيل الخدمة له.',
          'يأخذ النظام نسخة احتياطية دورية تُحفَظ على قرص الخادم، ويُتحقَّق من سلامتها آلياً.',
          'نسخة على الخادم نفسه لا تحمي من فقدان الجهاز، ولذلك **يلتزم المشترك** بالاحتفاظ '
              'بنسخة احتياطية خارج الخادم على جهاز يخصّه، ويُسلَّم إرشاد ذلك عند التسليم.',
          'لا يتحمّل الطرف الأول فقداً ناتجاً عن إخلال المشترك بالتزام النسخة الخارجية.',
        ]),

        clause(7, 'التزامات المشترك', [
          'المحافظة على سرّية حسابات مستخدميه وكلمات مرورهم، وهو مسؤول عن كل عملية تُنفَّذ بها.',
          'إخطار الطرف الأول فور اكتشاف أي استخدام غير مصرّح به.',
          'عدم محاولة نسخ النظام أو تحليله أو تشغيله لصالح جهة أخرى.',
          'توفير اتصال إنترنت وأجهزة مناسبة لتشغيل النظام في فروعه.',
        ]),

        clause(8, 'حدود المسؤولية', [
          'يُقدَّم النظام على ما هو عليه بالوحدات الموصوفة في البند الأول.',
          'لا يتحمّل الطرف الأول أضراراً غير مباشرة أو أرباحاً فائتة، وتقتصر مسؤوليته في كل '
              'الأحوال على ما سدّده المشترك عن الدورة محلّ النزاع.',
          'لا يتحمّل الطرف الأول انقطاعاً سببه شبكة المشترك أو مزوّد خدمته أو قوّة قاهرة.',
        ]),

        clause(9, 'الإنهاء', [
          'لأي من الطرفين إنهاء العقد بإشعار كتابي قبل ثلاثين يوماً.',
          'للطرف الأول إنهاؤه فوراً عند إخلال جوهري لم يُعالَج خلال خمسة عشر يوماً من الإشعار.',
          'يُسلَّم المشترك نسخة كاملة من بياناته عند الإنهاء، ولا تُستحقّ استعادة رسوم دورة بدأت.',
        ]),

        clause(10, 'أحكام عامة', [
          'لا يُعدَّل هذا العقد إلا كتابةً وبموافقة الطرفين.',
          'ما لم يرد فيه نصّ يُرجَع فيه إلى القوانين المعمول بها، ويُسعى لحلّ أي خلاف ودّياً أولاً.',
          'حُرِّر من نسختين بيد كل طرف نسخة للعمل بموجبها.',
        ]),

        pw.SizedBox(height: 26),
        pw.Row(
          children: [
            pw.Expanded(child: _signature('الطرف الأول — مزوّد النظام', providerOwner)),
            pw.SizedBox(width: 40),
            pw.Expanded(child: _signature('الطرف الثاني — المشترك', null)),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

pw.Widget _signature(String label, String? name) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 28),
        pw.Container(height: 0.8, color: PdfColors.grey700),
        pw.SizedBox(height: 3),
        pw.Text(name ?? 'الاسم والتوقيع والتاريخ',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    );
