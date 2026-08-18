import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/inventory_providers.dart';
import 'import_products_dialog.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../shared/widgets/app_surface.dart';

/// شاشة "المخزون والموردين" — تجمع الموديولين لأن هذا نمط الشاشة الوحيد
/// المسجَّل في القائمة الجانبية (راجع app_sidebar.dart)، بدل تقسيمهما إلى
/// مسارين منفصلين لا حاجة فعلية لهما بهذا الحجم من الشاشات.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  int _tab = 0; // 0 = الأصناف، 1 = الموردون

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'إدارة المخزون والموردين',
      activeRoute: '/inventory',
      actions: [
        // الاستيراد في تبويب الأصناف فقط — لا معنى له للموردين، وإظهاره
        // هناك كان سيوحي بأنه يستورد ملف موردين.
        if (_tab == 0)
          OutlinedButton.icon(
            onPressed: () => _openImportDialog(context),
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('استيراد من ملف'),
          ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _tab == 0 ? _openProductDialog(context) : _openSupplierDialog(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(_tab == 0 ? 'إضافة صنف' : 'إضافة مورد'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
          const SizedBox(height: 16),
          if (_tab == 0)
            _ProductsSection(onEdit: (p) => _openProductDialog(context, product: p))
          else
            _SuppliersSection(onEdit: (s) => _openSupplierDialog(context, supplier: s)),
        ],
      ),
    );
  }

  Future<void> _openProductDialog(BuildContext context, {Map<String, dynamic>? product}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductFormDialog(product: product),
    );
    if (saved == true) {
      ref.invalidate(productsInventoryProvider);
    }
  }

  Future<void> _openImportDialog(BuildContext context) async {
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => const ImportProductsDialog(),
    );
    // تحديث القائمة فقط عند استيراد فعلي — الخروج بعد المعاينة لا يغيّر شيئاً.
    if (imported == true) ref.invalidate(productsInventoryProvider);
  }

  Future<void> _openSupplierDialog(BuildContext context, {Map<String, dynamic>? supplier}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(supplier: supplier),
    );
    if (saved == true) {
      ref.invalidate(suppliersProvider);
    }
  }
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabChip(label: 'الأصناف', selected: index == 0, onTap: () => onChanged(0)),
        const SizedBox(width: 8),
        _TabChip(label: 'الموردون', selected: index == 1, onTap: () => onChanged(1)),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        // 44 أدنى هدف لمس؛ الحشو وحده كان يعطي 39.
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMd(color: selected ? color : AppColors.textSecondary)
              .copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الأصناف
// ---------------------------------------------------------------------------

class _ProductsSection extends ConsumerStatefulWidget {
  const _ProductsSection({required this.onEdit});
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  ConsumerState<_ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends ConsumerState<_ProductsSection> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // بدون تأخير بسيط هنا، كل ضغطة مفتاح في البحث كانت ستطلق طلب HTTP جديد
  // فوراً — وميض في القائمة واحتمال وصول ردّين بترتيب معكوس.
  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(productSearchProvider.notifier).state = value;
      ref.read(productsPageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsInventoryProvider);

