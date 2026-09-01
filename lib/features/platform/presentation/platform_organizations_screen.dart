import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/printing/contract_printer.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';
import '../data/platform_organizations_providers.dart';
import '../../../core/time/app_clock.dart';
import 'organization_users_dialog.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

const _editionLabels = {
  'standard': 'قياسي',
  'wallet': 'المحفظة',
  'wallet_plus': 'المحفظة بالمحاسبة',
  'trial': 'تجريبي',
  'enterprise': 'مؤسسات',
};

const _tierLabels = {
  'trial': 'تجريبية',
  'standard': 'قياسية',
  'professional': 'احترافية',
  'enterprise': 'مؤسسات',
};

/// نصّ الخطأ كما يقوله الخادم — بما فيه الرمز المرجعي إن وُجد.
String _errorDetail(Object err) {
  if (err is DioException) {
    final data = err.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
    if (err.response == null) return 'لا اتصال بالخادم — تحقّق من الشبكة.';
    return 'ردّ الخادم بالحالة ${err.response?.statusCode}.';
  }
  return err.toString();
}

/// إدارة الشركات المشترَكة — مقصورة على مالك المنصة.
///
/// كانت الشاشة الوحيدة المتاحة له هي «إنشاء منظمة»: يُنشئ العميل ثم لا يملك
/// بعدها تصحيح اسم كُتب خطأً، ولا تمديد ترخيص انتهى، ولا إيقاف عميل توقّف
/// عن السداد. وكلها عمليات يومية في تشغيل منصّة تُباع لعملاء.
class PlatformOrganizationsScreen extends ConsumerWidget {
  const PlatformOrganizationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(platformOrganizationsProvider);

    return AdaptiveScaffold(
      title: 'الشركات المشترَكة',
      activeRoute: '/platform/organizations',
      // القائمة تمرّر نفسها: لفّها بمُمرِّر خارجي يعطيها ارتفاعاً غير محدود
      // فتنهار بـ«Vertical viewport was given unbounded height» — شاشةٌ
      // بيضاء عند المستخدم بلا رسالة. راجع AdaptiveScaffold.scrollable.
      scrollable: false,
      body: orgsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // رسالة الخادم كما هي لا نصٌّ عامّ.
        //
        // «تعذّر تحميل الشركات» وحدها طريقٌ مسدود: لا المستخدم يعرف ماذا
        // يفعل، ولا الدعم يعرف أين يبحث. والخادم يُرسل الآن رمزاً مرجعياً
        // مع كل عطب غير متوقّع — عرضُه هو ما يجعل الشكوى قابلة للتتبّع.
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تعذّر تحميل الشركات',
                    style: AppTextStyles.headlineMd(color: AppColors.danger)),
                const SizedBox(height: 8),
                Text(_errorDetail(err),
                    style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(platformOrganizationsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('أعد المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (orgs) {
          if (orgs.isEmpty) {
            return Center(
              child: Text('لا شركات بعد — أنشئ أول عميل من «إنشاء منظمة جديدة»',
                  style: AppTextStyles.bodyMd()),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orgs.length,
            itemBuilder: (context, i) => _OrgCard(org: orgs[i]),
          );
        },
      ),
    );
  }
}

