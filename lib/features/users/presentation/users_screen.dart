import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_form_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../branches/data/branches_providers.dart';
import '../data/users_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/app_surface.dart';

// ux-audit: ignore UX-03 — مستخدمو المنظمة عشرات لا آلاف، وعددهم مقيَّد
// بالتراخيص أصلاً (راجع شاشة الترخيص). البحث الموجود يكفي.

const _roleLabels = {
  'super_admin': 'مدير عام',
  'branch_manager': 'مدير فرع',
  'cashier': 'كاشير',
  'inventory_officer': 'مسؤول مخزون',
  'accountant': 'محاسب',
  'custom': 'دور مخصّص (راجع مصفوفة الصلاحيات)',
};

String _roleLabel(String role) => _roleLabels[role] ?? role;

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  int _tab = 0; // 0 = المستخدمون، 1 = سجل تسجيل الدخول

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'الصلاحيات والمستخدمون',
      activeRoute: '/users',
      actions: [
        if (_tab == 0)
          ElevatedButton.icon(
            onPressed: () => _openUserDialog(context),
            icon: const Icon(Icons.person_add_alt_outlined, size: 18),
            label: const Text('إضافة مستخدم'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap لا Row: شريط الفلاتر يفيض على عرض الهاتف. الالتفاف يبقي
          // كل فلتر ظاهراً وقابلاً للنقر بدل قصّ آخره بصمت.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TabChip(label: 'المستخدمون', selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
              const SizedBox(width: 8),
              _TabChip(label: 'سجل تسجيل الدخول', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == 0)
            _UsersSection(onEdit: (u) => _openUserDialog(context, user: u))
          else
            const _LoginHistorySection(),
        ],
      ),
    );
  }

  Future<void> _openUserDialog(BuildContext context, {Map<String, dynamic>? user}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(user: user),
    );
    if (saved == true) {
      ref.invalidate(usersProvider);
    }
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

// ---------------------------------------------------------------------------
// المستخدمون
// ---------------------------------------------------------------------------

class _UsersSection extends ConsumerStatefulWidget {
  const _UsersSection({required this.onEdit});
  final ValueChanged<Map<String, dynamic>> onEdit;

