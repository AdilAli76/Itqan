import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../data/medicine_reference_providers.dart';

/// إدارة نشرات الأدوية — لمالك المنصّة.
///
/// <b>لماذا شاشة واحدة لكل العملاء:</b> الجدول على مستوى المنصّة لا المنظمة
/// (راجع MedicineReference في Entities.cs). «باراسيتامول 500 مجم» له نفس
/// موانع الاستعمال في كل صيدلية، فإدخاله مرّة واحدة هنا يجعله متاحاً لكل
/// عملاء إصدار الصيدليات — بينما ربطه بالمنظمة كان يعني أن كل عميل جديد
/// يبدأ بنشرات فارغة يُدخلها من الصفر، فتُهمَل الميزة عملياً.
///
/// ولهذا الكتابة محصورة بمالك المنصّة: صفٌّ واحد يراه الجميع، وتركه لكل
/// منظمة يعني أن صيدلية تُفسد نشرة تظهر لبقية الصيدليات.
class MedicineReferenceScreen extends ConsumerStatefulWidget {
  const MedicineReferenceScreen({super.key});

  @override
  ConsumerState<MedicineReferenceScreen> createState() => _MedicineReferenceScreenState();
}

class _MedicineReferenceScreenState extends ConsumerState<MedicineReferenceScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(medicineRefSearchProvider.notifier).state = value;
      ref.read(medicineRefPageProvider.notifier).state = 1;
    });
  }

  Future<void> _openDialog({Map<String, dynamic>? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MedicineFormDialog(item: item),
    );
    if (saved == true) ref.invalidate(medicineRefsProvider);
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف النشرة'),
        content: Text('حذف نشرة «${item['name']}»؟ الأصناف المرتبطة بها في كل '
            'المنظمات تبقى كما هي، وتختفي عنها النشرة فقط.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.dio.delete('/medicine-reference/${item['id']}');
      ref.invalidate(medicineRefsProvider);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.statusCode == 403
            ? 'إدارة النشرات لمالك المنصّة وحده'
            : 'تعذّر الحذف')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final refsAsync = ref.watch(medicineRefsProvider);

    return AdaptiveScaffold(
      title: 'نشرات الأدوية',
      activeRoute: '/medicine-reference',
      actions: [
        FilledButton.icon(
          onPressed: () => _openDialog(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('إضافة نشرة'),
        ),
      ],
      body: refsAsync.when(
        loading: () => const TableSkeleton(),
        error: (err, _) => AppSurface(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  // 403 هنا حالة متوقَّعة لا عطل: الشاشة لا تُفتح إلا لمالك
                  // المنصّة، لكن الوحدة قد تكون غير مفعَّلة في بيئة تجربة.
                  err is DioException && err.response?.statusCode == 403
                      ? 'وحدة الصيدليات غير مفعَّلة لهذا الحساب'
                      : 'تعذّر تحميل النشرات',
                  style: AppTextStyles.bodyMd(color: AppColors.danger),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(medicineRefsProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (page) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDataTable(
              title: 'نشرات الأدوية (${page.totalCount})',
              icon: Icons.medical_information_outlined,
              onSearch: _onSearch,
              emptyMessage: 'لا نشرات بعد — أضف أول نشرة من زر «إضافة نشرة»',
              emptyIcon: Icons.medical_information_outlined,
              columns: const [
                AppColumn('الاسم'),
                AppColumn('المادة الفعّالة'),
                AppColumn('التركيز'),
                AppColumn('الشكل'),
                AppColumn('بوصفة'),
                AppColumn(''),
              ],
              rows: page.items.map(_row).toList(),
            ),
            PaginationBar(
              page: page.page,
              pageSize: page.pageSize,
              totalCount: page.totalCount,
              onPageChanged: (p) => ref.read(medicineRefPageProvider.notifier).state = p,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _row(Map<String, dynamic> m) {
    final requiresPrescription = m['requiresPrescription'] == true;
    return [
      Text(m['name'] as String? ?? ''),
      Text(m['activeIngredient'] as String? ?? '-'),
      Text(m['strength'] as String? ?? '-'),
      Text(m['form'] as String? ?? '-'),
      // المقيَّد بوصفة يُميَّز بلونه في القائمة: هو ما يُراجَع أولاً عند
      // مراجعة الكتالوج، وقراءته من عمود نصّي رمادي تُضيّعه.
      requiresPrescription
          ? Text('نعم',
              style: AppTextStyles.bodyMd(color: AppColors.danger)
                  .copyWith(fontWeight: FontWeight.w600))
          : Text('—', style: AppTextStyles.bodyMd()),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openDialog(item: m),
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _confirmDelete(m),
          ),
        ],
      ),
    ];
  }
}

/// نموذج إضافة/تعديل نشرة — نافذة واحدة للحالتين عبر [item].
class _MedicineFormDialog extends StatefulWidget {
  const _MedicineFormDialog({this.item});
  final Map<String, dynamic>? item;

  @override
  State<_MedicineFormDialog> createState() => _MedicineFormDialogState();
}

class _MedicineFormDialogState extends State<_MedicineFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.item?['name'] as String?);
  late final _ingredient = TextEditingController(text: widget.item?['activeIngredient'] as String?);
  late final _strength = TextEditingController(text: widget.item?['strength'] as String?);
  late final _form = TextEditingController(text: widget.item?['form'] as String?);
  late final _indications = TextEditingController(text: widget.item?['indications'] as String?);
  late final _contraindications =
      TextEditingController(text: widget.item?['contraindications'] as String?);
  late final _cautions = TextEditingController(text: widget.item?['cautions'] as String?);
  late final _sideEffects = TextEditingController(text: widget.item?['sideEffects'] as String?);
  late bool _requiresPrescription = widget.item?['requiresPrescription'] == true;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name, _ingredient, _strength, _form,
      _indications, _contraindications, _cautions, _sideEffects,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    String? trimmed(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final body = {
      'name': _name.text.trim(),
      'activeIngredient': _ingredient.text.trim(),
      'strength': trimmed(_strength),
      'form': trimmed(_form),
      'indications': trimmed(_indications),
      'contraindications': trimmed(_contraindications),
      'cautions': trimmed(_cautions),
      'sideEffects': trimmed(_sideEffects),
      'requiresPrescription': _requiresPrescription,
    };

    try {
      final id = widget.item?['id'] as String?;
      if (id == null) {
        await ApiClient.instance.dio.post('/medicine-reference', data: body);
      } else {
        await ApiClient.instance.dio.put('/medicine-reference/$id', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = e.response?.statusCode == 403
            ? 'إدارة النشرات لمالك المنصّة وحده'
            : (e.response?.data is Map
                ? (e.response!.data['message'] as String? ?? 'تعذّر الحفظ')
                : 'تعذّر الحفظ');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: widget.item == null ? 'نشرة دواء جديدة' : 'تعديل النشرة',
      maxWidth: 520,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
      body: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'الاسم التجاري *', hintText: 'كما يُعرَف في السوق'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ingredient,
                  decoration: const InputDecoration(
                      labelText: 'المادة الفعّالة *', hintText: 'Paracetamol'),
                  // مطلوبة لأنها أساس البحث عن بديل: الصيدلي يبحث عن بديل
                  // لدواء ناقص، والبديل يشترك في المادة لا في الاسم التجاري.
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'المادة الفعّالة مطلوبة' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _strength,
                        decoration: const InputDecoration(
                            labelText: 'التركيز', hintText: '500 مجم'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _form,
                        decoration: const InputDecoration(
                            labelText: 'الشكل الصيدلي', hintText: 'أقراص، شراب، حقن'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _multiline(_indications, 'دواعي الاستعمال'),
                _multiline(_contraindications, 'موانع الاستعمال'),
                _multiline(_cautions, 'تحذيرات'),
                _multiline(_sideEffects, 'أعراض جانبية'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _requiresPrescription,
                  onChanged: (v) => setState(() => _requiresPrescription = v),
                  title: const Text('يُصرَف بوصفة طبية'),
                  subtitle: Text(
                    'يظهر تحذيراً أحمر للكاشير في نقطة البيع قبل أي تفصيل آخر.',
                    style: AppTextStyles.caption(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
            ),
          ),
    );
  }

  Widget _multiline(TextEditingController controller, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
        ),
      );
}
