import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix_ai_os/core/constants/app_constants.dart';
import 'package:matrix_ai_os/main.dart';

void main() {
  testWidgets('Matrix AI OS App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MatrixAiOsApp(),
      ),
    );

    // Verify title and system constants
    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text('Privacy-First Local AI Core'), findsOneWidget);
  });
}
