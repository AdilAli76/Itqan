import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import '../../../shared/widgets/app_surface.dart';
import '../data/platform_organizations_providers.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

/// مهندسو البيع — وكلاءُ يبيعون النظام تحت ترخيص مالك المنصّة.
///
/// <para><b>ما يفرّقهم عنه:</b> يرون ما باعوه وحدهم، ولا يحذفون منظمة،
/// ولا يُنشئون مهندساً آخر. وما عدا ذلك يملكونه — إنشاء عميل وتمديد
/// ترخيصه وبيع الوحدات فوق إصداره — وإلّا كانوا مسوّقين يرجعون في كل
/// تجديد لا بائعين.</para>
///
/// <para><b>والحارس الفعلي على الخادم</b> ([PlatformScope])، لا هنا:
/// إخفاء الشاشة لا يمنع نداءً يُرسَل من أي أداة بتوكن صالح.</para>
class PlatformEngineersBody extends ConsumerWidget {
  const PlatformEngineersBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformEngineersProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(engineerErrorText(err, 'تعذّر تحميل حسابات المنصّة'),
              style: AppTextStyles.bodyMd(color: AppColors.danger),
              textAlign: TextAlign.center),
        ),
      ),
      data: (rows) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'المهندس يبيع تحت ترخيصك ويرى عملاءه وحدهم. '
                    'ولا يحذف منظمة ولا يُنشئ مهندساً.',
                    style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _CreateEngineerDialog(),
                  ),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('مهندس جديد'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (context, i) => _EngineerCard(row: rows[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _EngineerCard extends ConsumerWidget {
  const _EngineerCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = row['platformRole'] == 'owner';
    final isActive = row['isActive'] as bool? ?? true;
    final created = DateTime.tryParse('${row['createdAt']}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppSurface(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${row['fullName']}', style: AppTextStyles.headlineMd()),
                        Text('${row['email']}',
                            style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  _tag(isOwner ? 'مالك المنصّة' : 'مهندس بيع',
                      isOwner ? AppColors.success : AppColors.textSecondary),
                  if (!isActive) ...[
                    const SizedBox(width: 6),
                    _tag('موقوف', AppColors.danger),
                  ],
                ],
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _fact('رقم الترخيص', '${row['resellerLicense']}'),
                  _fact('عملاؤه', '${row['organizationCount'] ?? 0}'),
                  _fact('أُنشئ', created == null ? '—' : _dateFormat.format(created)),
                ],
              ),
              const SizedBox(height: 12),
              // ولا زرّ حذف: حسابٌ باع عملاء يبقى مرجعاً لهم في العقود
              // وفي نسبة كل منظمة. والإيقاف يمنع الدخول ويُبقي الأثر —
              // نفس منطق تعطيل مستخدمي المنظمة لا حذفهم.
              OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _EditEngineerDialog(row: row),
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: AppTextStyles.bodyMd(color: color)),
      );

  Widget _fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.labelMd()),
        ],
      );
}

class _CreateEngineerDialog extends ConsumerStatefulWidget {
  const _CreateEngineerDialog();

  @override
  ConsumerState<_CreateEngineerDialog> createState() => _CreateEngineerDialogState();
}

class _CreateEngineerDialogState extends ConsumerState<_CreateEngineerDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _created;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio.post('/platform/engineers', data: {
        'fullName': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
      });
      ref.invalidate(platformEngineersProvider);
      if (!mounted) return;
      // رقم الترخيص يُعرَض بعد الإنشاء لا يُطوى: يولّده الخادم، ومن
      // أنشأ الحساب يحتاج أن يسلّمه لصاحبه — وإخفاؤه يعني بحثاً عنه في
      // قائمة بعد إغلاق الحوار.
      setState(() {
        _saving = false;
        _created = '${(res.data as Map)['resellerLicense']}';
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = engineerErrorText(e, 'تعذّر إنشاء الحساب');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_created != null) {
      return AdaptiveDialog(
        title: 'أُنشئ حساب المهندس',
        maxWidth: 420,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('تمّ'),
          ),
        ],
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('رقم ترخيصه:', style: AppTextStyles.bodyMd()),
            const SizedBox(height: 4),
            SelectableText(_created!, style: AppTextStyles.headlineMd()),
            const SizedBox(height: 10),
            Text(
              'يُطبع في عقد كل عميل يبيعه. سلّمه بريده وكلمة مروره — '
              'وكلمة المرور لا تُعرض بعد إغلاق هذه النافذة.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return AdaptiveDialog(
      title: 'حساب مهندس بيع جديد',
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('إنشاء'),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم الكامل'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور',
              helperText: 'ثمانية أحرف فأكثر — تُسلَّم له ويغيّرها',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'رقم الترخيص يولّده النظام ويظهر بعد الإنشاء.',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}

class _EditEngineerDialog extends ConsumerStatefulWidget {
  const _EditEngineerDialog({required this.row});
  final Map<String, dynamic> row;

  @override
  ConsumerState<_EditEngineerDialog> createState() => _EditEngineerDialogState();
}

class _EditEngineerDialogState extends ConsumerState<_EditEngineerDialog> {
  late final _name = TextEditingController(text: '${widget.row['fullName']}');
  late final _license = TextEditingController(text: '${widget.row['resellerLicense']}');
  late bool _isActive = widget.row['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/platform/engineers/${widget.row['id']}', data: {
        'fullName': _name.text.trim(),
        'isActive': _isActive,
        'resellerLicense': _license.text.trim(),
      });
      ref.invalidate(platformEngineersProvider);
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = engineerErrorText(e, 'تعذّر الحفظ');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'تعديل حساب المنصّة',
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم الكامل'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _license,
            decoration: const InputDecoration(
              labelText: 'رقم الترخيص',
              helperText: 'يُطبع في عقود عملائه — بدّله برقم وكالة حقيقي إن وُجد',
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الحساب نشط'),
            subtitle: Text(
              'الإيقاف يمنع دخوله ويُبقي عملاءه منسوبين إليه.',
              style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
            ),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
        ],
      ),
    );
  }
}

/// نصّ الخطأ كما يقوله الخادم — ومعه حالته حين لا يقول شيئاً.
///
/// نفس درس حوار الحسابات: رسالةٌ عامّة واحدة لثلاثة أعطاب مختلفة لا
/// يُميَّز بينها إلا بفتح شاشة الشبكة.
String engineerErrorText(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (error.response == null) return 'لا اتصال بالخادم — تحقّق من الشبكة.';
    return '$fallback — ردّ الخادم بالحالة ${error.response?.statusCode}.';
  }
  return '$fallback — ردٌّ غير متوقَّع من الخادم ($error).';
}
