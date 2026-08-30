import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';
import '../../../core/pdf/arabic_pdf_theme.dart';
import '../../../core/printing/receipt_printer.dart';
import '../../../core/printing/receipt_template.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/shortcuts/keyboard_shortcuts_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/app_surface.dart';

/// مصمّم قالب الإيصال.
///
/// <para><b>الفجوة التي يسدّها:</b> الإيصال كان يطبع اسم المنظمة نصّاً
/// وحسب — لا شعار ولا رقم ضريبي ولا سجلّ تجاري ولا تذييل ولا رمز استجابة
/// سريعة. والتاجر يريد شعاره على الورقة، وهو أوّل ما يسأل عنه بعد
/// الشراء.</para>
///
/// <para><b>والمعاينة تبني الصفحة بنفس دالة الطباعة</b>
/// ([buildReceiptPage]) لا بشكلٍ يشبهها. ومعاينةٌ مستقلّة كانت ستَعِد
/// المستخدم بشيء وتُخرج الطابعة غيره — وهو نفس مبدأ معاينة مصمّم
/// الباركود.</para>
class ReceiptDesignerScreen extends ConsumerStatefulWidget {
  const ReceiptDesignerScreen({super.key});

  @override
  ConsumerState<ReceiptDesignerScreen> createState() => _ReceiptDesignerScreenState();
}

class _ReceiptDesignerScreenState extends ConsumerState<ReceiptDesignerScreen> {
  ReceiptTemplate? _draft;
  final _header = TextEditingController();
  final _footer = TextEditingController();
  final _taxNumber = TextEditingController();
  final _registry = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    _taxNumber.dispose();
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(receiptTemplateProvider);

    return AdaptiveScaffold(
      title: 'قالب الإيصال',
      activeRoute: '/receipt-designer',
      scrollable: false,
      actions: [
        if (_draft != null)
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
          ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('تعذّر تحميل القالب', style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ),
        data: (loaded) {
          // أوّل بناء فقط: إعادة التعبئة عند كل إعادة رسم تمحو ما يكتبه
          // المستخدم بينما هو يكتبه.
          _draft ??= () {
            _header.text = loaded.headerText ?? '';
            _footer.text = loaded.footerText ?? '';
            _taxNumber.text = loaded.taxNumber ?? '';
            _registry.text = loaded.commercialRegistry ?? '';
            return loaded;
          }();

          final isDesktop = Breakpoints.isDesktop(context);
          final controls = _Controls(
            draft: _draft!,
            header: _header,
            footer: _footer,
            taxNumber: _taxNumber,
            registry: _registry,
            onChanged: (next) => setState(() => _draft = next),
          );
          final preview = _Preview(draft: _current);

          return EnterAdvancesFocus(
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: SingleChildScrollView(child: controls)),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: preview),
                    ],
                  )
                : ListView(
                    children: [
                      controls,
                      const SizedBox(height: 16),
                      SizedBox(height: 420, child: preview),
                    ],
                  ),
          );
        },
      ),
    );
  }

  /// المسودّة ومعها ما يكتبه المستخدم الآن — فتتحرّك المعاينة مع كل حرف.
  ReceiptTemplate get _current => _draft!.copyWith(
        headerText: _header.text,
        footerText: _footer.text,
        taxNumber: _taxNumber.text,
        commercialRegistry: _registry.text,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ApiClient.instance.dio
          .put('/organizations/me/receipt-template', data: _current.toRequest());
      ref.invalidate(receiptTemplateProvider);
      ref.invalidate(receiptLogoProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('حُفظ القالب — كل إيصال بعده يُطبع به')),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      messenger.showSnackBar(SnackBar(
        content: Text(data is Map && data['message'] is String
            ? data['message'] as String
            : 'تعذّر حفظ القالب'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.draft,
    required this.header,
    required this.footer,
    required this.taxNumber,
    required this.registry,
    required this.onChanged,
  });

  final ReceiptTemplate draft;
  final TextEditingController header;
  final TextEditingController footer;
  final TextEditingController taxNumber;
  final TextEditingController registry;
  final ValueChanged<ReceiptTemplate> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المقاس', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: draft.paper,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'مقاس الورق'),
              items: [
                for (final paper in ReceiptPapers.all)
                  DropdownMenuItem(value: paper, child: Text(ReceiptPapers.labelOf(paper))),
              ],
              onChanged: (v) => v == null ? null : onChanged(draft.copyWith(paper: v)),
            ),
            const SizedBox(height: 20),
            Text('ما يظهر', style: AppTextStyles.bodyLg()),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.showLogo,
              onChanged: (v) => onChanged(draft.copyWith(showLogo: v)),
              title: const Text('الشعار'),
              subtitle: Text(
                draft.logoUrl == null
                    // قول السبب أصدق من مفتاحٍ يُفعَّل ولا يظهر أثره.
                    ? 'لا شعار مرفوع للمنظمة — ارفعه من شاشة الفروع والهوية'
                    : 'شعار المنظمة أعلى الإيصال',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.showTaxNumber,
              onChanged: (v) => onChanged(draft.copyWith(showTaxNumber: v)),
              title: const Text('الرقم الضريبي'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.showCommercialRegistry,
              onChanged: (v) => onChanged(draft.copyWith(showCommercialRegistry: v)),
              title: const Text('رقم السجلّ التجاري'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.showQr,
              onChanged: (v) => onChanged(draft.copyWith(showQr: v)),
              title: const Text('رمز الاستجابة السريعة'),
              subtitle: Text(
                // يحمل الرقم لا رابطاً: الرمز يجب أن يعمل بعد سنة ومن هاتف
                // خارج الشبكة.
                'يحمل رقم الفاتورة — يعمل بلا إنترنت',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            Text('البيانات الرسمية', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 8),
            TextField(
              controller: taxNumber,
              decoration: const InputDecoration(labelText: 'الرقم الضريبي'),
              onChanged: (_) => onChanged(draft),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: registry,
              decoration: const InputDecoration(labelText: 'رقم السجلّ التجاري'),
              onChanged: (_) => onChanged(draft),
            ),
            const SizedBox(height: 20),
            Text('الترويسة والتذييل', style: AppTextStyles.bodyLg()),
            const SizedBox(height: 8),
            TextField(
              controller: header,
              decoration: const InputDecoration(
                labelText: 'سطر الترويسة',
                hintText: 'العنوان أو رقم الهاتف',
              ),
              onChanged: (_) => onChanged(draft),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: footer,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'شروط التذييل',
                hintText: 'الاسترجاع خلال ٣ أيام بالفاتورة',
              ),
              onChanged: (_) => onChanged(draft),
            ),
          ],
        ),
      ),
    );
  }
}

