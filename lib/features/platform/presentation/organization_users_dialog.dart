import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl يصدّر TextDirection خاصّاً به بثوابت أخرى (LTR/RTL) فيحجب نوع
// Flutter ذا ltr/rtl. وإخفاؤه أوضح من كتابة بادئة على كل استعمال.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/network/api_client.dart';
import '../../../core/shortcuts/keyboard_shortcuts_manager.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

/// مستخدمو منظمة عميل — لمالك المنصّة.
final organizationUsersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, organizationId) async {
  final response =
      await ApiClient.instance.dio.get('/platform/organizations/$organizationId/users');
  return (response.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// حسابات منظمة عميل: عرضها، وتصحيح بياناتها، وإعادة كلمات مرورها.
///
/// <para><b>الفجوة التي تسدّها:</b> بريد مدير المنظمة وكلمة مروره يُدخَلان
/// **مرّةً واحدة** عند الإنشاء ثم لا يظهران في أي شاشة. فإن نسي المدير
/// بريده، أو أُدخل بحرفٍ خاطئ، أو طلب إعادة كلمة مروره — لم يكن ثمّة طريق
/// إلا فتح قاعدة البيانات يدوياً.</para>
class OrganizationUsersDialog extends ConsumerWidget {
  const OrganizationUsersDialog({super.key, required this.org});

  final Map<String, dynamic> org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgId = '${org['id']}';
    final async = ref.watch(organizationUsersProvider(orgId));

    return AlertDialog(
      title: Text('حسابات ${org['displayName']}'),
      content: SizedBox(
        width: 620,
        child: async.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Text(
            _errorText(err, 'تعذّر تحميل الحسابات'),
            style: AppTextStyles.bodyMd(color: AppColors.danger),
          ),
          data: (users) {
            if (users.isEmpty) {
              return Text('لا حسابات في هذه المنظمة', style: AppTextStyles.bodyMd());
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final user in users) _UserTile(orgId: orgId, user: user),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.orgId, required this.user});

  final String orgId;
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = user['isActive'] as bool? ?? true;
    final lastLogin = DateTime.tryParse('${user['lastLoginAt']}');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${user['fullName']}', style: AppTextStyles.bodyLg()),
                      const SizedBox(height: 2),
                      // البريد قابل للنسخ: يُملى هاتفياً للعميل عادةً،
                      // وإعادة كتابته باليد تُدخل الخطأ الذي جئنا نصلحه.
                      SelectableText(
                        '${user['email']}',
                        style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (!isActive)
                  Text('موقوف', style: AppTextStyles.caption(color: AppColors.danger)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الدور: ${user['role']}'
              '${(user['isPlatformAdmin'] as bool? ?? false) ? ' · مالك منصّة' : ''}'
              ' · آخر دخول: ${lastLogin == null ? 'لم يدخل بعد' : _dateFormat.format(lastLogin)}',
              style: AppTextStyles.caption(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _edit(context, ref),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('تصحيح البيانات'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _resetPassword(context, ref),
                  icon: const Icon(Icons.key_outlined, size: 16),
                  label: const Text('إعادة كلمة المرور'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditUserDialog(orgId: orgId, user: user),
    );
    if (saved == true) ref.invalidate(organizationUsersProvider(orgId));
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // يولّدها النظام لا مالك المنصّة: كلمةٌ يختارها هو يعرفها هو،
              // فيستطيع الدخول بحساب العميل بلا أثر يميّزه عن صاحبه.
              'يولّد النظام كلمة مؤقّتة تُعرَض مرّةً واحدة. سلّمها لصاحب '
              'الحساب ليغيّرها. ولن تظهر مرّةً أخرى.',
              style: AppTextStyles.bodyMd(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'سبب إعادة التعيين',
                hintText: 'طلب العميل · نسي كلمته',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تراجع')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('إعادة التعيين'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await ApiClient.instance.dio.post(
        '/platform/organizations/$orgId/users/${user['id']}/reset-password',
        data: {'reason': reason},
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _TemporaryPasswordDialog(
          email: '${response.data['email']}',
          password: '${response.data['temporaryPassword']}',
        ),
      );
    } on DioException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorText(e, 'تعذّرت إعادة التعيين'))),
      );
    }
  }
}

/// الكلمة المؤقّتة — تُعرَض مرّةً ولا تُسترجَع.
class _TemporaryPasswordDialog extends StatelessWidget {
  const _TemporaryPasswordDialog({required this.email, required this.password});

  final String email;
  final String password;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('كلمة المرور المؤقّتة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email, style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              password,
              // لاتينية دائماً يساراً: الكلمة تُقرأ حرفاً حرفاً، وعكسُها
              // باتجاه الصفحة العربية يجعلها تُملى خطأً.
              textDirection: TextDirection.ltr,
              style: AppTextStyles.headlineMd(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'لن تظهر مرّةً أخرى. انسخها الآن وسلّمها لصاحب الحساب.',
            style: AppTextStyles.caption(color: AppColors.warning),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: password));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('نُسخت كلمة المرور')));
          },
          child: const Text('نسخ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('نسختُها'),
        ),
      ],
    );
  }
}

class _EditUserDialog extends ConsumerStatefulWidget {
  const _EditUserDialog({required this.orgId, required this.user});

  final String orgId;
  final Map<String, dynamic> user;

  @override
  ConsumerState<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<_EditUserDialog> {
  late final _name = TextEditingController(text: '${widget.user['fullName']}');
  late final _email = TextEditingController(text: '${widget.user['email']}');
  late bool _isActive = widget.user['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveFormDialog(
      title: 'تصحيح بيانات الحساب',
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('تراجع'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
        ),
      ],
      body: EnterAdvancesFocus(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  helperText: 'هو اسم الدخول — تغييره يغيّر ما يكتبه صاحبه',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('الحساب نشط'),
                subtitle: Text(
                  // الإيقاف لا الحذف: حسابٌ محذوف تبقى فواتيره تشير إليه.
                  'الإيقاف يمنع الدخول ويُبقي أثره في السجلّات',
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/platform/organizations/${widget.orgId}/users/${widget.user['id']}',
        data: {
          'fullName': _name.text.trim(),
          'email': _email.text.trim(),
          'isActive': _isActive,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error = _errorText(e, 'تعذّر الحفظ');
      });
    }
  }
}

String _errorText(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}
