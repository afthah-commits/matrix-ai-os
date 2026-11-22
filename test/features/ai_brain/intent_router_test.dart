import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';

void main() {
  late IntentRouterService router;

  setUp(() {
    router = IntentRouterService();
  });

  group('IntentRouterService Tests', () {
    test('Correctly classifies personal memory queries', () {
      expect(
        router.classify('How much did I spend yesterday?'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('Who called me today?'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('Show my screen time and top apps'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('What is my passport number?'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('Find receipt from Starbucks'),
        equals(UserIntent.personalMemory),
      );
    });

    test('Correctly classifies live web / world queries', () {
      expect(
        router.classify('Who won today\'s Champions League match?'),
        equals(UserIntent.liveWebWorld),
      );
      expect(
        router.classify('Latest tech news and AI advancements'),
        equals(UserIntent.liveWebWorld),
      );
      expect(
        router.classify('What is quantum computing?'),
        equals(UserIntent.liveWebWorld),
      );
      expect(
        router.classify('Current price of Bitcoin'),
        equals(UserIntent.liveWebWorld),
      );
    });

    test('Correctly classifies hybrid queries linking personal context with live web', () {
      expect(
        router.classify('I bought shoes from Nike, what is their return policy online?'),
        equals(UserIntent.hybrid),
      );
      expect(
        router.classify('Compare my screen time with average daily smartphone usage'),
        equals(UserIntent.hybrid),
      );
      expect(
        router.classify('I have a flight ticket to Paris, what is the weather there right now?'),
        equals(UserIntent.hybrid),
      );
    });
  });
}
