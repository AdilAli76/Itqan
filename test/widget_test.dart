import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic_enterprise/core/theme/branding_provider.dart';
import 'package:kinetic_enterprise/main.dart';

void main() {
  testWidgets('التطبيق يبني أول إطار دون استثناء', (WidgetTester tester) async {
    // brandingProvider يستدعي الـ Backend؛ نُثبّته على الهوية الافتراضية
    // حتى لا يعتمد الاختبار على سيرفر قائم.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          brandingProvider.overrideWith((ref) async => OrganizationBranding.fallback),
        ],
        child: const KineticApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
