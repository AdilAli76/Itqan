import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/branding_provider.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/branches_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/app_surface.dart';

// ux-audit: ignore UX-03 — قائمة فروع المنظمة محدودة بطبيعة العمل (وحدات
// إلى عشرات، لا آلاف). الترقيم هنا يضيف شريطاً لا يظهر أبداً وحالة صفحة
// تُدار بلا داعٍ.
// ux-audit: ignore UX-02 — للسبب نفسه: الترشيح فوق قائمة تُقرأ كاملةً في
// نظرة واحدة يزيد الخطوات ولا يقلّلها.

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

String _colorToHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

/// شاشة "تخصيص النظام" (White-Labeling) + إدارة الفروع — هذه الشاشة تحديداً
/// هي ما يحوّل النظام من "نسخة واحدة مقفلة" إلى منتج قابل للبيع لأكثر من
/// زبون: كل زبون يغيّر اسمه وألوانه وفروعه من هنا مباشرة.
class BranchIdentityScreen extends ConsumerStatefulWidget {
  const BranchIdentityScreen({super.key});

  @override
  ConsumerState<BranchIdentityScreen> createState() => _BranchIdentityScreenState();
}

class _BranchIdentityScreenState extends ConsumerState<BranchIdentityScreen> {
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
    final brandingAsync = ref.watch(brandingProvider);

    return AdaptiveScaffold(
      title: 'إدارة الفروع والهوية',
      activeRoute: '/branches',
      actions: [
        if (_canEdit)
          ElevatedButton.icon(
            onPressed: () async {
              final created = await showDialog<bool>(
                context: context,
                builder: (_) => const _BranchFormDialog(),
              );
              if (created == true) ref.invalidate(allBranchesProvider);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة فرع'),
          ),
      ],
      body: !_roleLoaded
          ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                brandingAsync.when(
                  loading: () => const TableSkeleton(),
                  error: (_, __) => _ErrorBox(
                    message: 'تعذّر تحميل بيانات الهوية',
                    onRetry: () => ref.invalidate(brandingProvider),
                  ),
                  data: (branding) => _BrandingForm(branding: branding, canEdit: _canEdit),
                ),
                const SizedBox(height: 24),
                _BranchesSection(canEdit: _canEdit),
              ],
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
// الهوية (الاسم والألوان)
// ---------------------------------------------------------------------------

class _BrandingForm extends ConsumerStatefulWidget {
  const _BrandingForm({required this.branding, required this.canEdit});
  final OrganizationBranding branding;
  final bool canEdit;

  @override
  ConsumerState<_BrandingForm> createState() => _BrandingFormState();
}

class _BrandingFormState extends ConsumerState<_BrandingForm> {
  late final _nameController = TextEditingController(text: widget.branding.displayName);
  late Color _primary = widget.branding.colors.primary;
  late Color _secondary = widget.branding.colors.secondary;
  late String _navLayout = widget.branding.navLayout;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'الاسم والشعار',
          icon: Icons.badge_outlined,
          subtitle: 'يتم تطبيق التغييرات فورياً على كامل النظام دون نشر نسخة جديدة.',
          children: [
            Text('اسم النظام المعروض', style: AppTextStyles.labelMd()),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              enabled: widget.canEdit,
              decoration: const InputDecoration(hintText: 'مثال: نخبة ERP'),
            ),
            const SizedBox(height: 16),
            const _LogoUploadBox(),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'الألوان ونمط التنقّل',
          icon: Icons.palette_outlined,
          children: [
            Text('اللون الأساسي (Primary)', style: AppTextStyles.labelMd()),
            const SizedBox(height: 8),
            _ColorSwatchRow(
              colors: AppColors.presetPrimaries,
              selected: _primary,
              onSelect: widget.canEdit ? (c) => setState(() => _primary = c) : null,
            ),
            const SizedBox(height: 16),
            Text('اللون الثانوي (Secondary)', style: AppTextStyles.labelMd()),
            const SizedBox(height: 8),
            _ColorSwatchRow(
              colors: AppColors.presetSecondaries,
              selected: _secondary,
              onSelect: widget.canEdit ? (c) => setState(() => _secondary = c) : null,
            ),
            const SizedBox(height: 20),
            _PreviewBar(primary: _primary, secondary: _secondary),
            const SizedBox(height: 20),
            Text('نمط التنقّل', style: AppTextStyles.labelMd()),
            const SizedBox(height: 8),
            _NavLayoutRow(
              value: _navLayout,
              onChanged: widget.canEdit ? (v) => setState(() => _navLayout = v) : null,
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ],
        const SizedBox(height: 16),
        if (widget.canEdit)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('حفظ الهوية'),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(8)),
            child: Text('عرض فقط — تعديل الهوية متاح للمدير العام فقط', style: AppTextStyles.bodyMd(color: AppColors.warning)),
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
      await ApiClient.instance.dio.put('/organizations/me/branding', data: {
        'displayName': _nameController.text.trim(),
        'primaryColor': _colorToHex(_primary),
        'secondaryColor': _colorToHex(_secondary),
        'navLayout': _navLayout,
      });
      ref.invalidate(brandingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الهوية')));
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الهوية'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LogoUploadBox extends StatelessWidget {
  const _LogoUploadBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.upload_outlined, color: AppColors.textMuted),
          const SizedBox(height: 6),
          Text('رفع الشعار — غير مفعَّل بعد', style: AppTextStyles.bodyMd()),
        ],
      ),
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({required this.colors, required this.selected, required this.onSelect});
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: colors.map((c) {
        final isSelected = c.toARGB32() == selected.toARGB32();
        return InkWell(
          onTap: onSelect == null ? null : () => onSelect!(c),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            // 44 هدف اللمس لا حجم الدائرة المرئية — الحشو يوسّع المنطقة
            // القابلة للنقر دون تكبير الشكل.
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.textPrimary : Colors.transparent,
                width: 2,
              ),
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
          ),
        );
      }).toList(),
    );
  }
}

