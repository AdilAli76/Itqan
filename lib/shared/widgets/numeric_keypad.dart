import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// حجم اللوحة — الفرق ليس جمالياً: 44 نقطة هو أصغر هدف لمس موصى به من
/// إرشادات Material، و64 هو المريح لكاشير يعمل بإصبعه ساعات على شاشة لمس
/// دون النظر إلى يده. xlarge هو حجم ضخم جداً للشاشات الكبيرة والأصابع الثقيلة.
enum KeypadSize { compact, large, xlarge }

/// لوحة أرقام على شكل آلة حاسبة — بديل حقل الإدخال في نقطة البيع.
///
/// تعمل بالنقر وبلوحة المفاتيح الفعلية معاً: الكاشير على شاشة لمس ينقر،
/// والكاشير المعتاد على الكتابة لا يُجبر على رفع يده إلى الشاشة. وترتيب
/// الأرقام من الأسفل (7-8-9 في الأعلى) هو ترتيب الآلة الحاسبة ولوحة الأرقام
/// في الكيبورد، لا ترتيب الهاتف (1-2-3 في الأعلى) — من يعمل على نقطة بيع
/// معتاد على الأول.
///
/// استُخرجت من CashPaymentDialog لتُستخدم في إدخال الكمية والقيمة المفتوحة
/// أيضاً، فيبقى سلوك الأرقام واحداً في الشاشة كلها.
class NumericKeypad extends StatefulWidget {
  const NumericKeypad({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = KeypadSize.compact,
    this.allowDecimal = true,
    this.decimalPlaces = 2,
    this.maxIntegerDigits = 9,
    this.onSubmit,
    this.autofocus = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final KeypadSize size;

  /// الكمية في بعض الأصناف عدد صحيح (قطع)، وفي غيرها كسرية (كيلوغرام).
  final bool allowDecimal;
  final int decimalPlaces;

  /// حدّ يمنع رقماً بطول لا معنى له نتيجة نقرة مستمرة بالخطأ.
  final int maxIntegerDigits;

  /// يُستدعى عند Enter من لوحة المفاتيح — يختصر خطوة الضغط على زر التأكيد.
  final VoidCallback? onSubmit;
  final bool autofocus;

  @override
  State<NumericKeypad> createState() => _NumericKeypadState();
}

class _NumericKeypadState extends State<NumericKeypad> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _press(String key) {
    final current = widget.value;

    switch (key) {
      case 'clear':
        widget.onChanged('');
        return;
      case 'del':
        if (current.isNotEmpty) widget.onChanged(current.substring(0, current.length - 1));
        return;
      case '.':
        if (!widget.allowDecimal || current.contains('.')) return;
        widget.onChanged(current.isEmpty ? '0.' : '$current.');
        return;
      case '00':
        // دفعة واحدة: النداء مرتين على _append يقرأ widget.value القديمة،
        // لأن onChanged يصعد إلى الأب ولا يُحدِّث القيمة هنا فوراً.
        _append('00');
        return;
      default:
        _append(key);
    }
  }

  void _append(String digits) {
    final current = widget.value;
    final parts = current.split('.');

    // بعد الفاصلة: منع دقة أكثر من المطلوب (قيمة نقدية لا تحتاج أكثر من فلسين).
    if (parts.length == 2) {
      if (parts[1].length + digits.length > widget.decimalPlaces) return;
    } else if (parts[0].length + digits.length > widget.maxIntegerDigits) {
      return;
    }

    // منع أصفار بادئة عديمة المعنى: "0" ثم "5" تصبح "5" لا "05".
    if (current == '0') {
      widget.onChanged(digits == '00' ? '0' : digits);
      return;
    }
    widget.onChanged(current + digits);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final logical = event.logicalKey;
    if (logical == LogicalKeyboardKey.backspace) {
      _press('del');
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.delete || logical == LogicalKeyboardKey.escape) {
      _press('clear');
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.enter || logical == LogicalKeyboardKey.numpadEnter) {
      widget.onSubmit?.call();
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char == null || char.length != 1) return KeyEventResult.ignored;
    if (char == '.' || char == ',') {
      // الفاصلة العشرية في لوحة الأرقام العربية قد تأتي فاصلةً لا نقطة.
      _press('.');
      return KeyEventResult.handled;
    }
    final code = char.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) {
      _press(char);
      return KeyEventResult.handled;
    }
    // الأرقام العربية الهندية (٠-٩) — لوحة مفاتيح معرَّبة تُرسلها كما هي.
    if (code >= 0x0660 && code <= 0x0669) {
      _press(String.fromCharCode(code - 0x0660 + 0x30));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _keyHeight {
    switch (widget.size) {
      case KeypadSize.xlarge:
        return 88;
      case KeypadSize.large:
        return 64;
      case KeypadSize.compact:
        return 44;
    }
  }

  double get _gap {
    switch (widget.size) {
      case KeypadSize.xlarge:
        return 14;
      case KeypadSize.large:
        return 10;
      case KeypadSize.compact:
        return 8;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      [widget.allowDecimal ? '.' : '00', '0', 'del'],
    ];

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows) ...[
            Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) SizedBox(width: _gap),
                  Expanded(
                    child: _KeypadKey(
                      label: row[i],
                      height: _keyHeight,
                      size: widget.size,
                      onTap: () => _press(row[i]),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: _gap),
          ],
          _KeypadKey(
            label: 'clear',
            height: _keyHeight,
            size: widget.size,
            onTap: () => _press('clear'),
          ),
        ],
      ),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({
    required this.label,
    required this.height,
    required this.size,
    required this.onTap,
  });

