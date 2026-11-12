import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_settings.dart';
import '../features/location/services/location_controller.dart';
import '../features/photo_editor/services/photo_service.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class GpsCameraApp extends ConsumerStatefulWidget {
  const GpsCameraApp({super.key});

  @override
  ConsumerState<GpsCameraApp> createState() => _GpsCameraAppState();
}

class _GpsCameraAppState extends ConsumerState<GpsCameraApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Foreground-only location: pause GPS when the app is backgrounded.
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(locationControllerProvider.notifier).pause(),
      onShow: () => ref.read(locationControllerProvider.notifier).start(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolvePending());
  }

  /// Fills in addresses for photos captured offline, when online.
  Future<void> _resolvePending() async {
    try {
      await ref.read(photoServiceProvider).resolvePendingAddresses();
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isOnlineProvider, (prev, online) {
      if (online && prev == false) unawaited(_resolvePending());
    });
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return MaterialApp.router(
      title: 'GPS Camera',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: [
        for (final code in supportedLocaleCodes.keys)
          if (code != 'system') Locale(code),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
