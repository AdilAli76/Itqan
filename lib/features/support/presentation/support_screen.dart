import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/support_providers.dart';

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

/// جهة الدعم الفني الموحّدة لكل عملاء المنصة — تُدار من مالك المنصة (نفس
/// بوابة PlatformController)، وتظهر للجميع كبيانات تواصل عند الحاجة لدعم.
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  bool _isPlatformAdmin = false;

  @override
  void initState() {
    super.initState();
    readJwtClaims().then((claims) {
      if (mounted) setState(() => _isPlatformAdmin = claims?['is_platform_admin'] == 'True');
    });
  }

  @override
  Widget build(BuildContext context) {
    final infoAsync = ref.watch(platformSupportInfoProvider);

    return AdaptiveScaffold(
      title: 'الدعم الفني',
      activeRoute: '/support',
      body: infoAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        error: (_, __) => Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Text('تعذّر تحميل بيانات الدعم الفني', style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ),
        data: (info) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('التواصل مع الدعم الفني', style: AppTextStyles.headlineMd()),
                  const SizedBox(height: 16),
                  _InfoRow(icon: Icons.business_outlined, label: 'الشركة', value: info['companyName'] as String?),
                  _InfoRow(icon: Icons.person_outline, label: 'المسؤول', value: info['ownerName'] as String?),
                  _InfoRow(icon: Icons.phone_outlined, label: 'الهاتف', value: info['phone'] as String?),
                  _InfoRow(icon: Icons.chat_outlined, label: 'واتساب', value: info['whatsapp'] as String?),
                  _InfoRow(icon: Icons.email_outlined, label: 'البريد الإلكتروني', value: info['email'] as String?),
                  _InfoRow(icon: Icons.location_on_outlined, label: 'العنوان', value: info['address'] as String?),
                ],
              ),
            ),
            if (_isPlatformAdmin) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final saved = await showDialog<bool>(context: context, builder: (_) => _EditSupportInfoDialog(info: info));
                    if (saved == true) ref.invalidate(platformSupportInfoProvider);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('تعديل بيانات الدعم الفني'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: Text(label, style: AppTextStyles.labelMd(color: AppColors.textSecondary))),
          Expanded(
            child: SelectableText(
              hasValue ? value! : 'غير مُعبَّأ بعد',
              style: AppTextStyles.bodyMd(color: hasValue ? AppColors.textPrimary : AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditSupportInfoDialog extends StatefulWidget {
  const _EditSupportInfoDialog({required this.info});
  final Map<String, dynamic> info;

  @override
  State<_EditSupportInfoDialog> createState() => _EditSupportInfoDialogState();
}

class _EditSupportInfoDialogState extends State<_EditSupportInfoDialog> {
  late final _companyController = TextEditingController(text: widget.info['companyName'] as String?);
  late final _ownerController = TextEditingController(text: widget.info['ownerName'] as String?);
  late final _phoneController = TextEditingController(text: widget.info['phone'] as String?);
  late final _whatsappController = TextEditingController(text: widget.info['whatsapp'] as String?);
  late final _emailController = TextEditingController(text: widget.info['email'] as String?);
  late final _addressController = TextEditingController(text: widget.info['address'] as String?);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _companyController.dispose();
    _ownerController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات الدعم الفني'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(controller: _companyController, decoration: const InputDecoration(labelText: 'اسم الشركة')),
              const SizedBox(height: 12),
              TextFormField(controller: _ownerController, decoration: const InputDecoration(labelText: 'اسم المسؤول')),
              const SizedBox(height: 12),
              TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
              const SizedBox(height: 12),
              TextFormField(controller: _whatsappController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'واتساب')),
              const SizedBox(height: 12),
              TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
              const SizedBox(height: 12),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'العنوان')),
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.put('/platform-settings', data: {
        'companyName': _companyController.text.trim(),
        'ownerName': _ownerController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'whatsapp': _whatsappController.text.trim().isEmpty ? null : _whatsappController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ البيانات'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
