import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/current_user.dart';
import 'api_client.dart';

/// بطاقةٌ في كشف الفرع المخزَّن محلياً.
class RosterCard {
  const RosterCard({
    required this.customerId,
    required this.fullName,
    required this.cardCode,
    required this.balance,
    required this.dailyCap,
    this.photoUrl,
  });

  final String customerId;
  final String fullName;
  final String cardCode;

  /// الرصيد لحظة آخر تحديث — **ينقص محلياً** مع كل سحبٍ غير مُزامَن.
  ///
  /// <para>وبلا إنقاصه كان سحبان متتاليان بلا اتصال يريان الرصيد الكامل
  /// كلاهما، فيخرج ضعف ما في البطاقة.</para>
  final double balance;

  final double dailyCap;
  final String? photoUrl;

  RosterCard copyWith({double? balance}) => RosterCard(
        customerId: customerId,
        fullName: fullName,
        cardCode: cardCode,
        balance: balance ?? this.balance,
        dailyCap: dailyCap,
        photoUrl: photoUrl,
      );

  factory RosterCard.fromJson(Map<String, dynamic> json) => RosterCard(
        customerId: '${json['customerId']}',
        fullName: '${json['fullName']}',
        cardCode: '${json['cardCode']}',
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        dailyCap: (json['dailyCap'] as num?)?.toDouble() ?? 0,
        photoUrl: json['photoUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'fullName': fullName,
        'cardCode': cardCode,
        'balance': balance,
        'dailyCap': dailyCap,
        'photoUrl': photoUrl,
      };
}

class RosterState {
  const RosterState({this.cards = const [], this.updatedAt, this.branchId});

  final List<RosterCard> cards;
  final DateTime? updatedAt;
  final String? branchId;

  RosterCard? byCode(String code) {
    final needle = code.trim().toUpperCase();
    for (final card in cards) {
      if (card.cardCode.toUpperCase() == needle) return card;
    }
    return null;
  }
}

/// كشف بطاقات الفرع المخزَّن على الجهاز — ليعمل السحب حين تنقطع الشبكة.
///
/// <para><b>الفجوة:</b> البيع النقدي يعمل بلا اتصال منذ زمن، أمّا السحب من
/// بطاقة فكان ممنوعاً لأن الجهاز لا يعرف الرصيد. فيقف المنتسب ومعه بطاقة
/// فيها رصيد ولا يستطيع الصرف — والشبكة تنقطع كثيراً.</para>
///
/// <para><b>وما يجعله آمناً أن البطاقة مربوطة بفرع</b>: الفرع يملك بياناتها
/// وحده، فالكاتب واحد لا اثنان ولا يُخصَم من بطاقةٍ في فرعين معاً.</para>
///
/// <para><b>⚠ والمفتاح يحمل معرّف المنظمة والفرع معاً.</b> مفتاحٌ عامّ كان
/// سيُظهر كشف منظمةٍ على جهازٍ يدخله موظّف منظمةٍ أخرى — وهو عين العطب الذي
/// وقع في طابور البيع دون اتصال وأُصلح.</para>
class BranchRosterNotifier extends StateNotifier<RosterState> {
  BranchRosterNotifier(this._storage) : super(const RosterState());

  final FlutterSecureStorage _storage;
  String? _organizationId;

  static String _keyFor(String? orgId, String? branchId) =>
      'branch_roster_${orgId ?? 'none'}_${branchId ?? 'none'}';

  /// يُحمّل الكشف المخزَّن لهذا الفرع — يُستدعى عند فتح نقطة البيع.
  Future<void> load(String branchId) async {
    try {
      final claims = await readJwtClaims();
      _organizationId = claims?['organization_id'] as String?;
      if (_organizationId == null) {
        state = const RosterState();
        return;
      }

      final raw = await _storage.read(key: _keyFor(_organizationId, branchId));
      if (raw == null || raw.isEmpty) {
        state = RosterState(branchId: branchId);
        return;
      }

      final decoded = json.decode(raw) as Map<String, dynamic>;
      state = RosterState(
        branchId: branchId,
        updatedAt: DateTime.tryParse('${decoded['updatedAt']}'),
        cards: (decoded['cards'] as List? ?? const [])
            .map((e) => RosterCard.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      // كشفٌ تالف لا يمنع إقلاع نقطة البيع — تبدأ بلا سحبٍ غير متّصل.
      state = RosterState(branchId: branchId);
    }
  }

  /// يجلب الكشف من الخادم ويحفظه — يُستدعى ما دامت الشبكة موصولة.
  ///
  /// <para>الفشل صامت: تحديثُ الكشف عملٌ خلفي، وإظهار خطئه للكاشير وهو
  /// يبيع ضجيجٌ لا يفعل به شيئاً. والكشف القديم يبقى صالحاً.</para>
  Future<bool> refresh(String branchId) async {
    try {
      final response = await ApiClient.instance.dio
          .get('/branch-roster', queryParameters: {'branchId': branchId});
      final data = Map<String, dynamic>.from(response.data as Map);
      final cards = (data['cards'] as List? ?? const [])
          .map((e) => RosterCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      state = RosterState(branchId: branchId, cards: cards, updatedAt: DateTime.now());
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يُنقص الرصيد المخزَّن بعد سحبٍ غير مُزامَن.
  ///
  /// <para>بلا هذا يرى سحبان متتاليان الرصيد الكامل كلاهما، فيخرج ضعف ما
  /// في البطاقة. والخادم هو الحكم عند المزامنة — لكن البضاعة تكون قد
  /// خرجت.</para>
  Future<void> debitLocally(String customerId, double amount) async {
    state = RosterState(
      branchId: state.branchId,
      updatedAt: state.updatedAt,
      cards: [
        for (final card in state.cards)
          card.customerId == customerId
              ? card.copyWith(balance: card.balance - amount)
              : card,
      ],
    );
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _storage.write(
        key: _keyFor(_organizationId, state.branchId),
        value: json.encode({
          'updatedAt': state.updatedAt?.toIso8601String(),
          'cards': state.cards.map((c) => c.toJson()).toList(),
        }),
      );
    } catch (_) {
      // فشل الكتابة يُبقي الكشف في الذاكرة لهذه الجلسة على الأقل.
    }
  }
}

final branchRosterProvider =
    StateNotifierProvider<BranchRosterNotifier, RosterState>((ref) {
  return BranchRosterNotifier(const FlutterSecureStorage());
});
