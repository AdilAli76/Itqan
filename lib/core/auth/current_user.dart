import 'dart:convert';
import '../network/api_client.dart';

/// فك ترميز حمولة (Payload) توكن JWT محلياً — بدون أي مكتبة إضافية، فقط
/// لقراءة الحقول المخزَّنة فيه أصلاً (organization_id, role, branch_id)،
/// نفس القيم التي يقرأها TenantContextMiddleware من نفس التوكن على الباك إند.
Future<Map<String, dynamic>?> readJwtClaims() async {
  final token = await ApiClient.instance.readToken();
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  return _decodeJwtSegment(parts[1]);
}

/// null يعني مدير عام (بلا فرع محدَّد) — راجع نفس المنطق في AuthController.Login.
Future<String?> readCurrentBranchId() async {
  final claims = await readJwtClaims();
  return claims?['branch_id'] as String?;
}

Map<String, dynamic> _decodeJwtSegment(String segment) {
  var normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
  switch (normalized.length % 4) {
    case 2:
      normalized += '==';
      break;
    case 3:
      normalized += '=';
      break;
  }
  final decoded = utf8.decode(base64.decode(normalized));
  return json.decode(decoded) as Map<String, dynamic>;
}

/// اسم المستخدم الحالي كما في التوكن — يُطبع تحت خانة «أصدره» في أوامر
/// الشراء. توقيع بلا اسم مقروء لا يدلّ على أحد بعد شهور.
Future<String?> readCurrentUserName() async {
  final claims = await readJwtClaims();
  return claims?['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'] as String? ??
      claims?['name'] as String? ??
      claims?['unique_name'] as String?;
}