class _NavLayoutRow extends StatelessWidget {
  const _NavLayoutRow({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('sidebar', 'شريط جانبي ثابت', Icons.view_sidebar_outlined),
      ('navbar', 'شريط علوي أفقي', Icons.view_headline_outlined),
    ];
    final color = Theme.of(context).colorScheme.primary;

    // Wrap لا Row: خياران بنصوصهما الكاملة يفيضان على عرض ضيّق، والالتفاف
    // إلى سطر ثانٍ أنسب من قصّ نص الخيار الذي يشرح ما يختاره المستخدم.
    return Wrap(
      spacing: 0,
      runSpacing: 10,
      children: options.map((o) {
        final (key, label, icon) = o;
        final selected = value == key;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: InkWell(
            onTap: onChanged == null ? null : () => onChanged!(key),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selected ? color : AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: selected ? color : AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(label, style: AppTextStyles.bodyMd(color: selected ? color : AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.primary, required this.secondary});
  final Color primary;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'معاينة الهوية',
              style: AppTextStyles.labelMd(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: secondary, borderRadius: BorderRadius.circular(6)),
            child: Text('زر رئيسي', style: AppTextStyles.labelMd(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الفروع
// ---------------------------------------------------------------------------

class _BranchesSection extends ConsumerWidget {
  const _BranchesSection({required this.canEdit});
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(allBranchesProvider);

    return branchesAsync.when(
      loading: () => const TableSkeleton(),
      error: (err, _) => _ErrorBox(
        message: 'تعذّر تحميل الفروع',
        onRetry: () => ref.invalidate(allBranchesProvider),
      ),
      data: (branches) => AppDataTable(
        title: 'الفروع (${branches.length})',
        columns: const [
          AppColumn('اسم الفرع'),
          AppColumn('الرمز'),
          AppColumn('العنوان'),
          AppColumn('الهاتف'),
          AppColumn('الحالة'),
          AppColumn(''),
        ],
        rows: branches.map((b) {
          final isActive = b['isActive'] as bool? ?? true;
          return [
            Text(b['name'] as String? ?? ''),
            Text(b['code'] as String? ?? ''),
            Text(b['address'] as String? ?? '-'),
            Text(b['phone'] as String? ?? '-'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.successBg : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(isActive ? 'نشط' : 'معطَّل', style: AppTextStyles.labelMd(color: isActive ? AppColors.success : AppColors.danger)),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (_) => _BranchFormDialog(branch: b),
                  );
                  if (saved == true) ref.invalidate(allBranchesProvider);
                },
              )
            else
              const SizedBox.shrink(),
          ];
        }).toList(),
      ),
    );
  }
}

class _BranchFormDialog extends StatefulWidget {
  const _BranchFormDialog({this.branch});
  final Map<String, dynamic>? branch;

  @override
  State<_BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<_BranchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.branch?['name'] as String?);
  late final _codeController = TextEditingController(text: widget.branch?['code'] as String?);
  late final _addressController = TextEditingController(text: widget.branch?['address'] as String?);
  late final _phoneController = TextEditingController(text: widget.branch?['phone'] as String?);
  late bool _isActive = widget.branch?['isActive'] as bool? ?? true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.branch != null;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل فرع' : 'إضافة فرع جديد'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                // أول حقل في الحوار يأخذ التركيز فور الفتح: المستخدم يكتب
                // مباشرة بدل نقرة إضافية في كل مرة — وهي نقرة تتكرّر آلاف
                // المرات في عمر النظام.
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم الفرع'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'رمز الفرع', hintText: 'مثال: TRP-01'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فرع نشط'),
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
      'code': _codeController.text.trim(),
      'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      if (_isEdit) 'isActive': _isActive,
    };

    try {
      if (_isEdit) {
        await ApiClient.instance.dio.put('/branches/${widget.branch!['id']}', data: body);
      } else {
        await ApiClient.instance.dio.post('/branches', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الفرع'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
