import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/permissions.dart';
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
  'pharmacy': 'الصيدليات',
  'trial': 'تجريبي',
  'enterprise': 'مؤسسات',
};

/// أسماء الوحدات كما تُعرض لمالك المنصّة — تقابل `Editions.AllModules`.
///
/// وحدةٌ تُضاف في الخادم ولا تُضاف هنا تظهر باسمها البرمجي لا تختفي (راجع
/// [_ModulesField])، فيبقى بيعها ممكناً وإن قبُح اسمها.
const _moduleLabels = {
  'pos': 'نقطة البيع',
  'customers': 'العملاء والبطاقات',
  'reports': 'التقارير',
  'inventory': 'المخزون والمشتريات',
  'warehouses': 'المستودعات',
  'valuation': 'تقييم المخزون',
  'procurement': 'أوامر الشراء وفواتير الموردين',
  'accounting': 'المحاسبة والدفاتر',
  'wallet': 'بطاقات ومرتَّبات المنتسبين',
  'pharmacy': 'نشرة الدواء',
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
    return const AdaptiveScaffold(
      title: 'الشركات المشترَكة',
      activeRoute: '/platform/organizations',
      // القائمة تمرّر نفسها: لفّها بمُمرِّر خارجي يعطيها ارتفاعاً غير محدود
      // فتنهار بـ«Vertical viewport was given unbounded height» — شاشةٌ
      // بيضاء عند المستخدم بلا رسالة. راجع AdaptiveScaffold.scrollable.
      scrollable: false,
      body: PlatformOrganizationsBody(),
    );
  }
}

/// قائمة العملاء بلا هيكل شاشة — لتصلح تبويباً داخل لوحة المنصّة.
///
/// <para><b>ولماذا فُصلت:</b> «لوحة المنصّة» و«الشركات المشترَكة» و«إنشاء
/// منظمة» كانت ثلاثة بنودٍ متجاورة لعملٍ واحد. ودمجُها بفتح الشاشة كاملةً
/// داخل تبويب يعني هيكلَ شاشةٍ داخل هيكل شاشة — شريطَي عنوان وقائمتَي
/// أوامر. فالجسم وحده هو ما يُعاد استعماله، والشاشة أعلاه تبقى غلافاً
/// رقيقاً للمسار القديم.</para>
class PlatformOrganizationsBody extends ConsumerWidget {
  const PlatformOrganizationsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgsAsync = ref.watch(platformOrganizationsProvider);

    return orgsAsync.when(
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
              child: Text('لا شركات بعد — أنشئ أول عميل من «عميل جديد»',
                  style: AppTextStyles.bodyMd()),
            );
          }

          // المُرشِّح لمالك المنصّة وحده: المهندس لا يرى إلا عملاءه، فقائمةٌ
          // منسدلة بخيارٍ واحد ضوضاء تُوحي بوجود ما لا يراه.
          final isOwner = ref.watch(isPlatformOwnerProvider).valueOrNull ?? false;
          final filter = ref.watch(organizationFilterProvider);
          final shown = (isOwner && filter != null)
              ? orgs.where((o) => '${o['ownerUserId']}' == filter).toList()
              : orgs;

          return Column(
            children: [
              if (isOwner) const _EngineerFilter(),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Text('لا شركات لهذا المهندس بعد',
                            style: AppTextStyles.bodyMd()),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: shown.length,
                        itemBuilder: (context, i) => _OrgCard(org: shown[i]),
                      ),
              ),
            ],
          );
        },
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
                    onPressed: () => _printContract(
                      context,
                      org,
                      ref.read(resellerLicenseProvider).valueOrNull,
                    ),
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
                  // الحذف كان في الخادم بلا زرّ يبلغه: نقطة
                  // DELETE /platform/organizations/{id} قائمة منذ بنائها،
                  // فكان محو عميلٍ انتهى عقده يستلزم فتح قاعدة البيانات —
                  // وهو أخطر ما يُدفَع إليه مالك المنصّة، لأن الحذف اليدوي
                  // ينسى المرفقات ويترك صفّاً في الفهرس العالمي.
                  // الحذف لمالك المنصّة وحده — والخادم يرفضه من غيره
                  // ([PlatformScope.IsOwner])، فإخفاؤه هنا يمنع زرّاً
                  // يُضغط ليُقابَل بـ403 لا أكثر.
                  if (ref.watch(isPlatformOwnerProvider).valueOrNull ?? false)
                    OutlinedButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _DeleteOrgDialog(org: org),
                      ),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      icon: const Icon(Icons.delete_forever_outlined, size: 18),
                      label: const Text('حذف'),
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

