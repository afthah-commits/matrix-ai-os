import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/presentation/widgets/matrix_logo_widget.dart';

void main() {
  testWidgets('MatrixLogoWidget renders properly with default properties', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MatrixLogoWidget(size: 48),
          ),
        ),
      ),
    );

    expect(find.byType(MatrixLogoWidget), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('MatrixLogoWidget renders properly without background', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MatrixLogoWidget(
              size: 64,
              withBackground: false,
              withGlow: false,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MatrixLogoWidget), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MatrixLogoWidget),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
