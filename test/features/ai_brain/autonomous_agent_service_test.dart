import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/core/database/local_database_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/autonomous_agent_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';

// Fake KnowledgeGraphService for testing AutonomousAgent queries
class FakeKnowledgeGraphService extends Fake implements KnowledgeGraphService {
  @override
  Future<KnowledgeQueryResult> queryRelatedMemories(String query, {int limit = 5}) async {
    final lower = query.toLowerCase();
    if (lower.contains('passport')) {
      return KnowledgeQueryResult(
        query: query,
        edges: const [],
        memories: [
          DecryptedMemoryNode(
            id: 1,
            category: 'ocr_doc',
            content: 'REPUBLIC OF INDIA PASSPORT A1234567 DOE JOHN',
            metadataJson: '{"docCategory": "Passport", "idNumber": "A1234567"}',
            timestamp: DateTime.now(),
            isPinned: true,
          ),
        ],
        relevanceScore: 1.0,
      );
    }
    return KnowledgeQueryResult(
      query: query,
      edges: const [],
      memories: const [],
      relevanceScore: 0.0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ActionDispatcherService actionDispatcher;
  late KnowledgeGraphService knowledgeGraphService;
  late AutonomousAgentService agentService;
  final List<MethodCall> nativeCalls = [];

  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      (MethodCall call) async {
        nativeCalls.add(call);
        switch (call.method) {
          case 'launchAppByName':
            final name = (call.arguments as Map)['name']?.toString().toLowerCase();
            if (name == 'whatsapp') {
              return {
                'success': true,
                'appName': 'WhatsApp',
                'packageName': 'com.whatsapp',
              };
            } else if (name == 'camera') {
              return {
                'success': true,
                'appName': 'Camera',
                'packageName': 'com.nothing.camera',
              };
            } else if (name == 'settings') {
              return {
                'success': true,
                'appName': 'Settings',
                'packageName': 'com.android.settings',
              };
            } else {
              return {
                'success': false,
                'error': 'App not found on device',
              };
            }

          case 'dialNumber':
            return true;

          case 'composeWhatsAppMessage':
            return true;

          case 'getCurrentScreenContext':
            return {
              'packageName': 'com.android.settings',
              'windowTitle': 'Settings',
              'screenText': 'Network, Connected devices, Battery',
              'isAccessibilityEnabled': true,
            };

          case 'performGlobalAction':
            return true;

          default:
            return null;
        }
      },
    );

    actionDispatcher = ActionDispatcherService();
    knowledgeGraphService = FakeKnowledgeGraphService();
    agentService = AutonomousAgentService(
      actionDispatcher: actionDispatcher,
      knowledgeGraphService: knowledgeGraphService,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(ActionDispatcherService.channelName),
      null,
    );
  });

  group('AutonomousAgentService Intent Parsing Tests', () {
    test('Parses natural language app launch commands accurately', () {
      final call1 = agentService.parseToolCall('open whatsapp');
      expect(call1, isNotNull);
      expect(call1!.toolName, equals('LAUNCH_APP'));
      expect(call1.arguments['name'], equals('whatsapp'));
      expect(call1.isSensitive, isFalse);

      final call2 = agentService.parseToolCall('launch camera');
      expect(call2, isNotNull);
      expect(call2!.toolName, equals('LAUNCH_APP'));
      expect(call2.arguments['name'], equals('camera'));

      final call3 = agentService.parseToolCall('please open settings');
      expect(call3, isNotNull);
      expect(call3!.toolName, equals('LAUNCH_APP'));
      expect(call3.arguments['name'], equals('settings'));

      final call4 = agentService.parseToolCall('can you start youtube');
      expect(call4, isNotNull);
      expect(call4!.toolName, equals('LAUNCH_APP'));
      expect(call4.arguments['name'], equals('youtube'));
    });

    test('Parses UI automation commands', () {
      final read = agentService.parseToolCall('read my screen');
      expect(read, isNotNull);
      expect(read!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(read.arguments['action'], equals('read_screen'));

      final back = agentService.parseToolCall('go back');
      expect(back, isNotNull);
      expect(back!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(back.arguments['action'], equals('back'));

      final home = agentService.parseToolCall('go home');
      expect(home, isNotNull);
      expect(home!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(home.arguments['action'], equals('home'));
    });

    test('Parses sensitive communication actions requiring confirmation gates', () {
      final call = agentService.parseToolCall('call +91 98765 43210');
      expect(call, isNotNull);
      expect(call!.toolName, equals('MAKE_CALL'));
      expect(call.arguments['phoneNumber'], equals('+91 98765 43210'));
      expect(call.isSensitive, isTrue);

      final wa = agentService.parseToolCall('whatsapp +91 98765 43210: Hey there');
      expect(wa, isNotNull);
      expect(wa!.toolName, equals('SEND_WHATSAPP'));
      expect(wa.arguments['phoneNumber'], equals('+91 98765 43210'));
      expect(wa.arguments['message'], equals('Hey there'));
      expect(wa.isSensitive, isTrue);
    });

    test('Parses OCR document search queries', () {
      final passport = agentService.parseToolCall('where is my passport?');
      expect(passport, isNotNull);
      expect(passport!.toolName, equals('SEARCH_FILES_AND_OCR'));

      final invoice = agentService.parseToolCall('find tax invoice');
      expect(invoice, isNotNull);
      expect(invoice!.toolName, equals('SEARCH_FILES_AND_OCR'));
    });

    test('Parses structured tool call from Cloud LLM JSON responses', () {
      const llmJson = '''
      {
        "thought": "The user wants to open the camera to take a photo",
        "tool_call": {
          "name": "LAUNCH_APP",
          "arguments": {"name": "camera"}
        },
        "response": "Launching camera app for you."
      }
      ''';

      final toolCall = agentService.parseToolCallFromJson(llmJson);
      expect(toolCall, isNotNull);
      expect(toolCall!.toolName, equals('LAUNCH_APP'));
      expect(toolCall.arguments['name'], equals('camera'));
      expect(toolCall.isSensitive, isFalse);
    });
  });

  group('AutonomousAgentService ReAct Execution Loop Tests', () {
    test('Executes safe LAUNCH_APP immediately and generates execution traces', () async {
      final result = await agentService.executeAgentLoop('open whatsapp');
      expect(result.hasAction, isTrue);
      expect(result.pendingConfirmation, isNull);
      expect(result.finalResponse, contains('Successfully launched **WhatsApp**'));
      expect(result.actionBadge, equals('App Launcher'));

      // Verify execution steps
      expect(result.steps.length, greaterThanOrEqualTo(2));
      expect(result.steps.any((s) => s.stepName.contains('Querying Android PackageManager')), isTrue);
      expect(result.steps.any((s) => s.stepName.contains('Launched WhatsApp') && s.status == 'success'), isTrue);

      // Verify native method was called
      expect(nativeCalls.any((c) => c.method == 'launchAppByName'), isTrue);
    });

    test('Handles non-existent app gracefully with error trace', () async {
      final result = await agentService.executeAgentLoop('open non_existent_game_xyz');
      expect(result.hasAction, isTrue);
      expect(result.pendingConfirmation, isNull);
      expect(result.finalResponse, contains('could not find an installed app'));
      expect(result.steps.any((s) => s.status == 'failed'), isTrue);
    });

    test('Enforces Human-in-the-Loop Confirmation Gate for sensitive MAKE_CALL', () async {
      final result = await agentService.executeAgentLoop('call +91 98765 43210');
      expect(result.hasAction, isTrue);
      expect(result.pendingConfirmation, isNotNull);
      expect(result.pendingConfirmation!.action.type, equals(ActionType.callContact));
      expect(result.actionBadge, equals('Safety Gate'));
      expect(result.steps.any((s) => s.status == 'pending_approval'), isTrue);

      // Ensure dialer was NOT auto-invoked
      expect(nativeCalls.any((c) => c.method == 'dialNumber'), isFalse);
    });

    test('Executes SEARCH_FILES_AND_OCR and retrieves local passport document', () async {
      final result = await agentService.executeAgentLoop('where is my passport?');
      expect(result.hasAction, isTrue);
      expect(result.finalResponse, contains('PASSPORT A1234567'));
      expect(result.actionBadge, equals('Vision OCR'));
      expect(result.steps.any((s) => s.status == 'success'), isTrue);
    });

    test('Executes UI_AUTOMATION_STEP to read screen via Accessibility', () async {
      final result = await agentService.executeAgentLoop('read my screen');
      expect(result.hasAction, isTrue);
      expect(result.finalResponse, contains('Foreground Screen Content'));
      expect(result.finalResponse, contains('Network, Connected devices, Battery'));
      expect(result.actionBadge, equals('Screen Reader'));
      expect(nativeCalls.any((c) => c.method == 'getCurrentScreenContext'), isTrue);
    });
  });
}