/// مُرشِّح قائمة العملاء بالمهندس البائع — لمالك المنصّة وحده.
///
/// <para>ويُعرض «بلا نسبة» خياراً صريحاً: منظمات أُنشئت قبل وجود المهندسين
/// لا تخصّ أحداً منهم، وإخفاؤها خلف «الكلّ» وحده كان يجعل مجموع المرشَّحات
/// أقلّ من القائمة بلا تفسير.</para>
class _EngineerFilter extends ConsumerWidget {
  const _EngineerFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engineers = ref.watch(platformEngineersProvider);
    final selected = ref.watch(organizationFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: selected,
              isDense: true,
              decoration: const InputDecoration(labelText: 'البائع'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('كل البائعين')),
                const DropdownMenuItem<String?>(value: 'null', child: Text('بلا نسبة')),
                // قائمةٌ فارغة حين يتعذّر تحميل المهندسين لا رسالة خطأ:
                // المُرشِّح راحةُ نظر، وإسقاط القائمة كلّها لأجله عقوبةٌ لا
                // تناسب.
                ...engineers.valueOrNull?.map((e) => DropdownMenuItem<String?>(
                          value: '${e['id']}',
                          child: Text('${e['fullName']} · ${e['resellerLicense']}'),
                        )) ??
                    const <DropdownMenuItem<String?>>[],
              ],
              onChanged: (v) =>
                  ref.read(organizationFilterProvider.notifier).state = v,
            ),
          ),
        ],
      ),
    );
  }
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
  late String _edition = widget.org['edition'] as String? ?? 'standard';

  /// الوحدات المطلوب أن تعمل بعد الحفظ — **الحاصل لا الفارق**.
  ///
  /// تُرسَل كما هي ويشتقّ الخادم منها المنح والسحب. اشتقاقها هنا كان
  /// يستلزم نسخة Dart من خريطة الإصدارات، ونسخةٌ ثانية تفترق عن الأولى عند
  /// أوّل إصدارٍ يُضاف — راجع `UpdatePlatformOrganizationRequest.Modules`.
  late Set<String> _modules = ((widget.org['effectiveModules'] as List?) ?? const [])
      .whereType<String>()
      .toSet();

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
        'edition': _edition,
        'modules': _modules.toList(),
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
              const SizedBox(height: 12),
              // الإصدار صار يُعدَّل — وكان ممنوعاً بحجّة أن تغييره يُخفي
              // وحدات فيها بيانات قائمة. والحجّة صحيحة والمنع خطأ: البيانات
              // لا تُحذف بإخفاء وحدة، وحاجة العميل إلى الترقية حقيقية
              // ويومية. والوحدات أسفله تُبقي المخفيّ ظاهراً متى شئت.
              DropdownButtonFormField<String>(
                initialValue: _editionLabels.containsKey(_edition) ? _edition : null,
                decoration: const InputDecoration(labelText: 'الإصدار'),
                items: _editionLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                // الوحدات لا تُعاد ضبطها هنا: مالك المنصّة يرقّي إصداراً
                // وقد اشترى العميل وحدةً فوقه، ومسحُها بتغيير الإصدار يُلغي
                // صفقةً بضغطة لا يقصدها. الخادم يقيس الفارق على الإصدار
                // الجديد عند الحفظ.
                onChanged: (v) => setState(() => _edition = v ?? _edition),
              ),
              const SizedBox(height: 12),
              _ModulesField(
                selected: _modules,
                onChanged: (m) => setState(() => _modules = m),
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


/// حذف منظمة عميل — بلا رجعة.
///
/// **التأكيد بكتابة الاسم القانوني حرفياً**، وهو ما يفرضه الخادم أصلاً.
/// وتكراره هنا ليس ازدواجاً بل هو الغرض: زرُّ «متأكد؟» يُضغط بلا قراءة،
/// وكتابةُ الاسم تُجبر على النظر إلى أي صفٍّ من القائمة يُحذف — والقائمة
/// تحمل عملاء بأسماء متشابهة.
class _DeleteOrgDialog extends ConsumerStatefulWidget {
  const _DeleteOrgDialog({required this.org});
  final Map<String, dynamic> org;

  @override
  ConsumerState<_DeleteOrgDialog> createState() => _DeleteOrgDialogState();
}

class _DeleteOrgDialogState extends ConsumerState<_DeleteOrgDialog> {
  final _confirmController = TextEditingController();
  bool _deleting = false;
  String? _error;

  String get _legalName => widget.org['legalName'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    // ليُعاد بناء الزرّ مع كل حرف: بلا هذا يبقى معطَّلاً حتى بعد كتابة
    // الاسم كاملاً، فيبدو للمستخدم أن الشاشة معطوبة.
    _confirmController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.delete(
        '/platform/organizations/${widget.org['id']}',
        // الاسم في مَعلمة استعلام لا في الجسم: DELETE بجسمٍ يُسقطه بعض
        // الوسطاء بصمت، فيصل الطلب بلا تأكيد ويردّه الخادم بـ400 مُبهم.
        queryParameters: {'confirm': _confirmController.text.trim()},
      );
      ref.invalidate(platformOrganizationsProvider);
      if (mounted) Navigator.pop(context);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = _errorDetail(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _confirmController.text.trim() == _legalName;

    return AdaptiveDialog(
      title: 'حذف الشركة نهائياً',
      maxWidth: 460,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: (!matches || _deleting) ? null : _delete,
          child: _deleting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('احذف'),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'يُحذف كل ما يخصّ «${widget.org['displayName'] ?? ''}»: فواتيرها '
            'وعملاؤها ومخزونها وقيودها ومرفقاتها وحسابات مستخدميها. '
            'ولا يُسترجَع شيء من ذلك إلا من نسخة احتياطية.',
            style: AppTextStyles.bodyMd(color: AppColors.danger),
          ),
          const SizedBox(height: 8),
          Text(
            'الإيقاف بديلٌ أهدأ: يمنع الدخول ويُبقي البيانات — من شاشة التعديل.',
            style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text('للتأكيد اكتب الاسم القانوني حرفياً:', style: AppTextStyles.bodyMd()),
          Text(_legalName, style: AppTextStyles.labelMd()),
          const SizedBox(height: 6),
          TextField(
            controller: _confirmController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'الاسم القانوني'),
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

/// اختيار الوحدات التي تعمل عند العميل.
///
/// **مربّعات على الحاصل لا على الفارق.** عرضُ «مُنح: pharmacy / سُحب:
/// accounting» يجعل مالك المنصّة يحسب الاتّحاد والطرح في رأسه ليعرف ما الذي
/// يراه عميله فعلاً — وهو الحساب الذي يُخطئ فيه ثم يبيع وحدة لا تظهر. فما
/// يُؤشَّر هنا هو ما يعمل، لا أكثر.
///
/// ولا يُمنَع سحب وحدةٍ أساسية كنقطة البيع: العميل قد يشتري النظام لدفتره
/// المحاسبي وحده. ومنعُ حالةٍ لأنها تبدو غريبة يجعل بيعاً حقيقياً مستحيلاً.
class _ModulesField extends StatelessWidget {
  const _ModulesField({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // اسمٌ يعرفه الخادم ولا تعرفه هذه الشاشة يُعرض باسمه البرمجي لا يختفي:
    // اختفاؤه كان يعني وحدةً تعمل عند العميل ولا يراها مالك المنصّة، فيسحبها
    // بلا قصد أوّل مرّة يحفظ.
    final keys = <String>{..._moduleLabels.keys, ...selected}.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الوحدات المفعَّلة', style: AppTextStyles.labelMd()),
        Text(
          'ما يُؤشَّر هنا هو ما يعمل عند العميل. الإصدار أعلاه يضبطها ابتداءً، '
          'وما تُغيّره بعده يُحفظ فوقه فلا يضيع عند ترقيته.',
          style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        for (final key in keys)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(_moduleLabels[key] ?? key, style: AppTextStyles.bodyMd()),
            value: selected.contains(key),
            onChanged: (on) => onChanged(
              on == true ? {...selected, key} : ({...selected}..remove(key)),
            ),
          ),
      ],
    );
  }
}

const _tierLimits = {
  'trial': (1, 3),
  'standard': (3, 10),
  'professional': (10, 50),
  'enterprise': (999, 999),
};

/// طباعة العقد بشروطه المحفوظة.
///
/// ورقم ترخيص البائع يُمرَّر من موضع النداء لا يُقرأ هنا: الدالّة خارج شجرة
/// الودجات فلا `ref` لها، وقراءته من التخزين مباشرةً تُنشئ طريقاً ثانياً
/// إلى دعاوى التوكن يفترق عن [resellerLicenseProvider].
Future<void> _printContract(
    BuildContext context, Map<String, dynamic> org, String? sellerLicense) async {
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
    modules: ((org['effectiveModules'] as List?) ?? const []).whereType<String>().toSet(),
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
    sellerLicense: sellerLicense,
    providerOwner: platform['ownerName'] as String?,
    providerPhone: platform['phone'] as String?,
    providerEmail: platform['email'] as String?,
    providerAddress: platform['address'] as String?,
  );
}