  final String label;
  final double height;
  final KeypadSize size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isClear = label == 'clear';
    final isDelete = label == 'del';
    final isXlarge = size == KeypadSize.xlarge;
    final isLarge = size == KeypadSize.large;

    Widget child;
    if (isDelete) {
      child = Icon(
        Icons.backspace_outlined,
        size: isXlarge ? 40 : (isLarge ? 28 : 20),
      );
    } else if (isClear) {
      final style = isXlarge
          ? AppTextStyles.displayMd()
          : (isLarge ? AppTextStyles.headlineMd() : AppTextStyles.bodyMd());
      child = Text('مسح', style: style);
    } else {
      final style = isXlarge
          ? const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: AppColors.textPrimary)
          : (isLarge
              ? AppTextStyles.displayLg(color: AppColors.textPrimary)
              : AppTextStyles.headlineMd(color: AppColors.textPrimary));
      child = Text(label, style: style);
    }

    return SizedBox(
      height: height,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isClear ? AppColors.danger : AppColors.textPrimary,
          side: BorderSide(color: isClear ? AppColors.danger.withValues(alpha: 0.4) : AppColors.border),
        ),
        onPressed: onTap,
        child: child,
      ),
    );
  }
}

/// شاشة عرض الرقم المُدخَل — كبيرة ومقروءة من مسافة، فوق اللوحة دائماً.
class KeypadDisplay extends StatelessWidget {
  const KeypadDisplay({
    super.key,
    required this.value,
    this.suffix,
    this.placeholder = '0',
    this.label,
  });

  final String value;
  final String? suffix;
  final String placeholder;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            Text(label!, style: AppTextStyles.labelMd(), textAlign: TextAlign.center),
            const SizedBox(height: 4),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.isEmpty ? placeholder : value,
                style: AppTextStyles.displayLg(
                  color: value.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Text(suffix!, style: AppTextStyles.bodyMd()),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// نافذة إدخال رقم واحد بلوحة الأرقام — تُستخدم للكمية والقيمة المفتوحة.
/// تُرجع القيمة، أو null إن أُلغيت.
Future<double?> showNumericEntryDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  String? suffix,
  double? initialValue,
  bool allowDecimal = true,
  int decimalPlaces = 2,
  double minValue = 0,
  KeypadSize size = KeypadSize.compact,
  String confirmLabel = 'تأكيد',
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _NumericEntryDialog(
      title: title,
      subtitle: subtitle,
      suffix: suffix,
      initialValue: initialValue,
      allowDecimal: allowDecimal,
      decimalPlaces: decimalPlaces,
      minValue: minValue,
      size: size,
      confirmLabel: confirmLabel,
    ),
  );
}

class _NumericEntryDialog extends StatefulWidget {
  const _NumericEntryDialog({
    required this.title,
    required this.subtitle,
    required this.suffix,
    required this.initialValue,
    required this.allowDecimal,
    required this.decimalPlaces,
    required this.minValue,
    required this.size,
    required this.confirmLabel,
  });

  final String title;
  final String? subtitle;
  final String? suffix;
  final double? initialValue;
  final bool allowDecimal;
  final int decimalPlaces;
  final double minValue;
  final KeypadSize size;
  final String confirmLabel;

  @override
  State<_NumericEntryDialog> createState() => _NumericEntryDialogState();
}

class _NumericEntryDialogState extends State<_NumericEntryDialog> {
  late String _text = _format(widget.initialValue);

  static String _format(double? value) {
    if (value == null || value <= 0) return '';
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  double get _parsed => double.tryParse(_text) ?? 0;
  bool get _isValid => _parsed > 0 && _parsed >= widget.minValue;

  void _submit() {
    if (!_isValid) return;
    Navigator.pop(context, _parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: widget.size == KeypadSize.large ? 420 : 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.subtitle != null) ...[
                Text(widget.subtitle!, style: AppTextStyles.bodyMd()),
                const SizedBox(height: 12),
              ],
              KeypadDisplay(value: _text, suffix: widget.suffix),
              const SizedBox(height: 16),
              NumericKeypad(
                value: _text,
                onChanged: (v) => setState(() => _text = v),
                size: widget.size,
                allowDecimal: widget.allowDecimal,
                decimalPlaces: widget.decimalPlaces,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _isValid ? _submit : null, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
