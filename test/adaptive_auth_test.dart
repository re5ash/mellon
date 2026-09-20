import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/presentation/auth_page.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('auth fits $size with keyboard and enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.8),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: const AuthPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Добро пожаловать'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
