import 'dart:async';

import 'package:barcode/barcode.dart' as bc;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/pdf/arabic_pdf_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../data/barcode_template_providers.dart';
import '../../../shared/widgets/icon_action.dart';

// ux-audit: ignore RT-06 — القيمة المالية الوحيدة هنا سعرٌ مطبوع على ملصق
// 30×20 مم، وتنسيقه toStringAsFixed(2) هو الصحيح لا NumberFormat: فواصل
// الآلاف تلتهم عرض الملصق، والملصق يُقرأ بماسح ضوئي وبعين على بُعد شبر
// لا في جدول مالي. العرض داخل pdfLtr أصلاً لضبط اتجاه الرقم.

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

class BarcodeDesignerScreen extends ConsumerStatefulWidget {
  const BarcodeDesignerScreen({super.key});

  @override
  ConsumerState<BarcodeDesignerScreen> createState() => _BarcodeDesignerScreenState();
}

class _BarcodeDesignerScreenState extends ConsumerState<BarcodeDesignerScreen> {
  bool _canEdit = false;
  bool _roleLoaded = false;

  @override
  void initState() {
    super.initState();
    readJwtClaims().then((claims) {
      if (mounted) {
        setState(() {
          _canEdit = claims?['role'] == 'super_admin';
          _roleLoaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final templateAsync = ref.watch(barcodeTemplateProvider);

    return AdaptiveScaffold(
      title: 'تخصيص ملصق الباركود',
      activeRoute: '/barcode-designer',
      body: !_roleLoaded
          ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          : templateAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Text('تعذّر تحميل إعداد الملصق', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => ref.invalidate(barcodeTemplateProvider), child: const Text('إعادة المحاولة')),
                  ],
                ),
              ),
              data: (template) => _DesignerBody(template: template, canEdit: _canEdit),
            ),
    );
  }
}

class _PrintLine {
  _PrintLine({required this.productId, required this.name, required this.barcodeValue, required this.sku, required this.price});
  final String productId;
  final String name;
  final String barcodeValue;
  final String sku;
  final double price;
  int quantity = 1;
}

class _DesignerBody extends ConsumerStatefulWidget {
  const _DesignerBody({required this.template, required this.canEdit});
  final Map<String, dynamic> template;
  final bool canEdit;

  @override
  ConsumerState<_DesignerBody> createState() => _DesignerBodyState();
}

class _DesignerBodyState extends ConsumerState<_DesignerBody> {
  late final _widthController = TextEditingController(text: '${widget.template['widthMm']}');
  late final _heightController = TextEditingController(text: '${widget.template['heightMm']}');
  late bool _showName = widget.template['showName'] as bool? ?? true;
  late bool _showPrice = widget.template['showPrice'] as bool? ?? true;
  late bool _showSku = widget.template['showSku'] as bool? ?? false;

