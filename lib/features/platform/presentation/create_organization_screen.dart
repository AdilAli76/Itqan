import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/platform_organizations_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../core/auth/permissions.dart';

// ux-audit: ignore UX-03 — قائمة المنظمات على الخادم، يراها مالك المنصة
// وحده وعددها بعشرات على الأكثر في نشر داخلي.

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

const _planTierLabels = {
  'trial': 'تجريبية',
  'standard': 'قياسية',
  'professional': 'احترافية',
  'enterprise': 'مؤسسات',
};

/// شاشة تزويد عملاء جدد — مقصورة على مالك المنصة (is_platform_admin في
/// التوكن). كل استدعاء ناجح يبني منظمة كاملة جاهزة للعمل فوراً: منظمة +
/// فرع أول + ترخيص + مستخدم مدير عام، بدل تنفيذ SQL يدوي في كل مرة تبيع
/// فيها نسخة جديدة من النظام.
class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  bool? _isPlatformAdmin;

  @override
  void initState() {
    super.initState();
    readJwtClaims().then((claims) {
      if (mounted) {
        setState(() => _isPlatformAdmin = claims?['is_platform_admin'] == 'True');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'إنشاء منظمة جديدة',
      activeRoute: '/platform/organizations/new',
      body: _isPlatformAdmin == null
          ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          // رسالة الرفض الموحَّدة بدل نصّ خاص بهذه الشاشة: المستخدم يجب أن
          // يتعرّف على «ليست لك صلاحية» بشكلها نفسه أينما وقعت في النظام.
          : _isPlatformAdmin == false
              ? const NoPermissionView(moduleName: 'إدارة المنصّة')
              : const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrganizationsList(),
                    SizedBox(height: 20),
                    _CreateOrganizationForm(),
                  ],
                ),
    );
  }
}

class _OrganizationsList extends ConsumerWidget {
  const _OrganizationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(platformOrganizationsProvider);

    return orgsAsync.when(
      loading: () => const TableSkeleton(),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Column(
          children: [
            Text('تعذّر تحميل قائمة المنظمات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => ref.invalidate(platformOrganizationsProvider), child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
      data: (orgs) => AppDataTable(
        title: 'المنظمات المزوَّدة على هذا السيرفر (${orgs.length})',
        columns: const [
          AppColumn('الاسم القانوني'),
          AppColumn('الاسم المعروض'),
          AppColumn('الحالة'),
          AppColumn('تاريخ الإنشاء'),
        ],
        rows: orgs.map((o) {
          final isActive = o['isActive'] as bool? ?? true;
          final createdAt = DateTime.tryParse(o['createdAt'] as String? ?? '');
          return [
            Text(o['legalName'] as String? ?? ''),
            Text(o['displayName'] as String? ?? ''),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isActive ? 'نشطة' : 'معطَّلة', style: AppTextStyles.labelMd(color: isActive ? AppColors.success : AppColors.danger)),
            ),
            Text(createdAt != null ? DateFormat('yyyy-MM-dd').format(createdAt) : '-'),
          ];
        }).toList(),
      ),
    );
  }
}

class _CreateOrganizationForm extends ConsumerStatefulWidget {
  const _CreateOrganizationForm();

  @override
  ConsumerState<_CreateOrganizationForm> createState() => _CreateOrganizationFormState();
}

class _CreateOrganizationFormState extends ConsumerState<_CreateOrganizationForm> {
  final _formKey = GlobalKey<FormState>();

  final _legalNameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _branchNameController = TextEditingController(text: 'الفرع الرئيسي');
  final _branchCodeController = TextEditingController(text: 'MAIN-01');
  final _monthsController = TextEditingController(text: '12');

  String _planTier = 'professional';
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _legalNameController.dispose();
    _displayNameController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    _branchNameController.dispose();
    _branchCodeController.dispose();
    _monthsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_result != null) ...[
              _ResultBanner(result: _result!, adminEmail: _adminEmailController.text.trim()),
              const SizedBox(height: 20),
            ],
            Text('بيانات المنظمة (العميل)', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _legalNameController,
                    decoration: const InputDecoration(labelText: 'الاسم القانوني'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(labelText: 'الاسم المعروض في النظام'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('المدير العام للعميل', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 4),
            Text('هذه بيانات الدخول الأولى التي ستسلّمها للعميل.', style: AppTextStyles.bodyMd()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _adminNameController,
                    decoration: const InputDecoration(labelText: 'اسم المدير العام'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _adminEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'بريد إلكتروني غير صحيح' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _adminPasswordController,
              decoration: const InputDecoration(labelText: 'كلمة المرور الأولى (8 أحرف على الأقل)'),
              validator: (v) => (v == null || v.length < 8) ? '8 أحرف على الأقل' : null,
            ),
            const SizedBox(height: 24),
            Text('الفرع الأول', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _branchNameController,
                    decoration: const InputDecoration(labelText: 'اسم الفرع'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _branchCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'رمز الفرع'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('الترخيص', style: AppTextStyles.headlineMd()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _planTier,
                    decoration: const InputDecoration(labelText: 'الباقة'),
                    items: _planTierLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _planTier = v ?? 'professional'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _monthsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'مدة الترخيص (بالأشهر)'),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'رقم غير صحيح' : null,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('إنشاء المنظمة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });

    try {
      final response = await ApiClient.instance.dio.post('/platform/organizations', data: {
        'legalName': _legalNameController.text.trim(),
        'displayName': _displayNameController.text.trim(),
        'adminFullName': _adminNameController.text.trim(),
        'adminEmail': _adminEmailController.text.trim(),
        'adminPassword': _adminPasswordController.text,
        'branchName': _branchNameController.text.trim(),
        'branchCode': _branchCodeController.text.trim(),
        'planTier': _planTier,
        'licenseMonths': int.parse(_monthsController.text.trim()),
      });
      setState(() => _result = response.data as Map<String, dynamic>);
      ref.invalidate(platformOrganizationsProvider);
      _formKey.currentState!.reset();
      _legalNameController.clear();
      _displayNameController.clear();
      _adminNameController.clear();
      _adminPasswordController.clear();
      _branchNameController.text = 'الفرع الرئيسي';
      _branchCodeController.text = 'MAIN-01';
      _monthsController.text = '12';
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر إنشاء المنظمة'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result, required this.adminEmail});
  final Map<String, dynamic> result;
  final String adminEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تم إنشاء المنظمة بنجاح — سلّم هذه البيانات للعميل:',
              style: AppTextStyles.labelMd(color: AppColors.success)),
          const SizedBox(height: 8),
          SelectableText('البريد: $adminEmail', style: AppTextStyles.bodyMd()),
          SelectableText('مفتاح الترخيص: ${result['licenseKey']}', style: AppTextStyles.bodyMd()),
          SelectableText('ينتهي بتاريخ: ${result['expiresAt']}', style: AppTextStyles.bodyMd()),
        ],
      ),
    );
  }
}