    return productsAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(
        message: 'تعذّر تحميل الأصناف',
        onRetry: () => ref.invalidate(productsInventoryProvider),
      ),
      data: (products) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDataTable(
            title: 'الأصناف (${products.totalCount})',
            onSearch: _onSearch,
            columns: const [
              AppColumn('الصنف'),
              AppColumn('الباركود'),
              AppColumn('التصنيف'),
              AppColumn('المورد'),
              AppColumn('الكمية'),
              AppColumn('سعر البيع'),
              AppColumn('الحالة'),
              AppColumn(''),
            ],
            rows: products.items.map((p) => _productRow(context, ref, p)).toList(),
          ),
          PaginationBar(
            page: products.page,
            pageSize: products.pageSize,
            totalCount: products.totalCount,
            onPageChanged: (p) => ref.read(productsPageProvider.notifier).state = p,
          ),
        ],
      ),
    );
  }

  List<Widget> _productRow(BuildContext context, WidgetRef ref, Map<String, dynamic> p) {
    final quantity = (p['quantity'] as num?)?.toDouble() ?? 0;
    final reorderLevel = (p['reorderLevel'] as num?)?.toDouble() ?? 0;
    final trackExpiry = p['trackExpiry'] as bool? ?? false;
    final tracksStock = p['tracksStock'] as bool? ?? true;
    final nearestExpiry =
        p['nearestExpiryDate'] != null ? DateTime.tryParse(p['nearestExpiryDate'] as String) : null;

    return [
      Text(p['name'] as String? ?? ''),
      Text(p['barcode'] as String? ?? '-'),
      Text(p['categoryName'] as String? ?? '-'),
      Text(p['supplierName'] as String? ?? '-'),
      Text(tracksStock ? NumberFormat('#,##0.###', 'en').format(quantity) : '—'),
      CurrencyBadge(amount: (p['salePrice'] as num?)?.toDouble() ?? 0),
      _stockStatusTag(
        quantity: quantity,
        reorderLevel: reorderLevel,
        trackExpiry: trackExpiry,
        expiry: nearestExpiry,
        tracksStock: tracksStock,
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تعديل الكمية',
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            onPressed: () async {
              final adjusted = await showDialog<bool>(
                context: context,
                builder: (_) => _StockAdjustmentDialog(product: p),
              );
              if (adjusted == true) ref.invalidate(productsInventoryProvider);
            },
          ),
          IconButton(
            tooltip: 'تعديل الصنف',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => widget.onEdit(p),
          ),
          IconButton(
            tooltip: 'حذف الصنف',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmDeleteProduct(context, ref, p),
          ),
        ],
      ),
    ];
  }

  Widget _stockStatusTag({
    required double quantity,
    required double reorderLevel,
    required bool trackExpiry,
    required DateTime? expiry,
    required bool tracksStock,
  }) {
    // الصنف غير المتتبَّع مخزنياً كميته صفر دائماً بحكم تعريفه، فوسمه
    // "نفاد المخزون" إنذار كاذب دائم.
    if (!tracksStock) {
      return _tag('قيمة مفتوحة', AppColors.info, AppColors.infoBg);
    }
    if (quantity <= 0) {
      return _tag('نفاد المخزون', AppColors.danger, AppColors.dangerBg);
    }
    if (trackExpiry && expiry != null) {
      final daysLeft = expiry.difference(DateTime.now()).inDays;
      if (daysLeft < 0) return _tag('منتهي الصلاحية', AppColors.danger, AppColors.dangerBg);
      if (daysLeft <= 7) return _tag('ينتهي خلال $daysLeft أيام', AppColors.warning, AppColors.warningBg);
    }
    if (quantity <= reorderLevel) {
      return _tag('مخزون منخفض', AppColors.warning, AppColors.warningBg);
    }
    return _tag('سليم', AppColors.success, AppColors.successBg);
  }

  Widget _tag(String label, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: AppTextStyles.labelMd(color: fg)),
      );

  Future<void> _confirmDeleteProduct(BuildContext context, WidgetRef ref, Map<String, dynamic> p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الصنف'),
        content: Text('هل تريد حذف "${p['name']}"؟ يمكن استرجاعه لاحقاً من سجل التدقيق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.dio.delete('/products/${p['id']}');
      ref.invalidate(productsInventoryProvider);
    } catch (_) {
      if (context.mounted) _showError(context, 'تعذّر حذف الصنف');
    }
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Text(message, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// نموذج إضافة/تعديل صنف
// ---------------------------------------------------------------------------

class _ProductFormDialog extends ConsumerStatefulWidget {
  const _ProductFormDialog({this.product});
  final Map<String, dynamic>? product;

  @override
  ConsumerState<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.product?['name'] as String?);
  late final _skuController = TextEditingController(text: widget.product?['sku'] as String?);
  late final _barcodeController = TextEditingController(text: widget.product?['barcode'] as String?);
  late final _costController =
      TextEditingController(text: (widget.product?['costPrice'] as num?)?.toString() ?? '0');
  late final _saleController =
      TextEditingController(text: (widget.product?['salePrice'] as num?)?.toString() ?? '0');
  late final _reorderController =
      TextEditingController(text: (widget.product?['reorderLevel'] as num?)?.toString() ?? '0');

  static const _units = {'piece': 'قطعة', 'box': 'كرتون', 'kg': 'كيلوجرام', 'litre': 'لتر'};

  late String _unitBase = widget.product?['unitBase'] as String? ?? 'piece';
  late bool _trackExpiry = widget.product?['trackExpiry'] as bool? ?? false;
  late bool _tracksStock = widget.product?['tracksStock'] as bool? ?? true;
  // `late` إلزامي هنا: حقول الحالة غير النهائية التي تقرأ widget داخل
  // مُهيّئ الحقل تُنفَّذ أثناء بناء الكائن (قبل أن يربط الإطار widget
  // بالـ State)، فالقراءة المباشرة تُطلق استثناء عند الإنشاء.
  late String? _categoryId = widget.product?['categoryId'] as String?;
  late String? _supplierId = widget.product?['supplierId'] as String?;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.product != null;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _costController.dispose();
    _saleController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final suppliersAsync = ref.watch(suppliersProvider);

    return AlertDialog(
      title: Text(_isEdit ? 'تعديل صنف' : 'إضافة صنف جديد'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم الصنف'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _skuController,
                        decoration: const InputDecoration(labelText: 'رمز الصنف (SKU)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration: const InputDecoration(labelText: 'الباركود'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: categoriesAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, __) => const Text('تعذّر تحميل الفئات'),
                        data: (categories) => DropdownButtonFormField<String?>(
                          initialValue: _categoryId,
                          decoration: const InputDecoration(labelText: 'الفئة'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('بدون فئة')),
                            ...categories.map((c) => DropdownMenuItem(
                                  value: c['id'] as String,
                                  child: Text(c['name'] as String),
                                )),
                          ],
                          onChanged: (v) => setState(() => _categoryId = v),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إضافة فئة جديدة',
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: _addCategory,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                suppliersAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('تعذّر تحميل الموردين'),
                  data: (suppliers) => DropdownButtonFormField<String?>(
                    initialValue: _supplierId,
                    decoration: const InputDecoration(labelText: 'المورد'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('بدون مورد')),
                      ...suppliers.map((s) => DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(s['name'] as String),
                          )),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _unitBase,
                  decoration: const InputDecoration(labelText: 'وحدة البيع'),
                  items: _units.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _unitBase = v ?? 'piece'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                        validator: _numberValidator,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _saleController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'سعر البيع'),
                        validator: _numberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reorderController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'حد إعادة الطلب'),
                  validator: _numberValidator,
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('يتطلب تتبع تاريخ الصلاحية'),
                  value: _trackExpiry,
                  onChanged: _tracksStock ? (v) => setState(() => _trackExpiry = v) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('متتبَّع في المخزون'),
                  subtitle: Text(
                    _tracksStock
                        ? 'يُخصم من رصيد المخزون عند البيع، ويُرفض البيع إن نفد'
                        : 'خدمة أو قيمة مفتوحة — يُباع بلا رصيد مخزون، وتُكتب قيمته عند البيع',
                    style: AppTextStyles.bodyMd(),
                  ),
                  value: _tracksStock,
                  onChanged: (v) => setState(() {
                    _tracksStock = v;
                    // صنف بلا مخزون لا معنى لتتبّع صلاحيته ولا لحد إعادة طلبه.
                    if (!v) _trackExpiry = false;
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }

  String? _numberValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
    return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة فئة جديدة'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'اسم الفئة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final response = await ApiClient.instance.dio.post('/categories', data: {'name': name});
      ref.invalidate(categoriesProvider);
      setState(() => _categoryId = response.data['id'] as String);
    } catch (_) {
      if (mounted) _showError(context, 'تعذّر إضافة الفئة');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final body = {
      'name': _nameController.text.trim(),
      'sku': _skuController.text.trim(),
      'barcode': _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
      'unitBase': _unitBase,
      'unitConversionFactor': 1,
      'categoryId': _categoryId,
      'supplierId': _supplierId,
      'costPrice': double.parse(_costController.text),
      'salePrice': double.parse(_saleController.text),
      'reorderLevel': double.parse(_reorderController.text),
      'trackExpiry': _trackExpiry,
      'tracksStock': _tracksStock,
    };

    try {
      if (_isEdit) {
        await ApiClient.instance.dio.put('/products/${widget.product!['id']}', data: body);
      } else {
        await ApiClient.instance.dio.post('/products', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الصنف'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// تعديل الكمية (جرد سريع)
// ---------------------------------------------------------------------------

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({required this.product});
  final Map<String, dynamic> product;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _batchController = TextEditingController();
  DateTime? _expiryDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantityController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackExpiry = widget.product['trackExpiry'] as bool? ?? false;

    return AlertDialog(
      title: Text('تعديل كمية: ${widget.product['name']}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الكمية الحالية: ${NumberFormat('#,##0.###', 'en').format((widget.product['quantity'] as num?) ?? 0)}',
                style: AppTextStyles.bodyMd(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'الفرق (+ للإضافة، - للخصم)',
                  hintText: 'مثال: 20 أو -5',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
                  return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _batchController,
                decoration: const InputDecoration(labelText: 'رقم الدفعة (اختياري)'),
              ),
              if (trackExpiry) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiryDate == null
                            ? 'بدون تاريخ صلاحية'
                            : 'ينتهي: ${DateFormat('yyyy-MM-dd').format(_expiryDate!)}',
                        style: AppTextStyles.bodyMd(),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(const Duration(days: 30)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) setState(() => _expiryDate = picked);
                      },
                      child: const Text('اختيار تاريخ'),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ApiClient.instance.dio.post('/products/${widget.product['id']}/stock-adjustments', data: {
        'quantityDelta': double.parse(_quantityController.text),
        'batchNumber': _batchController.text.trim().isEmpty ? null : _batchController.text.trim(),
        'expiryDate': _expiryDate?.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تعديل الكمية'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// الموردون
// ---------------------------------------------------------------------------

class _SuppliersSection extends ConsumerStatefulWidget {
  const _SuppliersSection({required this.onEdit});
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  ConsumerState<_SuppliersSection> createState() => _SuppliersSectionState();
}

class _SuppliersSectionState extends ConsumerState<_SuppliersSection> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(supplierSearchProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);

    return suppliersAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(
        message: 'تعذّر تحميل الموردين',
        onRetry: () => ref.invalidate(suppliersProvider),
      ),
      data: (suppliers) => AppDataTable(
        title: 'الموردون (${suppliers.length})',
        onSearch: _onSearch,
        columns: const [
          AppColumn('اسم المورد'),
          AppColumn('الهاتف'),
          AppColumn('الرصيد'),
          AppColumn(''),
        ],
        rows: suppliers.map((s) {
          final balance = (s['balance'] as num?)?.toDouble() ?? 0;
          return [
            Text(s['name'] as String? ?? ''),
            Text(s['phone'] as String? ?? '-'),
            CurrencyBadge(amount: balance, showSign: balance != 0),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => widget.onEdit(s),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _confirmDeleteSupplier(context, ref, s),
                ),
              ],
            ),
          ];
        }).toList(),
      ),
    );
  }

  Future<void> _confirmDeleteSupplier(BuildContext context, WidgetRef ref, Map<String, dynamic> s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف المورد'),
        content: Text('هل تريد حذف "${s['name']}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.dio.delete('/suppliers/${s['id']}');
      ref.invalidate(suppliersProvider);
    } catch (_) {
      if (context.mounted) _showError(context, 'تعذّر حذف المورد');
    }
  }
}

class _SupplierFormDialog extends StatefulWidget {
  const _SupplierFormDialog({this.supplier});
  final Map<String, dynamic>? supplier;

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.supplier?['name'] as String?);
  late final _phoneController = TextEditingController(text: widget.supplier?['phone'] as String?);
  late final _balanceController =
      TextEditingController(text: (widget.supplier?['balance'] as num?)?.toString() ?? '0');
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.supplier != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل مورد' : 'إضافة مورد جديد'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم المورد'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration:
                    const InputDecoration(labelText: 'الرصيد الحالي', helperText: 'موجب = نحن مدينون له'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
                  return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final body = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'balance': double.parse(_balanceController.text),
    };

    try {
      if (_isEdit) {
        await ApiClient.instance.dio.put('/suppliers/${widget.supplier!['id']}', data: body);
      } else {
        await ApiClient.instance.dio.post('/suppliers', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ المورد'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
