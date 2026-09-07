import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/shell/home_layout.dart';
import '../../../core/network/api_client.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/settings_providers.dart';
import '../../../shared/widgets/app_surface.dart';
import 'backup_section.dart';

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
              error: (err, _) => AppSurface(
      padding: const EdgeInsets.all(32),
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

  /// طريقة تكلفة الصنف — راجع القسم في آخر الشاشة.
  late String _costingMethod =
      widget.settings['inventoryCostingMethod'] as String? ?? 'last_purchase';
  late bool _posAllowOpenProduct = widget.settings['posAllowOpenProduct'] as bool? ?? false;

  // ── أنماط بطاقة المحفظة ────────────────────────────────────────────────
  // المدير يضع المظروف هنا (المسموح والافتراضي والسقف)، واختيار كل زبون
  // داخله من شاشة «بطاقات المحفظة». والكاشير لا يغيّر شيئاً.
  late final Set<String> _cardModes = ((widget.settings['cardModesAllowed'] as String?) ?? 'card,pin')
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet();
  late String _cardModeDefault = widget.settings['cardModeDefault'] as String? ?? 'pin';
  late final _cardCapController = TextEditingController(
      text: (widget.settings['cardOpenModeDailyCap'] as num?)?.toString() ?? '50');

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
    _cardCapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      // تكديس متجاوب بدل عمود ثابت بعرض 560.
      //
      // كان العمود شريطاً ضيّقاً وسط شاشة مكتب واسعة — ثلثا المساحة فارغان
      // والمستخدم يمرّر لأربعة أقسام كان يمكن أن تُرى معاً. و«الحفظ» في
      // أسفل التمرير يجعل تعديل حقل في الأعلى رحلةً ذهاباً وإياباً.
      //
      // الحدّ عند 980 لا 600: القسم الواحد يحتاج نحو 460 بكسل ليبقى مقروءاً،
      // فعمودان تحته يضيّقان الحقول بدل أن يريحا العين.
      child: LayoutBuilder(builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 980;
        final sections = _sections(context);

        if (!twoColumns) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...sections, _footer()],
            ),
          );
        }

        // توزيع بالتناوب لا بالنصف: الأقسام تختلف ارتفاعاً، والقسمة على
        // المنتصف تترك عموداً أطول من الآخر بفارق ظاهر.
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < sections.length; i++) {
          (i.isEven ? left : right).add(sections[i]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
              ],
            ),
            _footer(),
          ],
        );
      }),
    );
  }

  /// أقسام الإعدادات — مُرشَّحة بحسب إصدار المنظمة.
  ///
  /// **لماذا الترشيح لا الإخفاء بالتعطيل:** إعدادٌ لا معنى له في هذا
  /// الإصدار (عرض لفة الطابعة الحرارية لمنظمة بلا بضاعة) ليس «غير متاح» بل
  /// **غير موجود**. وعرضه معطّلاً يدفع المستخدم إلى سؤال الدعم عن سبب
  /// تعطيله.
  List<Widget> _sections(BuildContext context) {
    return [
            SectionCard(
              title: 'الشاشة الرئيسية',
              icon: Icons.home_outlined,
              children: [
                Text(
                  // الخيار يُشرَح بمن يستعمله لا بشكله: «شبكة» و«لوحة»
                  // كلمتان لا تقولان لأحد أيّهما له.
                  'من يفتح النظام ليعرف أرقام اليوم يريد اللوحة، ومن يفتحه '
                  'ليصل إلى شاشة البيع يريد الشبكة. والتفضيل لهذا الجهاز '
                  'وحده — لا يُفرض على بقيّة الأجهزة.',
                  style: AppTextStyles.labelMd(),
                ),
                const SizedBox(height: 8),
                // RadioGroup لا groupValue على كل عنصر: الأخير مهجور منذ
                // 3.32، والمجموعة تُدار من الجدّ.
                RadioGroup<HomeLayout>(
                  groupValue: ref.watch(homeLayoutProvider),
                  onChanged: (v) =>
                      v == null ? null : ref.read(homeLayoutProvider.notifier).set(v),
                  child: Column(
                    children: [
                      for (final option in HomeLayout.values)
                        RadioListTile<HomeLayout>(
                          value: option,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            switch (option) {
                              HomeLayout.auto => 'تبع الجهاز',
                              HomeLayout.dashboard => 'لوحة الأرقام',
                              HomeLayout.shortcuts => 'شبكة الاختصارات',
                            },
                            style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
                          ),
                          subtitle: Text(
                            switch (option) {
                              HomeLayout.auto =>
                                'شبكة على الهاتف، ولوحة أرقام على الشاشات الأوسع',
                              HomeLayout.dashboard => 'مبيعات اليوم والفواتير والمخزون',
                              HomeLayout.shortcuts => 'أيقونات كبيرة لكل شاشة',
                            },
                            style: AppTextStyles.labelMd(),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            SectionCard(
              title: 'بطاقة المحفظة',
              icon: Icons.credit_card_outlined,
              children: [
                Text(
                  'كيف يُتحقَّق من صاحب البطاقة عند الصرف. أنت تضع المظروف هنا، '
                  'ويُختار لكل زبون داخله من شاشة «بطاقات المحفظة». '
                  'الكاشير لا يغيّر النمط لحظة البيع.',
                  style: AppTextStyles.labelMd(),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _cardModes.contains('pin'),
                  onChanged: widget.canEdit ? (v) => _toggleCardMode('pin', v == true) : null,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('بطاقة + رقم سرّي',
                      style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                  subtitle: Text(
                    'الأشدّ. ولا تنسَ أن الزبون يُدخل رقمه على جهاز الكاشير، '
                    'فمن يقف خلفه قد يراه أو يحفظه.',
                    style: AppTextStyles.labelMd(),
                  ),
                ),
                CheckboxListTile(
                  value: _cardModes.contains('card'),
                  onChanged: widget.canEdit ? (v) => _toggleCardMode('card', v == true) : null,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text('البطاقة وحدها بسقف يومي',
                      style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                  subtitle: Text(
                    'لمن لا يحفظ رقماً. لا رقم سرّي يُحفَظ أصلاً فلا شيء يُسرَّب، '
                    'والخطر محصور بالسقف اليومي أدناه لا بكامل الرصيد.',
                    style: AppTextStyles.labelMd(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // بلا isExpanded تُرسَم عناصر القائمة في Row لا يلتفّ،
                  // فعنوانٌ طويل مثل «البطاقة وحدها بسقف يومي» يفيض على
                  // شاشة هاتف — وهو ما أمسكه ui_audit_test فعلاً (112 بكسل).
                  isExpanded: true,
                  initialValue: _cardModes.contains(_cardModeDefault) ? _cardModeDefault : null,
                  decoration: const InputDecoration(
                    labelText: 'النمط الافتراضي للبطاقة الجديدة',
                    helperText: 'ما يبدأ به كل حساب جديد ما لم يُختَر غيره عند الإصدار',
                  ),
                  items: [
                    if (_cardModes.contains('pin'))
                      const DropdownMenuItem(value: 'pin', child: Text('بطاقة + رقم سرّي')),
                    if (_cardModes.contains('card'))
                      const DropdownMenuItem(value: 'card', child: Text('البطاقة وحدها بسقف يومي')),
                  ],
                  onChanged: widget.canEdit ? (v) => setState(() => _cardModeDefault = v ?? _cardModeDefault) : null,
                  validator: (v) => v == null ? 'اختر نمطاً من الأنماط المسموحة' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cardCapController,
                  enabled: widget.canEdit && _cardModes.contains('card'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'السقف اليومي لنمط «البطاقة وحدها»',
                    helperText: 'أقصى ما يُصرف من البطاقة في اليوم بلا رقم سرّي. '
                        'صفر يعني تعطيل النمط فعلياً. وللزبون أن يختار لنفسه سقفاً أقلّ.',
                  ),
                  validator: (v) {
                    if (!_cardModes.contains('card')) return null;
                    final n = double.tryParse(v ?? '');
                    if (n == null || n < 0) return 'رقم غير سالب';
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'نقطة البيع',
              icon: Icons.point_of_sale_outlined,
              children: [
                SwitchListTile(
                  value: _posAllowOpenProduct,
                  onChanged: widget.canEdit ? (v) => setState(() => _posAllowOpenProduct = v) : null,
                  contentPadding: EdgeInsets.zero,
                  title: Text('السماح ببيع الأصناف مفتوحة القيمة',
                      style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                  subtitle: Text(
                    'الكاشير يكتب قيمة الصنف عند البيع بدل سعر ثابت. مفيد للخدمات '
                    'والبضاعة بالقيمة، لكنه يسمح بإصدار فاتورة بمبلغ لا تقابله بضاعة '
                    'في المخزون — راجع سجل التغييرات دورياً عند تفعيله.',
                    style: AppTextStyles.labelMd(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'تكلفة الصنف',
              icon: Icons.inventory_2_outlined,
              children: [
                Text(
                  // ما لا يفعله الخيار يُقال أوّلاً: أكثر ما يُخشى أن يظنّه
                  // المدير تغييراً في حساب الأرباح فيتردّد، أو يغيّره ظانّاً
                  // أنه يُصلح ربحاً — وكلاهما بُني على وهم.
                  'صنفٌ في مخزنه شحنتان بسعرين، وبطاقتُه تعرض رقماً واحداً: '
                  'هو ما يقيس عليه الحدّ الأدنى للسعر ويُعرض به الهامش. '
                  'واختيارُك هنا يضبط ذلك الرقم وحده — أمّا ربح كل فاتورة '
                  'فمحسوبٌ من تكلفة الشحنة التي خرجت منها بضاعتُها فعلاً، '
                  'ولا يتغيّر بهذا الإعداد.',
                  style: AppTextStyles.labelMd(),
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: _costingMethod,
                  onChanged: widget.canEdit
                      ? (v) => v == null ? null : setState(() => _costingMethod = v)
                      : null,
                  child: Column(
                    children: [
                      for (final option in const [
                        ('last_purchase', 'آخر شراء',
                            'سعر آخر شحنة وصلت محمَّلةً بمصاريفها — «بكم أشتريه اليوم». '
                                'وشراءٌ صغير بسعرٍ مرتفع يرفع الرقم لمخزونٍ قديم كلّه.'),
                        ('weighted_average', 'المتوسط المرجّح',
                            'قيمة ما في المخزن مقسومةً على كميّته. لمن يبيع بضاعةً '
                                'متماثلة من شحناتٍ مختلطة — ولا يساوي سعر أي شحنة بعينها.'),
                        ('batch', 'تكلفة الدفعة',
                            'تكلفة الشحنة التي ستخرج في البيع التالي — الأقرب إلى '
                                'الحقيقة، ولمن يتتبّع الصلاحية هو الوحيد الذي لا يكذب.'),
                      ])
                        RadioListTile<String>(
                          value: option.$1,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(option.$2,
                              style: AppTextStyles.bodyMd(color: AppColors.textPrimary)),
                          subtitle: Text(option.$3, style: AppTextStyles.labelMd()),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // النسخة الاحتياطية بصلاحيتها لا بدور المستخدم: مالك المنظمة
            // قد يمنحها محاسبه ليحفظ النسخ الأسبوعية، وقد لا يمنحها أحداً.
            // و`Can` يقرأ نفس الرمز الذي يفحصه الخادم (backup.manage)، فلا
            // يظهر زرٌّ يردّه الخادم بـ403 بلا سبب يفهمه من ضغطه.
            //
            // ولا يتبع canEdit: تلك «أيعدّل الإعدادات؟» وهي شيء آخر —
            // ربطُهما كان يعني أن منح صلاحية النسخ يستلزم فتح كل الإعدادات.
            //
            // والمسافة داخل `Can` لا قبله: خارجه تبقى فجوة 16 بكسل معلّقة
            // في قائمة من لا يملك الصلاحية.
            const Can(
              permission: Perm.backupManage,
              child: Padding(padding: EdgeInsets.only(top: 16), child: BackupSection()),
            ),
    ];
  }

  /// الشريط والزرّ خارج الأعمدة: توزيعهما مع الأقسام كان يضع «حفظ» في منتصف
  /// الشاشة تحت عمود واحد، ويكرّر تنبيه «عرض فقط» أو يُخفيه بحسب العدد.
  Widget _footer() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.canEdit) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(8)),
              child: Text('عرض فقط — تعديل الإعدادات متاح للمدير العام فقط',
                  style: AppTextStyles.bodyMd(color: AppColors.warning)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
          if (widget.canEdit) ...[
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ الإعدادات'),
              ),
            ),
          ],
        ],
      );

  /// إلغاء آخر نمط مسموح يعني حساباً لا يُصرَف منه أبداً — يُرفض هنا لا عند
  /// الحفظ، فالمستخدم يرى السبب في لحظته.
  void _toggleCardMode(String mode, bool on) {
    setState(() {
      if (on) {
        _cardModes.add(mode);
      } else if (_cardModes.length > 1) {
        _cardModes.remove(mode);
        // الافتراضي يتبع المسموح تلقائياً: تركُه على نمط أُلغي يُسقط كل حساب
        // جديد إلى مسار لم يقصده أحد.
        if (!_cardModes.contains(_cardModeDefault)) _cardModeDefault = _cardModes.first;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب السماح بنمط تحقّق واحد على الأقل')),
        );
      }
    });
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
        'inventoryCostingMethod': _costingMethod,
        'posAllowOpenProduct': _posAllowOpenProduct,
        'cardModesAllowed': _cardModes.join(','),
        'cardModeDefault': _cardModeDefault,
        'cardOpenModeDailyCap': double.parse(_cardCapController.text),
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