  final _searchController = TextEditingController();
  final List<_PrintLine> _lines = [];
  Timer? _debounce;
  bool _savingSettings = false;
  bool _printing = false;
  String? _error;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  double get _widthMm => double.tryParse(_widthController.text) ?? 40;
  double get _heightMm => double.tryParse(_heightController.text) ?? 25;

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(barcodeProductSearchProvider.notifier).state = value;
    });
  }

  /// دعم قارئ الباركود: مسح صنف ثم Enter يضيفه مباشرة عند تطابق وحيد —
  /// نفس نمط نقطة البيع وتحويل المخزون.
  Future<void> _onSearchSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;
    try {
      final response = await ApiClient.instance.dio.get('/products/inventory', queryParameters: {'search': code});
      final results = List<Map<String, dynamic>>.from(response.data as List);
      final exact = results.where((p) => p['barcode'] == code || p['sku'] == code).toList();
      final match = exact.length == 1 ? exact.first : (results.length == 1 ? results.first : null);
      if (match != null) {
        _addLine(match);
        _searchController.clear();
        ref.read(barcodeProductSearchProvider.notifier).state = '';
      }
    } catch (_) {
      // تُترك الأخطاء لطلب البحث العادي عبر barcodeProductResultsProvider
    }
  }

  void _addLine(Map<String, dynamic> product) {
    final id = product['id'] as String;
    _PrintLine? existing;
    for (final line in _lines) {
      if (line.productId == id) {
        existing = line;
        break;
      }
    }
    final barcodeValue = (product['barcode'] as String?)?.trim();
    setState(() {
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _lines.add(_PrintLine(
          productId: id,
          name: product['name'] as String? ?? '',
          barcodeValue: (barcodeValue == null || barcodeValue.isEmpty) ? (product['sku'] as String? ?? id) : barcodeValue,
          sku: product['sku'] as String? ?? '',
          price: (product['salePrice'] as num?)?.toDouble() ?? 0,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);
    final resultsAsync = ref.watch(barcodeProductResultsProvider);
    final branding = ref.watch(brandingProvider).valueOrNull;
    final currencySymbol = branding?.currencySymbol ?? 'د.ل';

    final settingsPanel = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تصميم الملصق', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _widthController,
                  enabled: widget.canEdit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'العرض (ملم)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _heightController,
                  enabled: widget.canEdit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الارتفاع (ملم)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('اسم الصنف'),
            value: _showName,
            onChanged: widget.canEdit ? (v) => setState(() => _showName = v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('سعر البيع'),
            value: _showPrice,
            onChanged: widget.canEdit ? (v) => setState(() => _showPrice = v) : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('رمز الصنف (SKU)'),
            value: _showSku,
            onChanged: widget.canEdit ? (v) => setState(() => _showSku = v) : null,
          ),
          const SizedBox(height: 12),
          Text('معاينة تقريبية', style: AppTextStyles.labelMd()),
          const SizedBox(height: 8),
          Center(child: _LabelPreview(
            widthMm: _widthMm,
            heightMm: _heightMm,
            showName: _showName,
            showPrice: _showPrice,
            showSku: _showSku,
            currencySymbol: currencySymbol,
          )),
          if (widget.canEdit) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: _savingSettings ? null : _saveSettings,
                child: _savingSettings
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ التصميم'),
              ),
            ),
          ],
        ],
      ),
    );

    final printPanel = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('طباعة ملصقات', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            onSubmitted: _onSearchSubmitted,
            decoration: const InputDecoration(hintText: 'ابحث أو امسح باركود صنف لإضافته...', prefixIcon: Icon(Icons.search, size: 18)),
          ),
          const SizedBox(height: 8),
          resultsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (products) => products.isEmpty
                ? const SizedBox.shrink()
                : SizedBox(
                    height: 140,
                    child: ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final p = products[index];
                        return ListTile(
                          dense: true,
                          title: Text(p['name'] as String? ?? ''),
                          subtitle: Text(p['barcode'] as String? ?? p['sku'] as String? ?? ''),
                          trailing: const Icon(Icons.add_circle_outline, size: 18),
                          onTap: () => _addLine(p),
                        );
                      },
                    ),
                  ),
          ),
          const Divider(height: 24),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('لم تُضف أصناف بعد', style: AppTextStyles.bodyMd()),
            )
          else
            ..._lines.map((line) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(line.name, style: AppTextStyles.bodyMd(color: AppColors.textPrimary))),
                      IconAction(
                        icon: Icons.remove_circle_outline,
                        iconSize: 18,
                        dense: true,
                        tooltip: line.quantity > 1
                            ? 'إنقاص كمية ${line.name}'
                            : 'إزالة ${line.name} من القائمة',
                        onPressed: () => setState(() {
                          if (line.quantity > 1) {
                            line.quantity -= 1;
                          } else {
                            _lines.remove(line);
                          }
                        }),
                      ),
                      SizedBox(width: 36, child: Text('${line.quantity}', textAlign: TextAlign.center)),
                      IconAction(
                        icon: Icons.add_circle_outline,
                        iconSize: 18,
                        dense: true,
                        tooltip: 'زيادة كمية ${line.name}',
                        onPressed: () => setState(() => line.quantity += 1),
                      ),
                    ],
                  ),
                )),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: (_printing || _lines.isEmpty) ? null : () => _print(currencySymbol),
            icon: _printing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.print_outlined, size: 18),
            label: Text('طباعة ${_lines.fold<int>(0, (sum, l) => sum + l.quantity)} ملصق'),
          ),
        ],
      ),
    );

    return isDesktop
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: settingsPanel),
                const SizedBox(width: 20),
                Expanded(child: printPanel),
              ],
            ),
          )
        : Column(children: [settingsPanel, const SizedBox(height: 20), printPanel]);
  }

  Future<void> _saveSettings() async {
    setState(() {
      _savingSettings = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/organizations/me/barcode-template', data: {
        'widthMm': _widthMm,
        'heightMm': _heightMm,
        'showName': _showName,
        'showPrice': _showPrice,
        'showSku': _showSku,
      });
      ref.invalidate(barcodeTemplateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تصميم الملصق')));
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ التصميم'));
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _print(String currencySymbol) async {
    setState(() {
      _printing = true;
      _error = null;
    });

    try {
      final doc = pw.Document(theme: await arabicPdfTheme());
      final labelWidgets = <pw.Widget>[];

      for (final line in _lines) {
        for (var i = 0; i < line.quantity; i++) {
          labelWidgets.add(_buildPdfLabel(line, currencySymbol));
        }
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10 * PdfPageFormat.mm),
          textDirection: pw.TextDirection.rtl,
          build: (context) => [
            pw.Wrap(spacing: 6, runSpacing: 6, children: labelWidgets),
          ],
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => doc.save());
    } catch (_) {
      setState(() => _error = 'تعذّر إنشاء ملف الطباعة');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  pw.Widget _buildPdfLabel(_PrintLine line, String currencySymbol) {
    return pw.Container(
      width: _widthMm * PdfPageFormat.mm,
      height: _heightMm * PdfPageFormat.mm,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5, color: PdfColors.grey700)),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (_showName)
            pdfAutoDir(
              line.name,
              style: const pw.TextStyle(fontSize: 7),
              textAlign: pw.TextAlign.center,
              maxLines: 1,
            ),
          // الباركود والسعر ورمز الصنف كلها محتوى لاتيني/رقمي يقلبه اتجاه
          // الصفحة العربية إن تُرك له — راجع [pdfLtr].
          pw.Expanded(
            child: pdfLtr(pw.BarcodeWidget(
              data: line.barcodeValue,
              barcode: pw.Barcode.code128(),
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 6),
            )),
          ),
          if (_showPrice)
            pdfLtr(pw.Text('${line.price.toStringAsFixed(2)} $currencySymbol', style: const pw.TextStyle(fontSize: 7))),
          if (_showSku)
            pdfLtr(pw.Text(line.sku, style: const pw.TextStyle(fontSize: 6))),
        ],
      ),
    );
  }
}

