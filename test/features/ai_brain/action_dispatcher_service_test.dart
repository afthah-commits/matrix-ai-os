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
          case 'launchAppByName':
            return {
              'success': true,
              'appName': 'YouTube',
              'packageName': 'com.google.android.youtube',
            };
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
          case 'clickUiElement':
            final target = (call.arguments as Map)['targetText']?.toString().toLowerCase() ?? '';
            if (target.contains('pay now')) {
              return {
                'success': false,
                'isFinancialBlocked': true,
                'message': 'Safety Block: Action matches critical financial/payment action.',
              };
            }
            return {
              'success': true,
              'message': 'Clicked on "$target"',
              'matchedText': target,
            };
          case 'typeUiText':
            final text = (call.arguments as Map)['text']?.toString() ?? '';
            return {
              'success': true,
              'message': 'Injected text: "$text"',
              'injectedText': text,
            };
          case 'scrollUi':
            final dir = (call.arguments as Map)['direction']?.toString() ?? 'down';
            return {
              'success': true,
              'direction': dir,
              'method': 'ACTION_SCROLL',
            };
          case 'inspectUiTree':
            return [
              {'text': 'Search', 'isClickable': true},
              {'text': 'Settings', 'isClickable': true},
            ];
          case 'openFileUri':
            return {
              'success': true,
              'message': 'Opened file',
            };
          case 'checkAllFilesAccess':
            return true;
          case 'requestAllFilesAccess':
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

    test('Parses Click UI intents correctly (safe)', () {
      final action = dispatcher.parseActionIntent('Click on Search');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.clickUi));
      expect(action.isSensitive, isFalse);
      expect(action.params['targetText'], equals('Search'));
    });

    test('Parses Click UI intents with dangerous financial keyword as sensitive', () {
      final action = dispatcher.parseActionIntent('Click on Pay Now');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.clickUi));
      expect(action.isSensitive, isTrue);
      expect(action.params['targetText'], equals('Pay Now'));
    });

    test('Parses Type Text intents correctly', () {
      final action = dispatcher.parseActionIntent('Type "Flutter AI" into Search');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.typeText));
      expect(action.isSensitive, isFalse);
      expect(action.params['text'], equals('Flutter AI'));
      expect(action.params['targetHint'], equals('Search'));
    });

    test('Parses Scroll Screen intents correctly', () {
      final action = dispatcher.parseActionIntent('Scroll down');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.scrollUi));
      expect(action.isSensitive, isFalse);
      expect(action.params['direction'], equals('down'));
    });

    test('Parses Inspect UI tree intents correctly', () {
      final action = dispatcher.parseActionIntent('inspect ui tree');
      expect(action, isNotNull);
      expect(action!.type, equals(ActionType.inspectUi));
      expect(action.isSensitive, isFalse);
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

    test('Sensitive action (Financial Click) yields PendingActionConfirmation', () async {
      final action = dispatcher.parseActionIntent('Click on Pay Now')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<PendingActionConfirmation>());
      final pending = result as PendingActionConfirmation;
      expect(pending.action.type, equals(ActionType.clickUi));
      expect(pending.promptMessage, contains('Confirm Action: Click on "Pay Now"'));
      expect(methodCalls.where((c) => c.method == 'clickUiElement'), isEmpty);
    });

    test('Safe Click UI executes directly and invokes native channel', () async {
      final action = dispatcher.parseActionIntent('Click on Search')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<ActionResult>());
      final actionResult = result as ActionResult;
      expect(actionResult.success, isTrue);
      expect(actionResult.message, contains('Clicked on "search"'));
      expect(methodCalls.any((c) => c.method == 'clickUiElement'), isTrue);
    });

    test('Safe Type Text executes directly and invokes native channel', () async {
      final action = dispatcher.parseActionIntent('Type "Flutter" into Search')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<ActionResult>());
      final actionResult = result as ActionResult;
      expect(actionResult.success, isTrue);
      expect(actionResult.message, contains('Flutter'));
      expect(methodCalls.any((c) => c.method == 'typeUiText'), isTrue);
    });

    test('Safe Scroll UI executes directly and invokes native channel', () async {
      final action = dispatcher.parseActionIntent('Scroll down')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<ActionResult>());
      final actionResult = result as ActionResult;
      expect(actionResult.success, isTrue);
      expect(actionResult.message, contains('Scrolled screen down'));
      expect(methodCalls.any((c) => c.method == 'scrollUi'), isTrue);
    });

    test('Safe Inspect UI executes directly and returns tree elements', () async {
      final action = dispatcher.parseActionIntent('inspect ui tree')!;
      final result = await dispatcher.processAction(action);

      expect(result, isA<ActionResult>());
      final actionResult = result as ActionResult;
      expect(actionResult.success, isTrue);
      expect(actionResult.data, isA<List>());
      expect((actionResult.data as List).length, equals(2));
      expect(methodCalls.any((c) => c.method == 'inspectUiTree'), isTrue);
    });

    test('Executes openFile directly and opens file URI in native viewer', () async {
      const phoneAction = PhoneAction(
        id: 'act_file_1',
        type: ActionType.openFile,
        params: {'uri': 'content://media/external/files/1001', 'mimeType': 'application/pdf'},
        description: 'Open file Air_India_Ticket.pdf',
        isSensitive: false,
      );

      final result = await dispatcher.executeConfirmedAction(phoneAction);
      expect(result.success, isTrue);
      expect(result.message, contains('Opened file'));
      expect(methodCalls.any((c) => c.method == 'openFileUri'), isTrue);
    });

    test('Checks accessibility service status and queries settings', () async {
      final isEnabled = await dispatcher.checkAccessibilityEnabled();
      expect(isEnabled, isTrue);
      expect(methodCalls.any((c) => c.method == 'checkAccessibilityEnabled'), isTrue);
    });

    test('Checks all files access status and opens settings', () async {
      final isGranted = await dispatcher.checkAllFilesAccess();
      expect(isGranted, isTrue);
      expect(methodCalls.any((c) => c.method == 'checkAllFilesAccess'), isTrue);

      await dispatcher.openAllFilesSettings();
      expect(methodCalls.any((c) => c.method == 'requestAllFilesAccess'), isTrue);
    });
  });
}
