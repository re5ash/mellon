import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/backend/backend_provider.dart';
import 'core/config/app_config.dart';
import 'core/startup/deferred_emoji_font.dart';
import 'design_system/app_theme.dart';
import 'design_system/deferred_fonts.dart';
import 'design_system/theme_controller.dart';
import 'design_system/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  scheduleMellonEmojiFont();
  try {
    final config = AppConfig.fromEnvironment();
    config.validate(release: kReleaseMode);
    final preferences = SharedPreferencesAsync();
    final appearance = await loadAppearance(preferences);
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.publishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    scheduleEmojiFontLoading();
    runApp(
      ProviderScope(
        overrides: [
          configProvider.overrideWithValue(config),
          initialAppearanceProvider.overrideWithValue(appearance),
          preferencesProvider.overrideWithValue(preferences),
        ],
        child: const MoyPrihodApp(),
      ),
    );
  } on Object catch (error) {
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Не удалось запустить приложение'),
                      const SizedBox(height: AppSpace.md),
                      Text(
                        kReleaseMode
                            ? 'Проверьте соединение и откройте приложение снова.'
                            : error is FormatException
                            ? error.message.toString()
                            : 'Ошибка подключения. Проверьте конфигурацию и доступность Supabase.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
