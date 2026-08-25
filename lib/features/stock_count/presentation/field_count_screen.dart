import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/pos_sounds.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../pos/presentation/barcode_scanner_sheet.dart';
import '../data/stock_count_providers.dart';

/// ما تعرضه الشاشة الآن — سؤالٌ واحد لا أكثر.
///
/// **الاستثناءات مسمّاة قبل المسار الناجح، لا بعده.** فحص الواجهات الكفّية
/// في myWMS يعطي الدرس: عملية الالتقاط عندهم عشرون شاشة، الناجح منها أربع.
/// الستّ عشرة الباقية استثناءات — والمنتج هو أن يجد العامل الواقف أمام رفٍّ
/// فارغ زرّاً يقول «فارغ» فيمضي. بلا ذلك الزرّ يخرج من النظام ويكتب على
/// ورقة، وتنتهي صلاحية النظام كلّه.
enum _Step {
  /// الاستثناء الأول: رمزٌ لا صنف له في الكتالوج إطلاقاً.
  unknownCode,

  /// الاستثناء الثاني: صنف موجود على الرفّ وليس في قائمة هذا الجرد.
  unlisted,

  /// الاستثناء الثالث: عُدَّ في هذه الجولة من قبل — تكرارٌ أو تصحيح.
  alreadyCounted,

  /// الاستثناء الرابع: فشل الإرسال. الرقم في يد العامل ولم يصل الخادم.
  saveFailed,

  /// المسار الناجح: امسح.
  scan,

  /// المسار الناجح: أدخل الكمية.
  quantity,
}

/// شاشة الجرد الميداني — سؤال واحد، حقل مسح واحد، زرّان.
///
/// <para><b>القالب المنقول:</b> سياقٌ للقراءة أعلاه، حقل إدخال واحد يستقبل
/// المسح، وزرّان لا أكثر. لا قوائم منسدلة، ولا تبويبات، ولا شبكات بيانات —
/// من يمسك جهازاً بيد وصندوقاً بالأخرى لا يتصفّح جدولاً.</para>
///
/// <para><b>وما تعرضه دائماً:</b> «بقي كذا من كذا». هذا الرقم هو الشاشة
/// كلّها عملياً — ولم يكن ممكناً قبل عمود <c>counted_at</c>، إذ كان الجرد
/// الدوري يبدأ بكمية معدودة مساوية للنظامية فيبدو كل شيء «مَعدوداً».</para>
class FieldCountScreen extends ConsumerStatefulWidget {
  const FieldCountScreen({super.key, required this.countId});

  final String countId;

  @override
  ConsumerState<FieldCountScreen> createState() => _FieldCountScreenState();
}

class _FieldCountScreenState extends ConsumerState<FieldCountScreen> {
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();
  final _quantityController = TextEditingController();

  _Step _step = _Step.scan;
  bool _busy = false;
  String? _message;

  /// السطر المعروض الآن.
  Map<String, dynamic>? _item;

  /// الصنف غير المُدرَج المنتظر قراراً.
  Map<String, dynamic>? _unlistedProduct;

  /// آخر كمية تعذّر إرسالها — تُعاد المحاولة بها لا بصفر.
  double? _pendingQuantity;

  int _counted = 0;
  int _total = 0;

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // ── الاستثناءات أولاً ──────────────────────────────────────────────────

  /// رمزٌ لا صنف له. لا يُسمح بإنشاء صنف من هنا عمداً: تسجيل صنف يحتاج سعراً
  /// ووحدة وتصنيفاً، ومن يقف أمام رفّ لا يملكها — فيخرج بصنف ناقص يُفسد
  /// الكتالوج. يُسجَّل ما وُجد ويُكمَل لاحقاً.
  Widget _unknownCodeStep() => _Frame(
        title: 'رمز غير معروف',
        tone: _Tone.warning,
        body: [
          Text(_message ?? '', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 12),
          Text(
            'قد يكون الرمز مقروءاً خطأً، أو الصنف غير مسجَّل في الكتالوج بعد. '
            'سجّله من شاشة الأصناف ثم أعد المسح.',
            style: AppTextStyles.labelMd(),
          ),
        ],
        primaryLabel: 'أعد المسح',
        onPrimary: _reset,
        secondaryLabel: 'تخطَّ',
        onSecondary: _reset,
      );

