import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/passkey.dart';
import '../../../core/auth/session_lock.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// إدارة مفاتيح المرور: ما هو مسجَّل، وإضافةُ مفتاح، وحذفُه.
///
/// <para><b>سبب وجودها هنا:</b> هذه شاشة أمان الحساب — كلمة المرور والقفل
/// والمفاتيح شيءٌ واحد عند صاحبها. ووضعُها في الإعدادات كان يخفيها عن
/// الكاشير: تلك الشاشة مقصورة على المديرين، وأوّل من يترك جهازه مفتوحاً هو
/// من يقف على نقطة البيع.</para>
///
/// <para><b>والمفتاح على الجهاز لا على الحساب:</b> من يعمل على حاسوب المكتب
/// وهاتفه يسجّل مفتاحاً على كلٍّ منهما. ولهذا تُطلَب تسمية: قائمةٌ فيها
/// ثلاثة مفاتيح بلا أسماء لا يُعرف أيّها لجهازٍ بيع أو فُقد.</para>
class PasskeysSection extends ConsumerStatefulWidget {
  const PasskeysSection({super.key});

  @override
  ConsumerState<PasskeysSection> createState() => _PasskeysSectionState();
}

class _PasskeysSectionState extends ConsumerState<PasskeysSection> {
  List<Map<String, dynamic>>? _keys;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await ApiClient.instance.dio.get('/passkeys');
      final list = (response.data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _keys = list);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 40),
        Text('مفاتيح المرور', style: AppTextStyles.headlineMd(), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          // ما يفعله المفتاح وما لا يفعله يُقال صراحةً: من يظنّه بديلاً عن
          // كلمة المرور في الدخول يجرّبه على جهازٍ آخر فيظنّ الميزة معطوبة.
          'يفتح الشاشة المقفلة ببصمتك أو رمز جهازك بدل كتابة كلمة المرور. '
          'والدخول أوّل مرّة يبقى بكلمة المرور، والمفتاح لا يغادر هذا الجهاز.',
          style: AppTextStyles.caption(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (keys == null && _error == null)
          const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else if (keys != null && keys.isEmpty)
          Text('لا مفاتيح مسجَّلة بعد.',
              style: AppTextStyles.bodyMd(color: AppColors.textMuted), textAlign: TextAlign.center)
        else if (keys != null)
          ...keys.map(_tile),
        const SizedBox(height: 12),
        if (Passkeys.isSupported)
          OutlinedButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.fingerprint, size: 18),
            label: const Text('أضف مفتاحاً على هذا الجهاز'),
          )
        else
          Text(
            // ولا يُخفى الزرّ بلا سبب: من لا يجده يظنّ الحساب محروماً منه،
            // بينما المانع هو الجهاز — ويكفي أن يفتح النظام من متصفّح.
            'هذا الجهاز لا يدعم مفاتيح المرور — افتح النظام من متصفّحٍ حديث لتسجيل مفتاح.',
            style: AppTextStyles.caption(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        if (keys != null && keys.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => ref.read(sessionLockProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('اقفل الشاشة الآن'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: AppTextStyles.bodyMd(color: AppColors.danger), textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Widget _tile(Map<String, dynamic> key) {
    final lastUsed = key['lastUsedAt'] as String?;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined, size: 20),
      title: Text('${key['label']}', style: AppTextStyles.bodyMd()),
      subtitle: Text(
        lastUsed == null ? 'لم يُستعمل بعد' : 'آخر استعمال: ${_date(lastUsed)}',
        style: AppTextStyles.caption(color: AppColors.textSecondary),
      ),
      trailing: IconButton(
        onPressed: _busy ? null : () => _remove(key),
        icon: const Icon(Icons.delete_outline, size: 20),
        tooltip: 'احذف المفتاح',
      ),
    );
  }

  /// التاريخ وحده يكفي هنا: «متى استُعمل آخر مرّة» سؤالٌ عن يومٍ لا عن دقيقة.
  String _date(String raw) {
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    return '${parsed.year}/${parsed.month}/${parsed.day}';
  }

  Future<void> _add() async {
    final label = await _askLabel();
    if (label == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final begin = await ApiClient.instance.dio.post('/passkeys/register/begin');
      final options = Map<String, dynamic>.from(begin.data as Map);
      final created = await Passkeys.register(options);
      await ApiClient.instance.dio.post(
        '/passkeys/register/complete',
        data: {...created, 'label': label},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سُجِّل المفتاح')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askLabel() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اسم الجهاز'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'حاسوب المكتب، هاتفي…'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('تراجع')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('تابع'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null) return null;
    return label.trim().isEmpty ? 'هذا الجهاز' : label.trim();
  }

  Future<void> _remove(Map<String, dynamic> key) async {
    // تأكيدٌ قبل الحذف: من حذف مفتاحه الوحيد وهو على جهازٍ بلا كلمة مرورٍ
    // محفوظة يجدها لازمة عند أوّل قفل.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المفتاح'),
        content: Text('لن يفتح «${key['label']}» الشاشةَ بعد الآن. تُعاد إضافته من الجهاز نفسه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('احذف')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.delete('/passkeys/${key['id']}');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    if (error is PasskeyException) return error.message;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
    }
    return 'تعذّرت العملية';
  }
}
