import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/permissions_providers.dart';

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

const _roleLabels = {
  'branch_manager': 'مدير فرع',
  'cashier': 'كاشير',
  'inventory_officer': 'مسؤول مخزون',
  'accountant': 'محاسب',
  'custom': 'دور مخصّص',
};

const _moduleLabels = {
  'inventory': 'المخزون',
  'suppliers': 'الموردون',
  'stock_transfer': 'تحويل المخزون',
  'stock_count': 'الجرد الدوري',
  'customers': 'العملاء',
  'invoices': 'الفواتير',
  'reports': 'التقارير',
  'audit_log': 'سجل التدقيق',
  'license': 'الترخيص',
};

const _moduleIcons = {
  'inventory': Icons.inventory_2_outlined,
  'suppliers': Icons.local_shipping_outlined,
  'stock_transfer': Icons.sync_alt_outlined,
  'stock_count': Icons.fact_check_outlined,
  'customers': Icons.people_outline,
  'invoices': Icons.receipt_long_outlined,
  'reports': Icons.bar_chart_outlined,
  'audit_log': Icons.history_outlined,
  'license': Icons.verified_user_outlined,
};

/// تحويل الأدوار الثابتة (المُبرمَجة سابقاً مباشرة في كل Controller) إلى
/// مصفوفة قابلة للتخصيص فعلياً من هنا — كل تغيير يُطبَّق فوراً في الباك اند
/// (RequirePermissionAttribute.cs يقرأ من نفس جدول role_permissions).
/// مثال: منح "كاشير" صلاحيات محاسب وأمين مخزن معاً = تفعيل صناديقهما هنا.
class PermissionsMatrixScreen extends ConsumerStatefulWidget {
  const PermissionsMatrixScreen({super.key});

  @override
  ConsumerState<PermissionsMatrixScreen> createState() => _PermissionsMatrixScreenState();
}

class _PermissionsMatrixScreenState extends ConsumerState<PermissionsMatrixScreen> {
  bool? _isSuperAdmin;
  String _selectedRole = 'branch_manager';

  @override
  void initState() {
    super.initState();
    readJwtClaims().then((claims) {
      if (mounted) setState(() => _isSuperAdmin = claims?['role'] == 'super_admin');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'مصفوفة الصلاحيات',
      activeRoute: '/permissions',
      body: _isSuperAdmin == null
          ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          : _isSuperAdmin == false
              ? Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('هذه الصفحة مخصَّصة للمدير العام فقط.', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                )
              : _MatrixBody(
                  selectedRole: _selectedRole,
                  onSelectRole: (r) => setState(() => _selectedRole = r),
                ),
    );
  }
}

class _MatrixBody extends ConsumerStatefulWidget {
  const _MatrixBody({required this.selectedRole, required this.onSelectRole});
  final String selectedRole;
  final ValueChanged<String> onSelectRole;

  @override
  ConsumerState<_MatrixBody> createState() => _MatrixBodyState();
}

class _MatrixBodyState extends ConsumerState<_MatrixBody> {
  Set<String>? _editedCodes;
  String? _loadedForRole;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(permissionsCatalogProvider);
    final matrixAsync = ref.watch(permissionsMatrixProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: _roleLabels.entries.map((e) {
            final selected = widget.selectedRole == e.key;
            return InkWell(
              onTap: () {
                setState(() => _editedCodes = null); // إعادة القراءة من المصفوفة عند تغيير الدور
                widget.onSelectRole(e.key);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : AppColors.border),
                ),
                child: Text(e.value, style: AppTextStyles.labelMd(color: selected ? Theme.of(context).colorScheme.primary : AppColors.textSecondary)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        catalogAsync.when(
          loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          error: (_, __) => Text('تعذّر تحميل كتالوج الصلاحيات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
          data: (catalog) => matrixAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            error: (_, __) => Text('تعذّر تحميل مصفوفة الصلاحيات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
            data: (matrix) {
              if (_loadedForRole != widget.selectedRole) {
                _editedCodes = {...(matrix[widget.selectedRole] ?? const [])};
                _loadedForRole = widget.selectedRole;
              }
              final grouped = <String, List<Map<String, dynamic>>>{};
              for (final p in catalog) {
                grouped.putIfAbsent(p['module'] as String, () => []).add(p);
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('صلاحيات دور "${_roleLabels[widget.selectedRole]}"', style: AppTextStyles.headlineMd()),
                  const SizedBox(height: 4),
                  Text('التفعيل هنا يُطبَّق فوراً على كل مستخدم بهذا الدور في منظمتك.', style: AppTextStyles.bodyMd()),
                  const SizedBox(height: 16),
                  ...grouped.entries.map((moduleGroup) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SectionCard(
                          title: _moduleLabels[moduleGroup.key] ?? moduleGroup.key,
                          icon: _moduleIcons[moduleGroup.key],
                          children: [
                            Wrap(
                              children: moduleGroup.value.map((p) {
                                final code = p['code'] as String;
                                final checked = _editedCodes!.contains(code);
                                return SizedBox(
                                  width: 340,
                                  child: CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(p['labelAr'] as String, style: AppTextStyles.bodyMd()),
                                    value: checked,
                                    onChanged: (v) => setState(() {
                                      if (v == true) {
                                        _editedCodes!.add(code);
                                      } else {
                                        _editedCodes!.remove(code);
                                      }
                                    }),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      )),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('حفظ'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/permissions/matrix', data: {
        'role': widget.selectedRole,
        'permissionCodes': _editedCodes!.toList(),
      });
      ref.invalidate(permissionsMatrixProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الصلاحيات')));
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الصلاحيات'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