/// معاينة حقيقية — تُبنى بدالة الطباعة نفسها.
class _Preview extends ConsumerWidget {
  const _Preview({required this.draft});
  final ReceiptTemplate draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider).valueOrNull;
    final logo = ref.watch(receiptLogoProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('معاينة', style: AppTextStyles.bodyLg()),
        const SizedBox(height: 4),
        Text(
          'مبنيّة بنفس دالة الطباعة — ما تراه هو ما يخرج من الطابعة',
          style: AppTextStyles.caption(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ref.watch(_canRasterProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const _PreviewUnavailable(),
                data: (canRaster) =>
                    canRaster ? _pdfPreview(branding, logo) : const _PreviewUnavailable(),
              ),
        ),
      ],
    );
  }

  Widget _pdfPreview(OrganizationBranding? branding, Uint8List? logo) => PdfPreview(
        build: (format) => _buildPdf(
          orgName: branding?.displayName ?? 'إتقان ERP',
          currencySymbol: branding?.currencySymbol ?? 'د.ل',
          logoBytes: draft.showLogo ? logo : null,
        ),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
      );

  Future<Uint8List> _buildPdf({
    required String orgName,
    required String currencySymbol,
    Uint8List? logoBytes,
  }) async {
    final doc = pw.Document(theme: await arabicPdfTheme());
    doc.addPage(buildReceiptPage(
      invoice: _sampleInvoice,
      orgName: orgName,
      currencySymbol: currencySymbol,
      template: draft,
      logoBytes: logoBytes,
    ));
    return doc.save();
  }
}

/// فاتورة عيّنة للمعاينة.
///
/// <para>بأصنافٍ وأسعارٍ واقعية لا بنصٍّ نائب: قالبٌ يبدو مضبوطاً على
/// «صنف ١» ثم ينكسر على اسمٍ طويل حقيقي لا يُكتشف إلا عند أوّل زبون.</para>
const _sampleInvoice = {
  'invoiceNumber': 'INV-2026-0842',
  'createdAt': '2026-08-25T12:30:00',
  'customerName': 'محمد عبد السلام',
  'invoiceType': 'sale',
  'subtotal': 187.5,
  'taxAmount': 0,
  'discountAmount': 12.5,
  'totalAmount': 175.0,
  'items': [
    {'productName': 'زيت محرّك 5W-30 — عبوة 4 لتر', 'quantity': 2, 'lineTotal': 154.0},
    {'productName': 'فلتر هواء', 'quantity': 1, 'lineTotal': 15.0},
    {'productName': 'مسّاحة زجاج', 'quantity': 1, 'lineTotal': 18.5},
  ],
  'payments': [
    {'method': 'cash', 'amount': 175.0},
  ],
};

/// أتستطيع هذه المنصّة رسم صفحة PDF على الشاشة؟
///
/// <para>المعاينة تحتاج تحويل الصفحة إلى صورة، وهو ما لا تدعمه كل منصّة.
/// وبلا هذا الفحص تعرض مكتبة المعاينة صندوق خطأ أحمر — وهو أسوأ من رسالة
/// تقول ما الذي لا يعمل: المستخدم يظنّ القالب نفسه معطوباً فلا يحفظه.</para>
final _canRasterProvider = FutureProvider<bool>((ref) async {
  try {
    return (await Printing.info()).canRaster;
  } catch (_) {
    return false;
  }
});

class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.print_disabled_outlined, size: 36, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text('المعاينة غير متاحة على هذا الجهاز',
                  style: AppTextStyles.bodyLg(), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                // الإعدادات تُحفظ وتعمل: العجز في الرسم على الشاشة لا في
                // القالب. وقول ذلك يمنع المستخدم من ظنّ عمله ضائعاً.
                'الإعدادات تُحفظ وتُطبَّق على الطباعة كالمعتاد — العرض هنا وحده معطَّل',
                style: AppTextStyles.caption(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
