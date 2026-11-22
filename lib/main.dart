import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/core/security/encryption_key_manager.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/main_shell_screen.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/services/wake_word_bridge_service.dart';
import 'package:matrix_ai_os/features/device_ingestion/background/background_sync_worker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Render the Flutter UI IMMEDIATELY (<150ms budget) so the app NEVER hangs on splash/loading
  runApp(
    const ProviderScope(
      child: MatrixAiOsApp(),
    ),
  );

  // Defer ALL background engine initializations until 800ms AFTER the first frame renders
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 800), () {
      _initializeCoreEngines();
    });
  });
}

Future<void> _initializeCoreEngines() async {
  // 1. Initialize Keystore & ObjectBox NoSQL Storage with timeout
  try {
    final keyManager = EncryptionKeyManager();
    await keyManager.getOrCreateMasterKey().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () {
        debugPrint('[Startup] Keystore key resolution timed out.');
        return Uint8List(32);
      },
    );

    final dbService = LocalDatabaseService();
    await dbService.initialize().timeout(
      const Duration(milliseconds: 2500),
      onTimeout: () {
        debugPrint('[Startup] ObjectBox init timed out; continuing.');
      },
    );
  } catch (e) {
    debugPrint('[Startup] ObjectBox/Keystore startup error: $e');
  }

  // 2. Initialize Workmanager & Background Sync with timeout
  try {
    await BackgroundSyncWorker.initialize().timeout(
      const Duration(milliseconds: 2000),
      onTimeout: () {
        debugPrint('[Startup] BackgroundSyncWorker init timed out.');
      },
    );
    await BackgroundSyncWorker.schedulePeriodicSync().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () {
        debugPrint('[Startup] BackgroundSyncWorker schedule timed out.');
      },
    );
  } catch (e) {
    debugPrint('[Startup] BackgroundSyncWorker startup error: $e');
  }

  // 3. Initialize Wake-Word Bridge / Native Service with timeout
  try {
    final wakeBridge = WakeWordBridgeService();
    await wakeBridge.init().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () {
        debugPrint('[Startup] WakeWordBridgeService init timed out.');
      },
    );
  } catch (e) {
    debugPrint('[Startup] WakeWordBridgeService startup error: $e');
  }
}

class MatrixAiOsApp extends StatelessWidget {
  const MatrixAiOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF111827),
          error: Color(0xFFEF4444),
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
      ),
      home: const MainShellScreen(),
    );
  }
}
