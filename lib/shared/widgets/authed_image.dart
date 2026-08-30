import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';

/// صورة تُجلب بتوكن الدخول.
///
/// `Image.network` لا يمرّ بمعترضات Dio ولا يحمل ترويسة Authorization —
/// وسم `<img>` في المتصفح لا يحمل ترويسات مخصّصة أصلاً. فكل صورة تُخدَم من
/// نقطة محمية كانت تفشل بـ401 وتظهر أيقونة مكسورة، بينما رفعها نجح فعلاً.
///
/// والبديل — جعل نقطة الملفات عامّة — مرفوض: نفس النقطة تخدم صور فواتير
/// الموردين، وهي تكشف أسعار الشراء لمن يعرف الرابط أو يخمّنه.
///
/// الجلب هنا عبر Dio نفسه، فيمرّ بالتوكن وبكل ما يمرّ به أي طلب آخر،
/// والبايتات تُعرض بـ [Image.memory].
class AuthedImage extends StatefulWidget {
  const AuthedImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.errorWidget,
  });

  /// مسار نسبي كما يعيده السيرفر: `/api/files/{id}`.
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? errorWidget;

  // ذاكرة على مستوى الصنف: الشعار يُعرض في الشريط الجانبي في كل شاشة،
  // وبلا تخزين يُطلب من السيرفر مع كل إعادة بناء للواجهة.
  static final Map<String, Uint8List> _cache = {};

  /// تُستدعى بعد استبدال الشعار أو حذفه — وإلا بقيت الصورة القديمة معروضة
  /// من الذاكرة رغم نجاح الرفع.
  static void evict(String path) => _cache.remove(path);
  static void evictAll() => _cache.clear();

  @override
  State<AuthedImage> createState() => _AuthedImageState();
}

class _AuthedImageState extends State<AuthedImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuthedImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final cached = AuthedImage._cache[widget.path];
    if (cached != null) {
      setState(() {
        _bytes = cached;
        _failed = false;
      });
      return;
    }
    try {
      // baseUrl ينتهي بـ /api والمسار يبدأ به، فيُزال أحدهما.
      final relative = widget.path.startsWith('/api')
          ? widget.path.substring(4)
          : widget.path;
      final response = await ApiClient.instance.dio.get<List<int>>(
        relative,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = Uint8List.fromList(response.data ?? const []);
      AuthedImage._cache[widget.path] = data;
      if (!mounted) return;
      setState(() {
        _bytes = data;
        _failed = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorWidget ??
          SizedBox(
            width: widget.width,
            height: widget.height,
            child: const Icon(Icons.broken_image_outlined, size: 20),
          );
    }
    if (_bytes == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return Image.memory(
      _bytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