/// معاينة حقيقية (وليست تقريبية شكلياً فقط) — تستخدم نفس مكتبة [barcode]
/// المستخدَمة في توليد PDF الطباعة، فقط عبر CustomPainter بدل pw.Widget،
/// حتى لا تُوهم المعاينة بشكل مختلف عمّا سيُطبع فعلياً.
class _LabelPreview extends StatelessWidget {
  const _LabelPreview({
    required this.widthMm,
    required this.heightMm,
    required this.showName,
    required this.showPrice,
    required this.showSku,
    required this.currencySymbol,
  });

  final double widthMm;
  final double heightMm;
  final bool showName;
  final bool showPrice;
  final bool showSku;
  final String currencySymbol;

  static const _scale = 3.0; // بكسل لكل ملم على الشاشة فقط (لا علاقة بحجم PDF الفعلي)

  @override
  Widget build(BuildContext context) {
    final width = (widthMm * _scale).clamp(60, 400).toDouble();
    final height = (heightMm * _scale).clamp(40, 300).toDouble();

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showName)
            // ux-audit: ignore AC-02 — معاينة ملصق 30×20 مم بمقاسه الحقيقي؛
            // تكبير الخط هنا يجعل المعاينة تكذب على المستخدم بشأن ما سيُطبع.
            const Text('اسم الصنف', style: TextStyle(fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
          Expanded(
            child: CustomPaint(painter: _BarcodePainter('0123456789'), child: Container()),
          ),
          // ux-audit: ignore AC-02 — كما أعلاه: مقاس الطباعة لا مقاس الشاشة.
          if (showPrice) Text('0.00 $currencySymbol', style: const TextStyle(fontSize: 9)),
          // ux-audit: ignore AC-02 — كما أعلاه.
          if (showSku) const Text('SKU-0000', style: TextStyle(fontSize: 8)),
        ],
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()..color = Colors.black;
    final elements = bc.Barcode.code128().make(data, width: size.width, height: size.height);
    for (final el in elements) {
      if (el is bc.BarcodeBar && el.black) {
        canvas.drawRect(Rect.fromLTWH(el.left, el.top, el.width, el.height), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) => oldDelegate.data != data;
}
