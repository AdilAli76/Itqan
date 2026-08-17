import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/settings_providers.dart';

const _localeLabels = {'ar': 'العربية', 'en': 'English'};

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
    final settingsAsync = ref.watch(settingsProvider);

    return AdaptiveScaffold(
      title: 'الإعدادات العامة',
      activeRoute: '/settings',
      body: !_roleLoaded
          ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          : settingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Text('تعذّر تحميل الإعدادات', style: AppTextStyles.bodyMd(color: AppColors.danger)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => ref.invalidate(settingsProvider), child: const Text('إعادة المحاولة')),
                  ],
                ),
              ),
              data: (settings) => _SettingsForm(settings: settings, canEdit: _canEdit),
            ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, required this.canEdit});
  final Map<String, dynamic> settings;
  final bool canEdit;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _currencyCodeController = TextEditingController(text: widget.settings['currencyCode'] as String?);
  late final _currencySymbolController = TextEditingController(text: widget.settings['currencySymbol'] as String?);
  late final _taxRateController =
      TextEditingController(text: (widget.settings['taxRate'] as num?)?.toString() ?? '0');
  late final _passwordMinLengthController =
      TextEditingController(text: (widget.settings['passwordMinLength'] as num?)?.toString() ?? '6');
  late final _receiptWidthController =
      TextEditingController(text: (widget.settings['receiptWidthMm'] as num?)?.toString() ?? '80');

  late String _locale = widget.settings['locale'] as String? ?? 'ar';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currencyCodeController.dispose();
    _currencySymbolController.dispose();
    _taxRateController.dispose();
    _passwordMinLengthController.dispose();
    _receiptWidthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'العملة واللغة',
              icon: Icons.language_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currencyCodeController,
                        enabled: widget.canEdit,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(labelText: 'رمز العملة (ISO)', hintText: 'LYD'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _currencySymbolController,
                        enabled: widget.canEdit,
                        decoration: const InputDecoration(labelText: 'رمز العملة المعروض', hintText: 'د.ل'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _locale,
                  decoration: const InputDecoration(labelText: 'لغة الواجهة الافتراضية'),
                  items: _localeLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: widget.canEdit ? (v) => setState(() => _locale = v ?? 'ar') : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'الضرائب وسياسة كلمة المرور',
              icon: Icons.security_outlined,
              children: [
                TextFormField(
                  controller: _taxRateController,
                  enabled: widget.canEdit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'نسبة الضريبة الافتراضية (%)'),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 0 || n > 100) return 'قيمة بين 0 و100';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordMinLengthController,
                  enabled: widget.canEdit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الحد الأدنى لطول كلمة المرور',
                    helperText: 'يُطبَّق فوراً عند إضافة مستخدم جديد أو إعادة تعيين كلمة مرور',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 4) return '4 أحرف على الأقل';
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'الطباعة',
              icon: Icons.print_outlined,
              children: [
                TextFormField(
                  controller: _receiptWidthController,
                  enabled: widget.canEdit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'عرض لفة إيصال الطابعة الحرارية (ملم)',
                    helperText: 'القياسان الشائعان: 58 أو 80 ملم',
                  ),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 40 || n > 120) return 'قيمة بين 40 و120';
                    return null;
                  },
                ),
              ],
            ),
            if (!widget.canEdit) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(8)),
                child: Text('عرض فقط — تعديل الإعدادات متاح للمدير العام فقط', style: AppTextStyles.bodyMd(color: AppColors.warning)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
            if (widget.canEdit) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('حفظ الإعدادات'),
                ),
              ),
            ],
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
    });

    try {
      await ApiClient.instance.dio.put('/organizations/me/settings', data: {
        'currencyCode': _currencyCodeController.text.trim(),
        'currencySymbol': _currencySymbolController.text.trim(),
        'locale': _locale,
        'taxRate': double.parse(_taxRateController.text),
        'passwordMinLength': int.parse(_passwordMinLengthController.text),
        'receiptWidthMm': double.parse(_receiptWidthController.text),
      });
      ref.invalidate(settingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
      }
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الإعدادات'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
