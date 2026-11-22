import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ActionDispatcherService dispatcher;
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'dialNumber':
            return true;
          case 'composeWhatsAppMessage':
            return true;
          case 'launchApp':
            return true;
          case 'getCurrentScreenContext':
            return {
              'packageName': 'com.android.settings',
              'windowTitle': 'Settings',
              'screenText': 'Wi-Fi, Bluetooth, Apps, Battery',
              'isAccessibilityEnabled': true,
            };
          case 'performGlobalAction':
            return true;
          case 'checkAccessibilityEnabled':
            return true;
          default:
            return null;
        }
      },
    );

    dispatcher = ActionDispatcherService();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      null,
    );
  });

  group('ActionDispatcherService Intent Parsing Tests', () {
    test('Parses Call Contact intents correctly', () {
      final action = dispatcher.parseActionIntent('Call +91 98765 43210');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.callContact));
      expect(action.isSensitive, isTrue);
      expect(action.params['phoneNumber'], equals('+91 98765 43210'));
    });

    test('Parses Send WhatsApp intents correctly', () {
      final action = dispatcher.parseActionIntent('Send WhatsApp to 9876543210 saying Meeting at 4pm');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.sendWhatsApp));
      expect(action.isSensitive, isTrue);
      expect(action.params['phoneNumber'], equals('9876543210'));
      expect(action.params['message'], equals('Meeting at 4pm'));
    });

    test('Parses Open App intents correctly', () {
      final action = dispatcher.parseActionIntent('Open YouTube');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.openApp));
      expect(action.isSensitive, isFalse);
      expect(action.params['packageName'], equals('com.google.android.youtube'));
    });

    test('Parses Read Screen intents correctly', () {
      final action = dispatcher.parseActionIntent('What is on my screen?');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.readScreen));
      expect(action.isSensitive, isFalse);
    });

    test('Parses Navigation intents correctly', () {
      final action = dispatcher.parseActionIntent('go back');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.globalNav));
      expect(action.params['action'], equals('back'));
    });

    test('Returns null for generic conversational queries without action commands', () {
      final action = dispatcher.parseActionIntent('How much did I spend yesterday?');
      expect(action, isNull);
    });
  });

  group('Safety Confirmation Gate Tests', () {
    test('Sensitive action (Call) yields PendingActionConfirmation without auto-executing', () async {
      final action = dispatcher.parseActionIntent('Call +91 98765 43210')!;
      final result = await dispatcher.processAction(action);

      // Must be a PendingActionConfirmation requiring explicit user approval
      expect(result, isA<PendingActionConfirmation>());
      final pending = result as PendingActionConfirmation;
      expect(pending.action.type, equals(ActionType.callContact));
      expect(pending.promptMessage, contains('Confirm Action: Dial phone number'));

      // MethodChannel must NOT have been called yet
      expect(methodCalls.where((c) => c.method == 'dialNumber'), isEmpty);

      // Once confirmed by user:
      final executed = await dispatcher.executeConfirmedAction(pending.action);
      expect(executed.success, isTrue);
      expect(methodCalls.any((c) => c.method == 'dialNumber'), isTrue);
    });

    test('Safe action (Read Screen) executes directly without confirmation gate', () async {
      final action = dispatcher.parseActionIntent('read my screen')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<ActionResult>());
      final actionResult = result as ActionResult;
      expect(actionResult.success, isTrue);
      expect(actionResult.data, contains('Wi-Fi, Bluetooth, Apps'));
      expect(methodCalls.any((c) => c.method == 'getCurrentScreenContext'), isTrue);
    });

    test('Checks accessibility service status and queries settings', () async {
      final isEnabled = await dispatcher.checkAccessibilityEnabled();
      expect(isEnabled, isTrue);
      expect(methodCalls.any((c) => c.method == 'checkAccessibilityEnabled'), isTrue);
    });
  });
}
