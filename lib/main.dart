import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/services/file_storage_service.dart';
import 'data/local/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'shared/widgets/startup_error.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Inter', 'Lora', 'Oswald'],
      'These fonts are licensed under the SIL Open Font License, Version 1.1 (https://openfontlicense.org).',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Roboto Mono'],
      'Roboto Mono is licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Map data'],
      'Map tiles and geocoding data © OpenStreetMap contributors, available under the Open Database License (ODbL).',
    );
  });

  try {
    await initializeDateFormatting();
    final results = await Future.wait([
      AppDatabase.open(),
      FileStorageService.init(),
      SharedPreferences.getInstance(),
    ]);
    runApp(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(results[0] as AppDatabase),
        storageProvider.overrideWithValue(results[1] as FileStorageService),
        settingsRepositoryProvider.overrideWithValue(SettingsRepository(results[2] as SharedPreferences)),
      ],
      child: const GpsCameraApp(),
    ));
  } catch (e) {
    runApp(StartupErrorApp(error: e));
  }
}
