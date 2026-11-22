import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/autonomous_agent_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/byok_key_manager.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/intent_router_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';

class MockSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _mockData = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _mockData[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _mockData[key] = value;
    } else {
      _mockData.remove(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _mockData.remove(key);
  }
}

class FakeKnowledgeGraphService extends Fake implements KnowledgeGraphService {
  @override
  Future<KnowledgeQueryResult> queryRelatedMemories(String query, {int limit = 5}) async {
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

  group('Malayalam App Mapping & Parsing Tests', () {
    test('mapMalayalamAppNameToEnglish correctly maps Malayalam names', () {
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('യൂട്യൂബ്'), equals('YouTube'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('വാട്സാപ്പ്'), equals('WhatsApp'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('വാട്സാപ്'), equals('WhatsApp'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('ക്യാമറ'), equals('Camera'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('സെറ്റിംഗ്സ്'), equals('Settings'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('ക്രോം'), equals('Chrome'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('ഇൻസ്റ്റാഗ്രാം'), equals('Instagram'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('ഗാലറി'), equals('Gallery'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('ഫോൺ'), equals('Phone'));
      expect(AutonomousAgentService.mapMalayalamAppNameToEnglish('UnknownApp'), equals('UnknownApp'));
    });

    late AutonomousAgentService agent;

    setUp(() {
      agent = AutonomousAgentService(
        actionDispatcher: ActionDispatcherService(),
        knowledgeGraphService: FakeKnowledgeGraphService(),
      );
    });

    test('Parses Malayalam app launch commands', () {
      final yt = agent.parseToolCall('യൂട്യൂബ് തുറക്കൂ');
      expect(yt, isNotNull);
      expect(yt!.toolName, equals(AgentToolType.launchApp.code));
      expect(yt.arguments['name'], equals('YouTube'));

      final cam = agent.parseToolCall('ക്യാമറ തുറക്കൂ');
      expect(cam, isNotNull);
      expect(cam!.toolName, equals(AgentToolType.launchApp.code));
      expect(cam.arguments['name'], equals('Camera'));

      final settings = agent.parseToolCall('സെറ്റിംഗ്സ് ഓപ്പൺ ചെയ്യൂ');
      expect(settings, isNotNull);
      expect(settings!.toolName, equals(AgentToolType.launchApp.code));
      expect(settings.arguments['name'], equals('Settings'));

      final wa = agent.parseToolCall('വാട്സാപ്പ് തുറക്കുക');
      expect(wa, isNotNull);
      expect(wa!.toolName, equals(AgentToolType.launchApp.code));
      expect(wa.arguments['name'], equals('WhatsApp'));
    });

    test('Parses Malayalam screen reading and navigation commands', () {
      final read = agent.parseToolCall('സ്ക്രീൻ വായിക്കൂ');
      expect(read, isNotNull);
      expect(read!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(read.arguments['action'], equals('read_screen'));

      final back = agent.parseToolCall('ബാക്ക്');
      expect(back, isNotNull);
      expect(back!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(back.arguments['action'], equals('back'));

      final home = agent.parseToolCall('ഹോം');
      expect(home, isNotNull);
      expect(home!.toolName, equals('UI_AUTOMATION_STEP'));
      expect(home.arguments['action'], equals('home'));

      final scrollDown = agent.parseToolCall('താഴേക്ക് സ്ക്രോൾ ചെയ്യൂ');
      expect(scrollDown, isNotNull);
      expect(scrollDown!.toolName, equals(AgentToolType.scrollScreen.code));
      expect(scrollDown.arguments['direction'], equals('down'));

      final scrollUp = agent.parseToolCall('മുകളിലേക്ക് സ്ക്രോൾ ചെയ്യൂ');
      expect(scrollUp, isNotNull);
      expect(scrollUp!.toolName, equals(AgentToolType.scrollScreen.code));
      expect(scrollUp.arguments['direction'], equals('up'));
    });

    test('Parses WhatsApp message commands with contact names (English & Malayalam)', () {
      // English: "Send Hi to Rahulan on WhatsApp"
      final call1 = agent.parseToolCall('Send Hi to Rahulan on WhatsApp');
      expect(call1, isNotNull);
      expect(call1!.toolName, equals(AgentToolType.sendWhatsApp.code));
      expect(call1.arguments['phoneNumber'], equals('Rahulan'));
      expect(call1.arguments['message'], equals('Hi'));
      expect(call1.isSensitive, isTrue);

      // English with quote/saying: "Send message to Mom on WhatsApp: I will be late"
      final call2 = agent.parseToolCall('send whatsapp to Mom: I will be late');
      expect(call2, isNotNull);
      expect(call2!.toolName, equals(AgentToolType.sendWhatsApp.code));
      expect(call2.arguments['phoneNumber'], equals('Mom'));
      expect(call2.arguments['message'], equals('I will be late'));
      expect(call2.isSensitive, isTrue);

      // Malayalam: "രാഹുലിന് വാട്സാപ്പിൽ ഹായ് അയക്കൂ"
      final call3 = agent.parseToolCall('രാഹുലിന് വാട്സാപ്പിൽ ഹായ് അയക്കൂ');
      expect(call3, isNotNull);
      expect(call3!.toolName, equals(AgentToolType.sendWhatsApp.code));
      expect(call3.arguments['phoneNumber'], equals('രാഹുൽ'));
      expect(call3.arguments['message'], equals('ഹായ്'));
      expect(call3.isSensitive, isTrue);

      // Malayalam variant: "വാട്സാപ്പിൽ അച്ഛന് സുഖമാണോ അയക്കൂ"
      final call4 = agent.parseToolCall('വാട്സാപ്പിൽ അച്ഛന് സുഖമാണോ അയക്കൂ');
      expect(call4, isNotNull);
      expect(call4!.toolName, equals(AgentToolType.sendWhatsApp.code));
      expect(call4.arguments['phoneNumber'], equals('അച്ഛൻ'));
      expect(call4.arguments['message'], equals('സുഖമാണോ'));
      expect(call4.isSensitive, isTrue);
    });

    test('Parses Malayalam phone call commands', () {
      final callMother = agent.parseToolCall('അമ്മയെ വിളിക്കൂ');
      expect(callMother, isNotNull);
      expect(callMother!.toolName, equals(AgentToolType.makeCall.code));
      expect(callMother.arguments['phoneNumber'], equals('അമ്മ'));
      expect(callMother.isSensitive, isTrue);

      final callDoc = agent.parseToolCall('ഡോക്ടറെ കോൾ ചെയ്യൂ');
      expect(callDoc, isNotNull);
      expect(callDoc!.toolName, equals(AgentToolType.makeCall.code));
      expect(callDoc.arguments['phoneNumber'], equals('ഡോക്ടർ'));
      expect(callDoc.isSensitive, isTrue);
    });

    test('Parses Malayalam document search commands', () {
      final passport = agent.parseToolCall('എന്റെ പാസ്പോർട്ട് കാണിക്കൂ');
      expect(passport, isNotNull);
      expect(passport!.toolName, equals(AgentToolType.searchFilesAndOcr.code));

      final ticket = agent.parseToolCall('ടിക്കറ്റ് കാണിക്കൂ');
      expect(ticket, isNotNull);
      expect(ticket!.toolName, equals(AgentToolType.searchFilesAndOcr.code));

      final docs = agent.parseToolCall('എന്റെ രേഖകൾ തിരയുക');
      expect(docs, isNotNull);
      expect(docs!.toolName, equals(AgentToolType.searchFilesAndOcr.code));
    });
  });

  group('IntentRouterService Malayalam Classification Tests', () {
    late IntentRouterService router;

    setUp(() {
      router = IntentRouterService();
    });

    test('Correctly classifies Malayalam personal memory queries', () {
      expect(
        router.classify('എന്റെ പാസ്പോർട്ട് നമ്പർ എന്താണ്?'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('എന്റെ സ്ക്രീൻ സമയം എത്രയാണ്?'),
        equals(UserIntent.personalMemory),
      );
      expect(
        router.classify('എന്റെ ഫ്ലൈറ്റ് ടിക്കറ്റ് കാണിക്കൂ'),
        equals(UserIntent.personalMemory),
      );
    });

    test('Correctly classifies Malayalam world/live queries', () {
      expect(
        router.classify('ആരാണ് ഇന്നത്തെ മത്സരം ജയിച്ചത്?'),
        equals(UserIntent.liveWebWorld),
      );
      expect(
        router.classify('ഇന്നത്തെ വാർത്തകൾ എന്തൊക്കെയാണ്?'),
        equals(UserIntent.liveWebWorld),
      );
    });
  });

  group('ByokKeyManager Language Preference Tests', () {
    late MockSecureStorage mockStorage;
    late ByokKeyManager keyManager;

    setUp(() {
      mockStorage = MockSecureStorage();
      keyManager = ByokKeyManager(storage: mockStorage);
    });

    test('Language preference defaults to English and updates to Malayalam', () async {
      expect(await keyManager.getLanguagePreference(), equals('en'));

      await keyManager.setLanguagePreference('ml');
      expect(await keyManager.getLanguagePreference(), equals('ml'));

      await keyManager.setLanguagePreference('en');
      expect(await keyManager.getLanguagePreference(), equals('en'));
    });
  });
}