  @override
  ConsumerState<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends ConsumerState<_UsersSection> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(userSearchProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final branchesAsync = ref.watch(branchesProvider);

    return usersAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(message: 'تعذّر تحميل المستخدمين', onRetry: () => ref.invalidate(usersProvider)),
      data: (users) {
        final branchNames = <String, String>{
          for (final b in branchesAsync.value ?? const <Map<String, dynamic>>[])
            b['id'] as String: b['name'] as String,
        };

        return AppDataTable(
          title: 'المستخدمون (${users.length})',
          onSearch: _onSearch,
          columns: const [
            AppColumn('الاسم'),
            AppColumn('البريد الإلكتروني'),
            AppColumn('اسم المستخدم'),
            AppColumn('الدور'),
            AppColumn('الفرع'),
            AppColumn('الحالة'),
            AppColumn(''),
          ],
          rows: users.map((u) => _userRow(context, u, branchNames)).toList(),
        );
      },
    );
  }

  List<Widget> _userRow(BuildContext context, Map<String, dynamic> u, Map<String, String> branchNames) {
    final isActive = u['isActive'] as bool? ?? true;
    final branchId = u['branchId'] as String?;

    return [
      Text(u['fullName'] as String? ?? ''),
      Text(u['email'] as String? ?? ''),
      Text(u['username'] as String? ?? '-'),
      Text(_roleLabel(u['role'] as String? ?? '')),
      Text(branchId == null ? 'كل الفروع' : (branchNames[branchId] ?? '-')),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.successBg : AppColors.dangerBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(isActive ? 'نشط' : 'معطَّل', style: AppTextStyles.labelMd(color: isActive ? AppColors.success : AppColors.danger)),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'تعديل',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => widget.onEdit(u),
          ),
          IconButton(
            tooltip: 'إعادة تعيين كلمة المرور',
            icon: const Icon(Icons.lock_reset_outlined, size: 18),
            onPressed: () async {
              final done = await showDialog<bool>(
                context: context,
                builder: (_) => _ResetPasswordDialog(user: u),
              );
              if (done == true && context.mounted) {
                _showError(context, 'تم تحديث كلمة المرور');
              }
            },
          ),
        ],
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// نموذج إضافة/تعديل مستخدم
// ---------------------------------------------------------------------------

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog({this.user});
  final Map<String, dynamic>? user;

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.user?['fullName'] as String?);
  late final _emailController = TextEditingController(text: widget.user?['email'] as String?);
  late final _usernameController = TextEditingController(text: widget.user?['username'] as String?);
  final _passwordController = TextEditingController();

  late String _role = widget.user?['role'] as String? ?? 'cashier';
  late String? _branchId = widget.user?['branchId'] as String?;
  late bool _isActive = widget.user?['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.user != null;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);

    return AdaptiveFormDialog(
      title: _isEdit ? 'تعديل مستخدم' : 'إضافة مستخدم جديد',
      maxWidth: 400,
      body: Form(
        key: _formKey,
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  enabled: !_isEdit,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم مستخدم مختصر (اختياري)',
                    hintText: 'مثال: ahmed — لتسجيل دخول أسهل من البريد الكامل',
                  ),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    validator: (v) {
                      if (v == null || v.length < 6) return '6 أحرف على الأقل';
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'الدور'),
                  items: _roleLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                ),
                const SizedBox(height: 12),
                branchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('تعذّر تحميل الفروع'),
                  data: (branches) => DropdownButtonFormField<String?>(
                    initialValue: _branchId,
                    decoration: const InputDecoration(labelText: 'الفرع'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل الفروع (مدير عام)')),
                      ...branches.map((b) => DropdownMenuItem(
                            value: b['id'] as String,
                            child: Text(b['name'] as String),
                          )),
                    ],
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                ),
                // كاشير بلا فرع لا يستطيع فتح نقطة البيع إطلاقاً: الفرع
                // يُقرأ من ادّعاء branch_id في التوكن، ولا يُضاف الادّعاء
                // أصلاً لمستخدم بلا فرع (AuthController). فالحساب يُنشأ
                // ويُسجّل دخوله بنجاح، ثم ترفضه الشاشة الوحيدة التي أُنشئ
                // لأجلها — بلا ما يربط الرفض بسببه.
                if (_role == 'cashier' && _branchId == null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_outlined, size: 18, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'كاشير بلا فرع لن يستطيع فتح نقطة البيع — اختر فرعاً.',
                            style: AppTextStyles.bodyMd(color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isEdit) ...[
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('حساب نشط'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                ],
              ],
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
      if (_isEdit) {
        await ApiClient.instance.dio.put('/users/${widget.user!['id']}', data: {
          'fullName': _nameController.text.trim(),
          'username': _usernameController.text.trim(),
          'role': _role,
          'branchId': _branchId,
          'isActive': _isActive,
        });
      } else {
        await ApiClient.instance.dio.post('/users', data: {
          'fullName': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
          'branchId': _branchId,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ المستخدم'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// إعادة تعيين كلمة المرور
// ---------------------------------------------------------------------------

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.user});
  final Map<String, dynamic> user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('كلمة مرور جديدة: ${widget.user['fullName']}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 320,
          child: TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة',
              errorText: _error,
            ),
            validator: (v) => (v == null || v.length < 6) ? '6 أحرف على الأقل' : null,
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
      await ApiClient.instance.dio.post('/users/${widget.user['id']}/reset-password', data: {
        'newPassword': _passwordController.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تحديث كلمة المرور'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// سجل تسجيل الدخول
// ---------------------------------------------------------------------------

class _LoginHistorySection extends ConsumerWidget {
  const _LoginHistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(loginHistoryProvider);

    return historyAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(message: 'تعذّر تحميل سجل تسجيل الدخول', onRetry: () => ref.invalidate(loginHistoryProvider)),
      data: (history) => AppDataTable(
        title: 'سجل تسجيل الدخول (${history.length})',
        columns: const [
          AppColumn('التاريخ'),
          AppColumn('المستخدم'),
          AppColumn('النتيجة'),
          AppColumn('عنوان IP'),
          AppColumn('الجهاز'),
        ],
        rows: history.map((h) {
          final createdAt = DateTime.tryParse(h['createdAt'] as String? ?? '');
          final success = h['success'] as bool? ?? false;
          return [
            Text(createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(createdAt) : '-'),
            Text(h['userName'] as String? ?? '-'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: success ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(success ? 'نجاح' : 'فشل', style: AppTextStyles.labelMd(color: success ? AppColors.success : AppColors.danger)),
            ),
            Text(h['ipAddress'] as String? ?? '-'),
            Text(
              h['deviceInfo'] as String? ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ];
        }).toList(),
      ),
    );
  }
}
