import 'dart:io';
import 'dart:typed_data';

/// المجلّد المحفوظ يعمل على سطح المكتب وحده.
///
/// <para>أندرويد يُرجع من منتقي المجلّدات معرّف مستند (content://) لا مساراً
/// على القرص، و<c>File</c> لا تكتب فيه — فالحفظ هناك يبقى بنافذة النظام،
/// وهي تقبل «Drive» وجهةً مباشرة على أي حال.</para>
bool get supportsFolderSave => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// يكتب الملف في المجلّد ويُعيد مساره الكامل.
///
/// <para><b>ولا يكتب فوق ملفٍ قائم:</b> نسختان في الدقيقة نفسها ممكنتان
/// (تنزيلٌ ثانٍ بعد فشلٍ ظاهر)، والكتابة فوق الأولى تُتلف نسخةً سليمة
/// لتضع مكانها نسخةً لم يُتحقّق منها بعد. فيُضاف رقمٌ إلى الاسم.</para>
Future<String> writeBackupFile(String folder, String fileName, Uint8List bytes) async {
  final directory = Directory(folder);
  if (!await directory.exists()) {
    // المجلّد قد يكون قرصاً مفصولاً أو مجلّد مزامنة أُعيدت تسميته — ورسالةٌ
    // تقول ذلك خيرٌ من استثناء نظام ملفات لا يفهمه أحد.
    throw FileSystemException('المجلّد لم يعد موجوداً — اختر غيره', folder);
  }

  var target = File('$folder${Platform.pathSeparator}$fileName');
  var attempt = 1;
  while (await target.exists()) {
    final base = fileName.endsWith('.zip')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    target = File('$folder${Platform.pathSeparator}$base-$attempt.zip');
    attempt++;
  }

  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

/// آخر جزأين من المسار — المسار الكامل يفيض على عرض البطاقة، وآخره هو
/// ما يميّزه في نظر من اختاره.
String folderLabel(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  if (parts.length <= 2) return path;
  return '…${Platform.pathSeparator}${parts[parts.length - 2]}${Platform.pathSeparator}${parts.last}';
}
