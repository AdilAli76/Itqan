import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/currency_badge.dart';
import '../../../shared/widgets/data_table_widget.dart';
import '../data/customers_providers.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../core/auth/permissions.dart';
import '../../../shared/widgets/app_surface.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(customerSearchProvider.notifier).state = value;
      // العودة للصفحة الأولى مع كل بحث جديد. بدونها يبقى المستخدم على
      // الصفحة الخامسة بينما النتيجة الجديدة صفحة واحدة، فيرى جدولاً فارغاً
      // ويستنتج أن البحث لم يجد شيئاً — وهو موجود أمامه في الصفحة الأولى.
      ref.read(customersPageProvider.notifier).state = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return AdaptiveScaffold(
      title: 'العملاء',
      activeRoute: '/customers',
      actions: [
        // الإخفاء لا التعطيل: من لا يملك صلاحية الإضافة لا يحتاج أن يرى
        // الزر أصلاً — رؤيته تدفعه للنقر ثم لسؤال الدعم عن سبب الرفض.
        Can(
          permission: Perm.customersManage,
          child: ElevatedButton.icon(
            onPressed: () => _openCustomerDialog(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة عميل'),
          ),
        ),
      ],
      body: customersAsync.when(
        loading: () => const TableSkeleton(),
        error: (err, _) => _ErrorBox(
          message: 'تعذّر تحميل العملاء',
          onRetry: () => ref.invalidate(customersProvider),
        ),
        data: (customers) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDataTable(
              // العدد الكلي لا عدد الصفحة: «العملاء (50)» في منظمة لديها ألف
              // عميل معلومة خاطئة صريحة.
              title: 'العملاء (${customers.totalCount})',
              onSearch: _onSearch,
              emptyMessage: 'لا يوجد عملاء بعد — أضف أول عميل من زر «إضافة عميل»',
              emptyIcon: Icons.people_outline,
              columns: const [
                AppColumn('الاسم'),
                AppColumn('الهاتف'),
                AppColumn('البريد الإلكتروني'),
                AppColumn('باركود البطاقة'),
                AppColumn('رصيد المحفظة'),
                AppColumn('نموذج الحساب'),
                AppColumn('نقاط الولاء'),
                AppColumn(''),
              ],
              rows: customers.items.map((c) => _customerRow(context, c)).toList(),
            ),
            PaginationBar(
              page: customers.page,
              pageSize: customers.pageSize,
              totalCount: customers.totalCount,
              onPageChanged: (p) => ref.read(customersPageProvider.notifier).state = p,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _customerRow(BuildContext context, Map<String, dynamic> c) {
    final balance = (c['walletBalance'] as num?)?.toDouble() ?? 0;
    return [
      Text(c['fullName'] as String? ?? ''),
      Text(c['phone'] as String? ?? '-'),
      Text(c['email'] as String? ?? '-'),
      Text(c['cardBarcode'] as String? ?? '-'),
      CurrencyBadge(amount: balance),
      _accountModelCell(c),
      Text(NumberFormat('#,##0', 'en').format((c['loyaltyPoints'] as num?) ?? 0)),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Can(
            permission: Perm.customersWalletAdjust,
            child: IconButton(
              tooltip: 'شحن رصيد المحفظة',
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              onPressed: () async {
                final adjusted = await showDialog<bool>(
                  context: context,
                  builder: (_) => _WalletAdjustmentDialog(customer: c),
                );
                if (adjusted == true) ref.invalidate(customersProvider);
              },
            ),
          ),
          // إصدار البطاقة وطباعتها لهما شاشة مخصَّصة واحدة («بطاقات المحفظة»)
          // — كان هنا مساران مكرَّران يصدران بطاقات بنموذجين مختلفين، وهو ما
          // سبّب اختلاف سلوك إدخال الرقم السري بين الشاشتين.
          Can(
            permission: Perm.customersManage,
            child: IconButton(
              tooltip: 'تعديل العميل',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _openCustomerDialog(context, customer: c),
            ),
          ),
          // صلاحية الحذف منفصلة عن صلاحية التعديل في الخادم
          // (customers.delete مقابل customers.manage)، فتُفحَص منفصلةً هنا
          // أيضاً — دمجهما كان سيمنح كل من يعدّل حقّ الحذف ضمناً.
          Can(
            permission: Perm.customersDelete,
            child: IconButton(
              tooltip: 'حذف العميل',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _confirmDelete(context, c),
            ),
          ),
        ],
      ),
    ];
  }

  /// يميّز نموذجَي الحساب في القائمة، ويحذّر من الاستحقاقات المنتهية أو
  /// الموشكة — لأن رصيد الاستحقاق يسقط بصمت وقتها، فيجب أن يُرى قبل ذلك.
  Widget _accountModelCell(Map<String, dynamic> c) {
    if ((c['accountModel'] as String? ?? 'prepaid') != 'entitlement') {
      return Text('رصيد مدفوع', style: AppTextStyles.bodyMd());
    }

    final expiresRaw = c['entitlementExpiresOn'] as String?;
    final expires = expiresRaw == null ? null : DateTime.tryParse(expiresRaw);
    final sponsor = c['sponsorName'] as String? ?? 'بلا جهة';

    String label;
    Color color;
    if (expires == null) {
      label = '$sponsor — بلا تاريخ';
      color = AppColors.warning;
    } else {
      final daysLeft = expires.difference(DateTime.now()).inDays;
      if (daysLeft < 0) {
        label = '$sponsor — منتهٍ';
        color = AppColors.danger;
      } else if (daysLeft <= 7) {
        label = '$sponsor — ينتهي خلال $daysLeft يوم';
        color = AppColors.warning;
      } else {
        label = '$sponsor — حتى ${DateFormat('yyyy-MM-dd').format(expires)}';
        color = AppColors.textSecondary;
      }
    }
    return Text(label, style: AppTextStyles.bodyMd(color: color));
  }

  Future<void> _openCustomerDialog(BuildContext context, {Map<String, dynamic>? customer}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerFormDialog(customer: customer),
    );
    if (saved == true) {
      ref.invalidate(customersProvider);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Map<String, dynamic> c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العميل'),
        content: Text('هل تريد حذف "${c['fullName']}"؟ يمكن استرجاعه لاحقاً من سجل التدقيق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.dio.delete('/customers/${c['id']}');
      ref.invalidate(customersProvider);
    } catch (_) {
      if (context.mounted) _showError(context, 'تعذّر حذف العميل');
    }
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

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _dioErrorMessage(Object error, String fallback) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) return data['message'] as String;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// نموذج إضافة/تعديل عميل
// ---------------------------------------------------------------------------

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.customer});
  final Map<String, dynamic>? customer;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.customer?['fullName'] as String?);
  late final _phoneController = TextEditingController(text: widget.customer?['phone'] as String?);
  late final _emailController = TextEditingController(text: widget.customer?['email'] as String?);
  late final _notesController = TextEditingController(text: widget.customer?['notes'] as String?);
  late final _cardController = TextEditingController(text: widget.customer?['cardBarcode'] as String?);
  late final _creditLimitController =
      TextEditingController(text: (widget.customer?['creditLimit'] as num?)?.toString() ?? '0');
  late final _ceilingController =
      TextEditingController(text: (widget.customer?['entitlementCeiling'] as num?)?.toString() ?? '0');
  late bool _isBranchOnly = widget.customer?['branchId'] != null;
  late String _accountModel = widget.customer?['accountModel'] as String? ?? 'prepaid';
  late String? _sponsorId = widget.customer?['sponsorId'] as String?;
  late DateTime? _expiresOn = widget.customer?['entitlementExpiresOn'] == null
      ? null
      : DateTime.tryParse(widget.customer!['entitlementExpiresOn'] as String);
  bool _saving = false;
  String? _error;

  bool get _isEntitlement => _accountModel == 'entitlement';

  bool get _isEdit => widget.customer != null;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    _cardController.dispose();
    _creditLimitController.dispose();
    _ceilingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل عميل' : 'إضافة عميل جديد'),
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
                decoration: const InputDecoration(labelText: 'اسم العميل'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'حقل إلزامي' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الهاتف'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني (اختياري)'),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return null;
                  return value.contains('@') ? null : 'بريد إلكتروني غير صحيح';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cardController,
                decoration: const InputDecoration(
                  labelText: 'باركود البطاقة',
                  helperText: 'يُملأ تلقائياً عند إصدار بطاقة من شاشة «بطاقات المحفظة»',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _creditLimitController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'سقف البيع الآجل'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
                  return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
                },
              ),
              const Divider(height: 28),
              Text('نموذج الحساب', style: AppTextStyles.labelMd()),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'prepaid',
                      label: Text('رصيد مدفوع'),
                      icon: Icon(Icons.savings_outlined, size: 16)),
                  ButtonSegment(
                      value: 'entitlement',
                      label: Text('استحقاق ممنوح'),
                      icon: Icon(Icons.card_giftcard_outlined, size: 16)),
                ],
                selected: {_accountModel},
                onSelectionChanged: (s) => setState(() => _accountModel = s.first),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  _isEntitlement
                      ? 'جهة ممولة تمنح رصيداً بسقف وفترة. ما لا يُصرف يسقط بانتهاء الفترة، '
                          'والمحاسبة تكون مع الجهة لا مع العميل.'
                      : 'رصيد يدفعه العميل من ماله. لا يسقط بمرور الوقت ولا سقف له — '
                          'إسقاط مال دفعه صاحبه مصادرة له.',
                  style: AppTextStyles.bodyMd(color: AppColors.info),
                ),
              ),
              if (_isEntitlement) ...[
                const SizedBox(height: 12),
                _SponsorPicker(
                  value: _sponsorId,
                  onChanged: (v) => setState(() => _sponsorId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ceilingController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'سقف المنح للفترة',
                    helperText: 'صفر = بلا سقف',
                  ),
                  validator: (v) {
                    if (!_isEntitlement) return null;
                    if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
                    return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'صالح حتى',
                    helperText: 'بعد هذا التاريخ يسقط ما تبقّى من الاستحقاق',
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            _expiresOn == null ? 'لم يُحدَّد' : DateFormat('yyyy-MM-dd').format(_expiresOn!)),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        label: const Text('اختر'),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _expiresOn ?? DateTime(now.year, now.month + 1, 0),
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 10),
                          );
                          if (picked != null) setState(() => _expiresOn = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 28),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ربط العميل بفرعي'),
                // الصياغة القديمة كانت "خاص بهذا الفرع فقط" وهي غير صحيحة:
                // جدول customers معزول على مستوى المنظمة لا الفرع، فالعميل
                // يبقى ظاهراً لكل الفروع. الحقل وصفي (لمعرفة فرع التسجيل)
                // وليس قيداً أمنياً — راجع تعليق CustomersController.
                subtitle: const Text('للتصنيف فقط — بيانات العميل تبقى متاحة لكل الفروع'),
                value: _isBranchOnly,
                onChanged: (v) => setState(() => _isBranchOnly = v),
              ),
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
      'fullName': _nameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      'cardBarcode': _cardController.text.trim().isEmpty ? null : _cardController.text.trim(),
      'creditLimit': double.parse(_creditLimitController.text),
      // فرع المستخدم الحالي وحده متاح بلا شاشة اختيار فروع بعد — راجع
      // نفس القيد في تعديل الكمية بشاشة المخزون.
      'branchId': _isBranchOnly ? await readCurrentBranchId() : null,
      'accountModel': _accountModel,
      // حقول الاستحقاق تُرسَل فارغة مع الدفع المسبق، والسيرفر يمحوها كذلك —
      // لئلا يبقى سقف وتاريخ معلَّقان على حساب لا يُطبَّقان عليه.
      'sponsorId': _isEntitlement ? _sponsorId : null,
      'entitlementCeiling': _isEntitlement ? double.parse(_ceilingController.text) : 0,
      'entitlementExpiresOn':
          _isEntitlement && _expiresOn != null ? DateFormat('yyyy-MM-dd').format(_expiresOn!) : null,
    };

    try {
      if (_isEdit) {
        await ApiClient.instance.dio.put('/customers/${widget.customer!['id']}', data: body);
      } else {
        await ApiClient.instance.dio.post('/customers', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ العميل'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// شحن رصيد المحفظة
// ---------------------------------------------------------------------------

class _WalletAdjustmentDialog extends StatefulWidget {
  const _WalletAdjustmentDialog({required this.customer});
  final Map<String, dynamic> customer;

  @override
  State<_WalletAdjustmentDialog> createState() => _WalletAdjustmentDialogState();
}

class _WalletAdjustmentDialogState extends State<_WalletAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = (widget.customer['walletBalance'] as num?)?.toDouble() ?? 0;

    return AlertDialog(
      title: Text('رصيد المحفظة: ${widget.customer['fullName']}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الرصيد الحالي: ${NumberFormat('#,##0.00', 'en').format(balance)}',
                style: AppTextStyles.bodyMd(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'الفرق (+ للشحن، - للخصم)',
                  hintText: 'مثال: 50 أو -20',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'حقل إلزامي';
                  return double.tryParse(v) == null ? 'قيمة غير صحيحة' : null;
                },
              ),
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

    try {
      await ApiClient.instance.dio.post('/customers/${widget.customer['id']}/wallet-adjustments', data: {
        'amountDelta': double.parse(_amountController.text),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر تعديل الرصيد'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// اختيار الجهة الممولة، مع إنشاء جهة جديدة دون مغادرة نموذج العميل.
///
/// الإنشاء المضمَّن مقصود: المستخدم يكتشف حاجته لجهة *أثناء* تسجيل أول مستفيد
/// لها، وإجباره على إغلاق النموذج والذهاب لشاشة أخرى يُفقده ما كتبه.
class _SponsorPicker extends ConsumerWidget {
  const _SponsorPicker({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sponsors = ref.watch(sponsorsProvider);

    return sponsors.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) =>
          Text('تعذّر تحميل الجهات الممولة', style: AppTextStyles.bodyMd(color: AppColors.danger)),
      data: (list) => Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: list.any((s) => s['id'] == value) ? value : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الجهة الممولة'),
              items: list
                  .map((s) => DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(s['name'] as String? ?? ''),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
          IconButton(
            tooltip: 'جهة ممولة جديدة',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              final created = await showDialog<String>(
                context: context,
                builder: (_) => const _SponsorFormDialog(),
              );
              if (created != null) {
                ref.invalidate(sponsorsProvider);
                onChanged(created);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// إنشاء جهة ممولة — يُرجع معرّف الجهة المُنشأة ليُختار فوراً.
class _SponsorFormDialog extends StatefulWidget {
  const _SponsorFormDialog();

  @override
  State<_SponsorFormDialog> createState() => _SponsorFormDialogState();
}

class _SponsorFormDialogState extends State<_SponsorFormDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _error = 'اسم الجهة إلزامي');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ApiClient.instance.dio.post('/sponsors', data: {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      });
      if (mounted) Navigator.pop(context, response.data['id'] as String);
    } catch (e) {
      setState(() => _error = _dioErrorMessage(e, 'تعذّر حفظ الجهة'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('جهة ممولة جديدة'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم الجهة'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف (اختياري)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