  /// صنف على الرفّ وليس في القائمة — `ConfirmUnexpectedUnitLoad`.
  Widget _unlistedStep() => _Frame(
        title: 'ليس في قائمة الجرد',
        tone: _Tone.warning,
        body: [
          Text(_unlistedProduct?['name'] as String? ?? '', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 8),
          Text(_message ?? '', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 12),
          Text(
            'يقع هذا في الجرد الموزَّع: القائمة تستبعد ما عُدَّ حديثاً. '
            'أضِفه لتعدّه الآن، أو تخطَّه ليبقى خارج هذه الجولة.',
            style: AppTextStyles.labelMd(),
          ),
        ],
        primaryLabel: 'أضِفه وعُدَّه',
        onPrimary: _addUnlisted,
        secondaryLabel: 'تخطَّ',
        onSecondary: _reset,
      );

  /// عُدَّ من قبل في هذه الجولة. لا يُكتب فوقه صامتاً: التكرار غالباً خطأ
  /// (صنف مُرَّ عليه مرّتين) وأحياناً تصحيح مقصود — ومن يقف أمام الرفّ هو من
  /// يعرف أيّهما، لا الخادم ولا الشاشة.
  Widget _alreadyCountedStep() => _Frame(
        title: 'عُدَّ من قبل',
        tone: _Tone.warning,
        body: [
          Text(_item?['productName'] as String? ?? '', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 8),
          Text(_message ?? '', style: AppTextStyles.bodyLg()),
          const SizedBox(height: 12),
          Text(
            'إن كنت مررت على هذا الصنف مرّتين فتخطَّه. '
            'وإن كنت تصحّح رقماً أدخلته خطأً فأعد العدّ.',
            style: AppTextStyles.labelMd(),
          ),
        ],
        primaryLabel: 'أعِد العدّ',
        onPrimary: () => setState(() {
          _step = _Step.quantity;
          _quantityController.text = '';
          _message = null;
        }),
        secondaryLabel: 'تخطَّ',
        onSecondary: _reset,
      );

  /// فشل الإرسال. **الرقم لا يُمحى**: العامل عدّ صندوقاً فعلاً، ومسحُ رقمه
  /// لعطل شبكة يعني إعادة العدّ من الرفّ. يُعاد الإرسال بنفس الرقم.
  Widget _saveFailedStep() => _Frame(
        title: 'لم يصل الرقم',
        tone: _Tone.danger,
        body: [
          Text(_item?['productName'] as String? ?? '', style: AppTextStyles.headlineMd()),
          const SizedBox(height: 8),
          Text(
            'الكمية التي أدخلتها: ${_pendingQuantity?.toStringAsFixed(3) ?? '-'}',
            style: AppTextStyles.bodyLg(),
          ),
          const SizedBox(height: 8),
          Text(_message ?? '', style: AppTextStyles.bodyMd(color: AppColors.danger)),
          const SizedBox(height: 12),
          Text(
            'رقمك محفوظ هنا ولم يُمحَ. أعد المحاولة حين يعود الاتصال.',
            style: AppTextStyles.labelMd(),
          ),
        ],
        primaryLabel: 'أعد المحاولة',
        onPrimary: () => _saveQuantity(_pendingQuantity ?? 0),
        secondaryLabel: 'تخطَّ الصنف',
        onSecondary: _reset,
      );

  // ── المسار الناجح ──────────────────────────────────────────────────────

