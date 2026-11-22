import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/features/assistant_ui/presentation/screens/main_shell_screen.dart';
import 'package:matrix_ai_os/features/device_ingestion/background/background_sync_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize periodic lightweight background sync (battery-not-low constraint)
  await BackgroundSyncWorker.initialize();
  await BackgroundSyncWorker.schedulePeriodicSync();

  runApp(
    const ProviderScope(
      child: MatrixAiOsApp(),
    ),
  );
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
