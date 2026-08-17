import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/barcode_view.dart';
import '../../../shared/widgets/currency_badge.dart';

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

const _kindLabels = {
  'topup': 'شحن رصيد',
  'spend': 'شراء',
  'invoice_refund': 'استرجاع فاتورة',
  'adjustment_in': 'إضافة رصيد',
  'adjustment_out': 'خصم رصيد',
};

/// بوابة العميل — شاشة مستقلة تماماً عن نظام الموظفين: لا شريط جانبي ولا
/// تبويبات، تُصمَّم لشاشة هاتف أولاً. العميل يرى رصيده وحركاته فقط ولا
/// يستطيع تنفيذ أي عملية؛ كشف الحساب يُطلَب من الإدارة.
class CustomerPortalScreen extends StatefulWidget {
  const CustomerPortalScreen({super.key});

  @override
  State<CustomerPortalScreen> createState() => _CustomerPortalScreenState();
}

class _CustomerPortalScreenState extends State<CustomerPortalScreen> {
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _account;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.post('/customer-portal/login', data: {
        'cardCode': _codeController.text.trim(),
        'pin': _pinController.text.trim(),
      });
      setState(() => _account = response.data as Map<String, dynamic>);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر الدخول — تحقق من الاتصال'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _logout() {
    setState(() {
      _account = null;
      _codeController.clear();
      _pinController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('حسابي'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          tooltip: 'رجوع',
          onPressed: () => context.go('/login'),
        ),
        actions: [
          if (_account != null)
            IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'خروج'),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _account == null ? _buildLogin(context) : _buildAccount(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 20),
        Text('حساب العميل', style: AppTextStyles.displayLg(), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'أدخل رمز بطاقتك ورقمك السري لعرض رصيدك',
          style: AppTextStyles.bodyMd(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'رمز البطاقة',
            hintText: 'مثال: 7K4M9PQR2XYZ',
            prefixIcon: Icon(Icons.credit_card_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          onSubmitted: (_) => _login(),
          decoration: const InputDecoration(
            labelText: 'الرقم السري',
            prefixIcon: Icon(Icons.lock_outline),
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(8)),
            child: Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loading ? null : _login,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('عرض حسابي'),
          ),
        ),
      ],
    );
  }

  Widget _buildAccount(BuildContext context) {
    final account = _account!;
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final transactions = List<Map<String, dynamic>>.from(account['transactions'] as List? ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // بطاقة الرصيد — أهم رقم في الشاشة، وأول ما تقع عليه العين.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account['organizationName'] as String? ?? '',
                  style: AppTextStyles.labelMd(color: Colors.white70)),
              const SizedBox(height: 2),
              Text(account['customerName'] as String? ?? '',
                  style: AppTextStyles.headlineMd(color: Colors.white)),
              const SizedBox(height: 20),
              Text('الرصيد المتاح', style: AppTextStyles.bodyMd(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                NumberFormat('#,##0.000', 'en').format(balance),
                style: AppTextStyles.displayLg(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // بطاقة العميل على الشاشة — الكاشير يمسح هذا الباركود من الهاتف
        // مباشرة بلا حاجة للبطاقة الورقية (نفس الرمز على كليهما).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text('اعرض هذا الباركود للكاشير', style: AppTextStyles.bodyMd(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              BarcodeView(data: account['cardCode'] as String? ?? '', height: 72),
              const SizedBox(height: 8),
              SelectableText(
                account['cardCode'] as String? ?? '',
                style: AppTextStyles.currency(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'سقف البيع الآجل',
                value: NumberFormat('#,##0.000', 'en').format((account['creditLimit'] as num?) ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MiniStat(
                label: 'نقاط الولاء',
                value: NumberFormat('#,##0', 'en').format((account['loyaltyPoints'] as num?) ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('آخر الحركات', style: AppTextStyles.headlineMd()),
        const SizedBox(height: 10),
        if (transactions.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text('لا توجد حركات بعد', style: AppTextStyles.bodyMd(color: AppColors.textMuted)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: transactions.map((t) {
                final signed = (t['signedAmount'] as num?)?.toDouble() ?? 0;
                final createdAt = DateTime.tryParse(t['createdAt'] as String? ?? '');
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        signed >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                        size: 18,
                        color: signed >= 0 ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_kindLabels[t['kind']] ?? t['kind'] as String? ?? '',
                                style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                            if (createdAt != null)
                              Text(DateFormat('yyyy-MM-dd HH:mm').format(createdAt),
                                  style: AppTextStyles.bodyMd(color: AppColors.textMuted).copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                      CurrencyBadge(amount: signed, showSign: true),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'لطلب كشف حساب مفصَّل، راجع إدارة المتجر.',
                  style: AppTextStyles.bodyMd(color: AppColors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.bodyMd(color: AppColors.textSecondary).copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.headlineMd()),
        ],
      ),
    );
  }
}