class _OrgCard extends ConsumerWidget {
  const _OrgCard({required this.org});
  final Map<String, dynamic> org;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = org['isActive'] as bool? ?? true;
    final expiresRaw = org['licenseExpiresAt'] as String?;
    final expires = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    final expired = expires != null && expires.isBefore(AppClock.now());

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
                        Text(org['displayName'] as String? ?? '', style: AppTextStyles.headlineMd()),
                        Text(org['legalName'] as String? ?? '',
                            style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (!isActive)
                    _tag('موقوفة', AppColors.danger)
                  else if (expired)
                    _tag('ترخيص منتهٍ', AppColors.warning)
                  else
                    _tag('نشطة', AppColors.success),
                ],
              ),
              const Divider(height: 20),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  // «—» لا «null»: القيمة قد تغيب فعلاً — منظمةٌ أُنشئت
                  // قبل ترحيل عمود الإصدار تحمله NULL. وطباعة اسم القيمة
                  // الفارغة كما هي تُظهر كلمة برمجية للمستخدم بدل أن تقول
                  // له إن البيانات ناقصة.
                  _fact('الإصدار', _labelOr(_editionLabels, org['edition'])),
                  _fact('الباقة', _labelOr(_tierLabels, org['planTier'])),
                  _fact('الفروع', '${org['branchCount'] ?? 0}'),
                  _fact('المستخدمون', '${org['userCount'] ?? 0}'),
                  _fact('انتهاء الترخيص', expires == null ? '—' : _dateFormat.format(expires)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _EditOrgDialog(org: org),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                  // إعادة طباعة العقد بالشروط المحفوظة — لا بقيم تُكتب من
                  // جديد. نسختان بمبلغين مختلفين أسوأ من غياب العقد.
                  OutlinedButton.icon(
                    onPressed: () => _printContract(context, org),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('طباعة العقد'),
                  ),
                  // حسابات المنظمة: بريد المدير وكلمة مروره يُدخَلان مرّةً
                  // عند الإنشاء ثم لا يظهران في أي شاشة. فمن نسي بريده أو
                  // أُدخل خطأً لم يكن له طريق إلا قاعدة البيانات.
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => OrganizationUsersDialog(org: org),
                    ),
                    icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                    label: const Text('الحسابات'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// التسمية العربية للقيمة، أو القيمة نفسها، أو «—» إن غابت.
  static String _labelOr(Map<String, String> labels, Object? value) {
    if (value == null) return '—';
    final key = '$value';
    if (key.isEmpty || key == 'null') return '—';
    return labels[key] ?? key;
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

class _EditOrgDialog extends ConsumerStatefulWidget {
  const _EditOrgDialog({required this.org});
  final Map<String, dynamic> org;

  @override
  ConsumerState<_EditOrgDialog> createState() => _EditOrgDialogState();
}

class _EditOrgDialogState extends ConsumerState<_EditOrgDialog> {
  late final _legalController = TextEditingController(text: widget.org['legalName'] as String? ?? '');
  late final _displayController = TextEditingController(text: widget.org['displayName'] as String? ?? '');
  late bool _isActive = widget.org['isActive'] as bool? ?? true;
  late String _planTier = widget.org['planTier'] as String? ?? 'standard';
  int _extendMonths = 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _legalController.dispose();
    _displayController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/platform/organizations/${widget.org['id']}', data: {
        'legalName': _legalController.text.trim(),
        'displayName': _displayController.text.trim(),
        'isActive': _isActive,
        'planTier': _tierLabels.containsKey(_planTier) ? _planTier : null,
        'extendMonths': _extendMonths > 0 ? _extendMonths : null,
      });
      ref.invalidate(platformOrganizationsProvider);
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.response?.data is Map
            ? (e.response!.data['message'] as String? ?? 'تعذّر الحفظ')
            : 'تعذّر الحفظ';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialog(
      title: 'تعديل بيانات الشركة',
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
                controller: _legalController,
                decoration: const InputDecoration(labelText: 'الاسم القانوني'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _displayController,
                decoration: const InputDecoration(labelText: 'الاسم المعروض'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tierLabels.containsKey(_planTier) ? _planTier : null,
                decoration: const InputDecoration(labelText: 'الباقة'),
                items: _tierLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _planTier = v ?? _planTier),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _extendMonths,
                decoration: const InputDecoration(labelText: 'تمديد الترخيص'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('بلا تمديد')),
                  DropdownMenuItem(value: 1, child: Text('شهر')),
                  DropdownMenuItem(value: 3, child: Text('٣ أشهر')),
                  DropdownMenuItem(value: 6, child: Text('٦ أشهر')),
                  DropdownMenuItem(value: 12, child: Text('سنة')),
                ],
                onChanged: (v) => setState(() => _extendMonths = v ?? 0),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الشركة نشطة'),
                subtitle: Text(
                  'الإيقاف يمنع دخول كل مستخدميها.',
                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                ),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              // الإصدار لا يُعدَّل هنا بقصد: تغييره على شركة عاملة يُخفي
              // وحدات فيها بيانات قائمة — مخزون وأوامر شراء لا تعود مرئية
              // لأحد. وهو قرار يُتَّخذ عند الإنشاء.
              const SizedBox(height: 4),
              Text(
                'الإصدار: ${_editionLabels[widget.org['edition']] ?? widget.org['edition']} — '
                'لا يُغيَّر بعد الإنشاء.',
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


const _tierLimits = {
  'trial': (1, 3),
  'standard': (3, 10),
  'professional': (10, 50),
  'enterprise': (999, 999),
};

Future<void> _printContract(BuildContext context, Map<String, dynamic> org) async {
  Map<String, dynamic> platform = const {};
  try {
    final res = await ApiClient.instance.dio.get('/platform-settings');
    platform = Map<String, dynamic>.from(res.data as Map);
  } catch (_) {}

  final tier = org['planTier'] as String? ?? 'standard';
  final limits = _tierLimits[tier] ?? (1, 5);
  final issued = DateTime.tryParse(org['licenseIssuedAt'] as String? ?? '') ??
      DateTime.tryParse(org['createdAt'] as String? ?? '') ??
      DateTime.now();
  final expires = DateTime.tryParse(org['licenseExpiresAt'] as String? ?? '') ??
      issued.add(const Duration(days: 365));

  await printSubscriptionContract(
    orgLegalName: org['legalName'] as String? ?? '',
    orgDisplayName: org['displayName'] as String? ?? '',
    edition: org['edition'] as String? ?? 'standard',
    planTier: _tierLabels[tier] ?? tier,
    issuedAt: issued,
    expiresAt: expires,
    maxBranches: limits.$1,
    maxUsers: limits.$2,
    monthlyFee: ((org['monthlyFee'] as num?) ?? 0).toDouble(),
    storageFee: ((org['storageFee'] as num?) ?? 0).toDouble(),
    maintenanceRate: ((org['maintenanceRate'] as num?) ?? 0).toDouble(),
    currencySymbol: 'د.ل',
    providerName: platform['companyName'] as String? ?? 'مزوّد النظام',
    providerOwner: platform['ownerName'] as String?,
    providerPhone: platform['phone'] as String?,
    providerEmail: platform['email'] as String?,
    providerAddress: platform['address'] as String?,
  );
}