  Widget _scanStep() => _Frame(
        title: 'امسح باركود الصنف',
        tone: _Tone.neutral,
        body: [
          TextField(
            controller: _codeController,
            focusNode: _codeFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            // الحجم كبير عمداً: يُقرأ بطرف العين ويد واحدة تمسك الجهاز.
            style: AppTextStyles.displayLg(),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'امسح أو اكتب الرمز',
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'مسح بالكاميرا',
                onPressed: _scanWithCamera,
              ),
            ),
            onSubmitted: (v) => _lookUp(v),
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(_message!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
          ],
        ],
        primaryLabel: 'ابحث',
        onPrimary: () => _lookUp(_codeController.text),
        secondaryLabel: 'إنهاء العدّ',
        onSecondary: _finish,
      );

  Widget _quantityStep() {
    final item = _item;
    if (item == null) return _scanStep();

    final unit = _unitLabel(item['unitBase'] as String?);
    return _Frame(
      title: 'كم على الرفّ؟',
      tone: _Tone.neutral,
      body: [
        Text(item['productName'] as String? ?? '', style: AppTextStyles.headlineMd()),
        const SizedBox(height: 4),
        Text('رمز الصنف: ${item['sku'] ?? '-'}', style: AppTextStyles.labelMd()),
        const SizedBox(height: 16),
        TextField(
          controller: _quantityController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          style: AppTextStyles.displayLg(),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            // الوحدة معروضة دائماً: بلاها يُدخِل العادّ حبّات مكان علب،
            // فيظهر فرقٌ هائل لا وجود له.
            suffixText: unit,
            hintText: '0',
          ),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          onSubmitted: (_) => _submitQuantity(),
        ),
        const SizedBox(height: 12),
        // **الكمية النظامية لا تُعرَض هنا عمداً.** عرضُها يجعل العادّ يؤكّدها
        // بضغطة بدل أن يعدّ — وهو ما يُبطل الجرد كلّه. تظهر بعد الإدخال في
        // شاشة الفروقات، حيث تُراجَع لا تُملى.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _saveQuantity(0),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                // الزرّ الذي يجعل الشاشة صالحة أصلاً: من يقف أمام رفّ فارغ
                // يحتاج مخرجاً بضغطة، لا كتابةَ صفرٍ يشكّ أنه أخطأ فيه.
                label: const Text('الرفّ فارغ'),
              ),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(_message!, style: AppTextStyles.bodyMd(color: AppColors.danger)),
        ],
      ],
      primaryLabel: 'تأكيد',
      onPrimary: _submitQuantity,
      secondaryLabel: 'تخطَّ',
      onSecondary: _reset,
    );
  }

  // ── المنطق ─────────────────────────────────────────────────────────────

  Future<void> _scanWithCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerSheet(), fullscreenDialog: true),
    );
    if (code != null && code.trim().isNotEmpty) await _lookUp(code);
  }

  Future<void> _lookUp(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await ApiClient.instance.dio.get('/stock-counts/${widget.countId}/scan/$code');
      final data = response.data as Map<String, dynamic>;
      final outcome = data['outcome'] as String?;
      final item = data['item'] as Map<String, dynamic>?;

      _codeController.clear();

      switch (outcome) {
        case 'found':
          PosSounds.scan();
          setState(() {
            _item = item;
            _quantityController.text = '';
            _step = _Step.quantity;
          });
        case 'already_counted':
          PosSounds.error();
          setState(() {
            _item = item;
            _message = data['message'] as String?;
            _step = _Step.alreadyCounted;
          });
        case 'unlisted':
          PosSounds.error();
          setState(() {
            // الاسم يأتي في الرسالة، والمعرّف يُجلَب عند الإضافة بالبحث
            // نفسه — لا نحمل الكتالوج إلى الجهاز.
            _unlistedProduct = {'code': code, 'name': _nameFromMessage(data['message'] as String?)};
            _message = data['message'] as String?;
            _step = _Step.unlisted;
          });
        default:
          PosSounds.error();
          setState(() {
            _message = data['message'] as String?;
            _step = _Step.unknownCode;
          });
      }
    } catch (e) {
      PosSounds.error();
      setState(() => _message = _errorMessage(e, 'تعذّر البحث عن الرمز'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitQuantity() {
    final value = double.tryParse(_quantityController.text.trim());
    if (value == null || value < 0) {
      setState(() => _message = 'أدخل كمية صحيحة');
      return;
    }
    _saveQuantity(value);
  }

  Future<void> _saveQuantity(double quantity) async {
    final item = _item;
    if (item == null || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ApiClient.instance.dio.put(
        '/stock-counts/${widget.countId}/items/${item['id']}',
        data: {'countedQuantity': quantity},
      );
      PosSounds.success();
      _pendingQuantity = null;
      ref.invalidate(stockCountDetailProvider(widget.countId));
      _reset();
    } catch (e) {
      PosSounds.error();
      setState(() {
        // الرقم يُحفَظ هنا لا يُمحى — راجع _saveFailedStep.
        _pendingQuantity = quantity;
        _message = _errorMessage(e, 'تعذّر إرسال الكمية');
        _step = _Step.saveFailed;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addUnlisted() async {
    final code = _unlistedProduct?['code'] as String?;
    if (code == null || _busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // المعرّف يُحلّ من نفس الرمز: البحث بالمطابقة التامّة على الخادم، فلا
      // يُحمَّل الكتالوج ولا يُختار من قائمة على شاشة صغيرة.
      final search = await ApiClient.instance.dio.get('/products', queryParameters: {
        'search': code,
        'pageSize': 5,
      });
      final body = search.data;
      final list = body is List ? body : (body as Map<String, dynamic>)['items'] as List;
      final match = list.cast<Map<String, dynamic>>().firstWhere(
            (p) => p['barcode'] == code || p['sku'] == code,
            orElse: () => <String, dynamic>{},
          );
      if (match.isEmpty) {
        setState(() {
          _message = 'تعذّر تحديد الصنف من الرمز $code';
          _step = _Step.unknownCode;
        });
        return;
      }

      final added = await ApiClient.instance.dio.post(
        '/stock-counts/${widget.countId}/items',
        data: {'productId': match['id']},
      );
      PosSounds.scan();
      ref.invalidate(stockCountDetailProvider(widget.countId));
      setState(() {
        _item = added.data as Map<String, dynamic>;
        _unlistedProduct = null;
        _quantityController.text = '';
        _step = _Step.quantity;
      });
    } catch (e) {
      PosSounds.error();
      setState(() => _message = _errorMessage(e, 'تعذّرت إضافة الصنف'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final remaining = _total - _counted;
    if (remaining > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('بقيت أصناف لم تُعدّ'),
          content: Text(
            'بقي $remaining صنفاً لم تقف أمامه. إنهاء العدّ الآن يُسجَّل '
            'صراحةً بأنه غير مكتمل — فمن يراجع الفروقات لاحقاً يعرف أن '
            'جزءاً من الرفوف لم يُنظَر إليه.',
            style: AppTextStyles.bodyMd(color: AppColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('أُكمل العدّ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إنهاء غير مكتمل'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.post(
        '/stock-counts/${widget.countId}/submit',
        data: {'force': remaining > 0},
      );
      ref.invalidate(stockCountDetailProvider(widget.countId));
      ref.invalidate(stockCountsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _message = _errorMessage(e, 'تعذّر إنهاء العدّ'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    setState(() {
      _step = _Step.scan;
      _item = null;
      _unlistedProduct = null;
      _message = null;
      _codeController.clear();
      _quantityController.clear();
    });
    // إعادة التركيز إلى حقل المسح: القارئ السلكي يكتب حيث التركيز، وبلا هذا
    // تذهب المسحة التالية إلى لا مكان فيظنّ العامل أن القارئ تعطّل.
    WidgetsBinding.instance.addPostFrameCallback((_) => _codeFocus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(stockCountDetailProvider(widget.countId));

    detail.whenData((data) {
      final items = (data['items'] as List?) ?? const [];
      final total = items.length;
      final uncounted = (data['uncountedCount'] as num?)?.toInt() ?? 0;
      if (total != _total || total - uncounted != _counted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _total = total;
            _counted = total - uncounted;
          });
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('جرد ميداني'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _Progress(counted: _counted, total: _total),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_step) {
            _Step.unknownCode => _unknownCodeStep(),
            _Step.unlisted => _unlistedStep(),
            _Step.alreadyCounted => _alreadyCountedStep(),
            _Step.saveFailed => _saveFailedStep(),
            _Step.scan => _scanStep(),
            _Step.quantity => _quantityStep(),
          },
        ),
      ),
    );
  }

  String? _nameFromMessage(String? message) {
    if (message == null) return null;
    final match = RegExp('«(.+?)»').firstMatch(message);
    return match?.group(1);
  }

  String _unitLabel(String? unitBase) => switch (unitBase) {
        'kg' => 'كجم',
        'litre' => 'لتر',
        'metre' => 'متر',
        'box' => 'علبة',
        _ => 'قطعة',
      };

  String _errorMessage(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (e.response == null) return 'لا اتصال بالخادم';
    }
    return fallback;
  }
}

// ═══════════════════════════════════════════════════════════════════════════

enum _Tone { neutral, warning, danger }

/// إطار الشاشة الواحدة: عنوان + جسم + زرّان. **لا ثالث لهما** — كل زرّ إضافي
/// قرارٌ يُطلب ممّن يحمل جهازاً بيد وصندوقاً بالأخرى.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.tone,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String title;
  final _Tone tone;
  final List<Widget> body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      _Tone.warning => (AppColors.warning, AppColors.warningBg),
      _Tone.danger => (AppColors.danger, AppColors.dangerBg),
      _Tone.neutral => (AppColors.textPrimary, AppColors.surfaceAlt),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          // العنوان يقول العملية الحالية بلا لبس — ما يفعله المستخدم الآن،
          // لا اسم الشاشة.
          child: Text(title, style: AppTextStyles.headlineLg(color: fg), textAlign: TextAlign.center),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
        ),
        const SizedBox(height: 16),
        // الأزرار كبيرة: إصبعٌ في قفّاز مستودع لا يُصيب زرّاً بارتفاع 36.
        SizedBox(
          height: 56,
          child: FilledButton(onPressed: onPrimary, child: Text(primaryLabel, style: AppTextStyles.bodyLg())),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel)),
        ),
      ],
    );
  }
}

/// «بقي كذا من كذا» — الرقم الذي تدور حوله الشاشة.
class _Progress extends StatelessWidget {
  const _Progress({required this.counted, required this.total});

  final int counted;
  final int total;

  @override
  Widget build(BuildContext context) {
    final remaining = (total - counted).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('عُدَّ $counted من $total', style: AppTextStyles.labelMd(color: Colors.white)),
              Text('بقي $remaining', style: AppTextStyles.labelMd(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : counted / total,
              minHeight: 6,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}
