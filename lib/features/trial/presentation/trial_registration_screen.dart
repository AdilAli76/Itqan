import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_surface.dart';

/// شاشة التسجيل الذاتي للنسخة التجريبية (14 يوماً).
/// 
/// تتيح للعملاء التسجيل مباشرة من المتصفح واختيار تخصص نشاطهم:
/// - إنشاء المنظمة وحساب المدير فوراً.
/// - تفعيل ترخيص 14 يوماً مع الوحدات المناسبة للنشاط.
/// - ربط العميل بالمهندس المسوق عبر كود الإحالة (?ref=CODE).
class TrialRegistrationScreen extends ConsumerStatefulWidget {
  const TrialRegistrationScreen({super.key, this.initialReferralCode});

  final String? initialReferralCode;

  @override
  ConsumerState<TrialRegistrationScreen> createState() => _TrialRegistrationScreenState();
}

class _TrialRegistrationScreenState extends ConsumerState<TrialRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _refCodeController = TextEditingController();

  String _selectedType = 'retail';
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialReferralCode != null && widget.initialReferralCode!.isNotEmpty) {
      _refCodeController.text = widget.initialReferralCode!;
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _refCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiClient.instance.dio.post(
        '/trial/register',
        data: {
          'businessName': _businessNameController.text.trim(),
          'businessType': _selectedType,
          'adminFullName': _adminNameController.text.trim(),
          'adminEmail': _emailController.text.trim().toLowerCase(),
          'adminPhone': _phoneController.text.trim(),
          'adminPassword': _passwordController.text,
          'referralCode': _refCodeController.text.trim().isEmpty ? null : _refCodeController.text.trim(),
        },
      );

      final token = response.data['token'] as String;
      await ApiClient.instance.saveToken(token);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.data['message'] as String? ?? 'تم تفعيل نسختك التجريبية بنجاح!'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 4),
        ),
      );

      // دخول مباشر للمنظومة
      context.go('/app');
    } on DioException catch (e) {
      final msg = e.response?.data is Map && e.response?.data['message'] != null
          ? e.response!.data['message'].toString()
          : 'تعذّر إكمال التسجيل، تأكد من الاتصال بالخادم والبيانات المدخلة';
      setState(() => _error = msg);
    } catch (e) {
      setState(() => _error = 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Breakpoints.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('التسجيل في النسخة التجريبية (14 يوماً مجاناً)'),
        elevation: 0,
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/login');
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 48 : 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: AppSurface(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // شعار وعنوان
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/branding/itqan_logo.png',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('منظومة إتقان ERP السحابية', style: AppTextStyles.headlineLg()),
                                Text(
                                  'احصل على نسختك الكاملة مجاناً لمدة 14 يوماً بدون أي رسوم مسبقة',
                                  style: AppTextStyles.bodyMd(color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 36),

                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.dangerBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.danger),
                          ),
                          child: Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // 1. اختيار نوع النشاط
                      Text('1. حدد مجال ونوع نشاطك التجاري', style: AppTextStyles.headlineMd()),
                      const SizedBox(height: 6),
                      Text(
                        'سنقوم بتجهيز الوحدات المحاسبية ونقاط البيع المناسبة لطبيعة عملك تلقائياً:',
                        style: AppTextStyles.caption(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _typeOption(
                            id: 'retail',
                            title: 'تجزئة وسوبرماركت',
                            subtitle: 'نقاط بيع سريعة، باركود، ومخازن',
                            icon: Icons.storefront_outlined,
                          ),
                          _typeOption(
                            id: 'pharmacy',
                            title: 'صيدليات ومراكز دواء',
                            subtitle: 'إدارة أدوية، جرعات، وموانع استعمال',
                            icon: Icons.local_pharmacy_outlined,
                          ),
                          _typeOption(
                            id: 'wholesale',
                            title: 'جملة وتوزيع ومخازن',
                            subtitle: 'موردين، عملاء جملة، ومستودعات متعددة',
                            icon: Icons.warehouse_outlined,
                          ),
                          _typeOption(
                            id: 'enterprise',
                            title: 'شركات ومقاولات',
                            subtitle: 'محاسبة عامة، مراكز تكلفة، وميزانيات',
                            icon: Icons.apartment_outlined,
                          ),
                          _typeOption(
                            id: 'wallet',
                            title: 'محفظة وبطاقات إلكترونية',
                            subtitle: 'أرصدة أعضاء وبطاقات خصم ونقاط',
                            icon: Icons.credit_card_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 2. بيانات المؤسسة والحساب
                      Text('2. بيانات المؤسسة والمدير العام', style: AppTextStyles.headlineMd()),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _businessNameController,
                        decoration: const InputDecoration(
                          labelText: 'اسم المؤسسة أو الشركة أو الصيدلية *',
                          prefixIcon: Icon(Icons.business_outlined),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'الرجاء كتابة اسم المؤسسة' : null,
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _adminNameController,
                              decoration: const InputDecoration(
                                labelText: 'اسم المدير المسؤول *',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'الرجاء إدخال اسم المسؤول' : null,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'رقم الهاتف',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني (يُستخدم لتسجيل الدخول) *',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'البريد الإلكتروني إلزامي';
                          if (!v.contains('@') || !v.contains('.')) return 'صيغة البريد غير صحيحة';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور (8 أحرف على الأقل) *',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'كلمة المرور إلزامية';
                          if (v.length < 8) return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 3. كود الإحالة / المهندس
                      TextFormField(
                        controller: _refCodeController,
                        decoration: const InputDecoration(
                          labelText: 'كود المهندس المسوق أو الدنقل (اختياري)',
                          prefixIcon: Icon(Icons.handshake_outlined),
                          hintText: 'إذا كان لديك كود إحالة من مهندس المبيعات',
                        ),
                      ),
                      const SizedBox(height: 28),

                      FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: AppTextStyles.headlineMd(),
                        ),
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.rocket_launch_rounded),
                        label: Text(_loading ? 'جاري تجهيز نسختك التجريبية...' : 'بدء التجربة المجانية فوراً'),
                      ),
                      const SizedBox(height: 14),

                      Center(
                        child: TextButton(
                          onPressed: () => context.go('/login'),
                          child: const Text('لديك حساب بالفعل؟ تسجيل الدخول'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedType == id;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: () => setState(() => _selectedType = id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 290,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withAlpha(20) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primaryColor : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: isSelected ? primaryColor : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodyLg(color: isSelected ? primaryColor : AppColors.textPrimary)),
                  Text(subtitle, style: AppTextStyles.caption(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
