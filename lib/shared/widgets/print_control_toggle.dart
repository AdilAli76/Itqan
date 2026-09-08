import 'package:flutter/material.dart';

/// زرّ التحكم في الطباعة — يتيح للكاشير اختيار هل يطبع الإيصال أم لا.
class PrintControlToggle extends StatefulWidget {
  final Function(bool) onChanged;
  final bool initialValue;

  const PrintControlToggle({
    Key? key,
    required this.onChanged,
    this.initialValue = true,
  }) : super(key: key);

  @override
  State<PrintControlToggle> createState() => _PrintControlToggleState();
}

class _PrintControlToggleState extends State<PrintControlToggle> {
  late bool _shouldPrint;

  @override
  void initState() {
    super.initState();
    _shouldPrint = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _shouldPrint = !_shouldPrint;
        });
        widget.onChanged(_shouldPrint);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: _shouldPrint ? Colors.green : Colors.orange,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          color: _shouldPrint ? Colors.green.shade50 : Colors.orange.shade50,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _shouldPrint ? Icons.print : Icons.print_disabled,
              color: _shouldPrint ? Colors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _shouldPrint ? 'طباعة مفعّلة' : 'بدون طباعة',
              style: TextStyle(
                color: _shouldPrint ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// نسخة بسيطة للاستخدام في الحوارات والشاشات الصغيرة.
class PrintControlCheckbox extends StatefulWidget {
  final Function(bool) onChanged;
  final bool initialValue;
  final String? label;

  const PrintControlCheckbox({
    Key? key,
    required this.onChanged,
    this.initialValue = true,
    this.label,
  }) : super(key: key);

  @override
  State<PrintControlCheckbox> createState() => _PrintControlCheckboxState();
}

class _PrintControlCheckboxState extends State<PrintControlCheckbox> {
  late bool _shouldPrint;

  @override
  void initState() {
    super.initState();
    _shouldPrint = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: _shouldPrint,
      onChanged: (value) {
        if (value != null) {
          setState(() => _shouldPrint = value);
          widget.onChanged(value);
        }
      },
      title: Text(widget.label ?? 'طباعة الإيصال'),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
    );
  }
}
