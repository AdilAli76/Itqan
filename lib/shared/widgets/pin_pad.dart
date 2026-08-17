import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// إدخال رقم سري بلوحة أرقام بدل حقل نصي — يعمل بالنقر وبلوحة المفاتيح
/// معاً، ويقبل الأرقام فقط بحكم تصميمه لا بحكم فلتر قد يُنسى. اختير بعد
/// بلاغ بتعذّر الكتابة في الحقل النصي على سطح المكتب: اللوحة لا تعتمد على
/// سلوك حقل الإدخال أصلاً، وهي الأنسب لرقم سري على شاشة لمس كذلك.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.maxLength = 6,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int maxLength;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // لوحة المفاتيح الفعلية تعمل أيضاً — المستخدم المعتاد على الكتابة
    // لا يُجبَر على استخدام الفأرة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _press(String key) {
    if (key == 'del') {
      if (widget.value.isNotEmpty) {
        widget.onChanged(widget.value.substring(0, widget.value.length - 1));
      }
      return;
    }
    if (widget.value.length >= widget.maxLength) return;
    widget.onChanged(widget.value + key);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _press('del');
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1 && char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39) {
      _press(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // خانات الرقم السري — تُظهر عدد ما أُدخل دون كشف الأرقام نفسها.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.maxLength, (i) {
                final filled = i < widget.value.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    border: Border.all(
                      color: filled ? Theme.of(context).colorScheme.primary : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.0,
            children: [
              for (final key in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                _PinKey(label: key, onTap: () => _press(key)),
              const SizedBox.shrink(),
              _PinKey(label: '0', onTap: () => _press('0')),
              _PinKey(icon: Icons.backspace_outlined, onTap: () => _press('del')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({this.label, this.icon, required this.onTap});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
      onPressed: onTap,
      child: icon != null
          ? Icon(icon, size: 20)
          : Text(label!, style: AppTextStyles.headlineMd()),
    );
  }
}
