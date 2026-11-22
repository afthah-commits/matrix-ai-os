import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';
import 'package:matrix_ai_os/features/ocr_vision/domain/services/deep_document_finder_service.dart';

/// Available autonomous agent tools for on-device and cloud agent reasoning.
enum AgentToolType {
  launchApp('LAUNCH_APP', 'Open installed applications dynamically by name', isSensitive: false),
  searchFilesAndOcr('SEARCH_FILES_AND_OCR', 'Search personal OCR docs, bills, and passports', isSensitive: false),
  queryMemory('QUERY_MEMORY', 'Search encrypted personal memory, expenses, and screen time', isSensitive: false),
  makeCall('MAKE_CALL', 'Initiate phone call to a contact or number', isSensitive: true),
  sendWhatsApp('SEND_WHATSAPP', 'Compose or send a WhatsApp message', isSensitive: true),
  uiAutomationStep('UI_AUTOMATION_STEP', 'Read foreground screen or navigate Back/Home', isSensitive: false),
  clickUi('CLICK_UI', 'Find and click a visible UI element by label or description', isSensitive: false),
  typeText('TYPE_TEXT', 'Inject text into an editable input field on screen', isSensitive: false),
  scrollScreen('SCROLL_SCREEN', 'Scroll active window down, up, left, or right', isSensitive: false),
  multiStepWorkflow('MULTI_STEP_WORKFLOW', 'Execute a multi-step UI automation sequence', isSensitive: false),
  openFile('OPEN_FILE', 'Open a local document or file on the phone', isSensitive: false);

  final String code;
  final String description;
  final bool isSensitive;

  const AgentToolType(this.code, this.description, {required this.isSensitive});
}

/// A structured tool call emitted by an LLM or offline deterministic intent parser.
@immutable
class AgentToolCall {
  final String toolName;
  final Map<String, dynamic> arguments;
  final String rationale;
  final bool isSensitive;

  const AgentToolCall({
    required this.toolName,
    required this.arguments,
    this.rationale = '',
    this.isSensitive = false,
  });

  @override
  String toString() => 'AgentToolCall($toolName, args: $arguments, sensitive: $isSensitive)';
}

/// An atomic execution step trace in the autonomous ReAct agent loop.
@immutable
class AgentExecutionStep {
  final String stepName;
  final String status; // 'running', 'success', 'failed', 'pending_approval'
  final String? output;
  final DateTime timestamp;

  const AgentExecutionStep({
    required this.stepName,
    required this.status,
    this.output,
    required this.timestamp,
  });

  @override
  String toString() => 'AgentExecutionStep($stepName: $status)';
}

/// The outcome of an autonomous agent execution loop.
@immutable
class AgentLoopResult {
  final bool hasAction;
  final List<AgentExecutionStep> steps;
  final String finalResponse;
  final PendingActionConfirmation? pendingConfirmation;
  final String? actionBadge;
  final List<DocumentMatchResult> matchedDocuments;

  const AgentLoopResult({
    required this.hasAction,
    required this.steps,
    required this.finalResponse,
    this.pendingConfirmation,
    this.actionBadge,
    this.matchedDocuments = const [],
  });
}

/// Autonomous ReAct Agent Service.
///
/// Discovers tools, parses intents from either natural language regex patterns or
/// structured cloud LLM tool-calling JSON, and executes safe actions on-device
/// while enforcing Human-in-the-Loop safety gates for sensitive actions.
class AutonomousAgentService {
  final ActionDispatcherService _actionDispatcher;
  final KnowledgeGraphService _knowledgeGraphService;
  final DeepDocumentFinderService? _documentFinderService;

  AutonomousAgentService({
    required ActionDispatcherService actionDispatcher,
    required KnowledgeGraphService knowledgeGraphService,
    DeepDocumentFinderService? documentFinderService,
  })  : _actionDispatcher = actionDispatcher,
        _knowledgeGraphService = knowledgeGraphService,
        _documentFinderService = documentFinderService;

  /// System prompt instructions for Cloud LLMs to emit structured tool calls.
  static String getToolSystemInstructions() {
    return '''
You have access to the following local Android OS tools:
- LAUNCH_APP: {"name": "<app_name>"} - Launch any installed application on the device by common name (e.g. "whatsapp", "camera", "settings", "youtube").
- CLICK_UI: {"targetText": "<label_to_click>"} - Click on a visible UI button, icon, or link by its text or accessibility description.
- TYPE_TEXT: {"text": "<text_to_type>", "targetHint": "<optional_field_hint>"} - Inject text into an editable input field.
- SCROLL_SCREEN: {"direction": "down" | "up" | "left" | "right"} - Scroll active window or list.
- MULTI_STEP_WORKFLOW: {"app": "<app_name>", "action": "search", "query": "<search_query>"} - Open app and automatically search for a query.
- SEARCH_FILES_AND_OCR: {"query": "<search_term>"} - Search indexed OCR documents (passports, invoices, boarding passes).
- OPEN_FILE: {"uri": "<file_uri>", "mimeType": "<optional_mime>"} - Open local document or image in native viewer.
- QUERY_MEMORY: {"query": "<query>"} - Query local encrypted memories, screen time, expenses, and calls.
- MAKE_CALL: {"phoneNumber": "<phone_number>"} - Place a phone call (requires user confirmation).
- SEND_WHATSAPP: {"phoneNumber": "<number>", "message": "<text>"} - Compose WhatsApp message (requires user confirmation).
- UI_AUTOMATION_STEP: {"action": "read_screen" | "back" | "home"} - Read current screen text or navigate.

If the user request is an action that can be executed by a tool, you MUST respond ONLY with a JSON object:
{
  "thought": "<brief reasoning>",
  "tool_call": {
    "name": "<TOOL_NAME>",
    "arguments": { <tool arguments> }
  },
  "response": "<friendly message to user>"
}
''';
  }

  /// Parses an action intent from natural language using deterministic rules (offline-capable).
  AgentToolCall? parseToolCall(String userPrompt) {
    final lower = userPrompt.trim().toLowerCase();

    // 1. Compound Multi-Step Workflow: E.g., "Open YouTube and search Flutter tutorials"
    final compoundWorkflowRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:open|launch)\s+([a-zA-Z0-9_\s\-]+)\s+and\s+(?:search(?: for)?)\s+(.+)$',
      caseSensitive: false,
    );
    final compoundMatch = compoundWorkflowRegex.firstMatch(userPrompt.trim());
    if (compoundMatch != null) {
      final appName = compoundMatch.group(1)!.trim();
      final query = compoundMatch.group(2)!.trim();
      return AgentToolCall(
        toolName: AgentToolType.multiStepWorkflow.code,
        arguments: {'app': appName, 'action': 'search', 'query': query},
        rationale: 'Execute multi-step workflow: Launch "$appName" and search for "$query"',
        isSensitive: false,
      );
    }

    // 2. App Launch: "open whatsapp", "launch camera", "please open settings", "can you start youtube"
    final openAppRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:open|launch|start|switch to)\s+([a-zA-Z0-9_\s\-]+)$',
      caseSensitive: false,
    );
    final openMatch = openAppRegex.firstMatch(userPrompt.trim());
    if (openMatch != null) {
      final appName = openMatch.group(1)!.trim();
      return AgentToolCall(
        toolName: AgentToolType.launchApp.code,
        arguments: {'name': appName},
        rationale: 'User explicitly requested opening application "$appName"',
        isSensitive: false,
      );
    }

    // 3. UI Automation: Read Screen / Back / Home
    if (lower.contains('read screen') ||
        lower.contains('read my screen') ||
        lower.contains('what is on my screen') ||
        lower.contains('what\'s on screen')) {
      return const AgentToolCall(
        toolName: 'UI_AUTOMATION_STEP',
        arguments: {'action': 'read_screen'},
        rationale: 'User requested reading foreground screen content via Accessibility',
        isSensitive: false,
      );
    }
    if (lower == 'go back' || lower == 'back') {
      return const AgentToolCall(
        toolName: 'UI_AUTOMATION_STEP',
        arguments: {'action': 'back'},
        rationale: 'User requested Android Back navigation',
        isSensitive: false,
      );
    }
    if (lower == 'go home' || lower == 'home') {
      return const AgentToolCall(
        toolName: 'UI_AUTOMATION_STEP',
        arguments: {'action': 'home'},
        rationale: 'User requested Android Home navigation',
        isSensitive: false,
      );
    }

    // 4. Scroll Screen: E.g., "Scroll down", "Swipe up", "Scroll right"
    final scrollRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:scroll|swipe)\s+(down|up|left|right)$',
      caseSensitive: false,
    );
    final scrollMatch = scrollRegex.firstMatch(userPrompt.trim());
    if (scrollMatch != null) {
      final direction = scrollMatch.group(1)!.toLowerCase();
      return AgentToolCall(
        toolName: AgentToolType.scrollScreen.code,
        arguments: {'direction': direction},
        rationale: 'Scroll active screen $direction',
        isSensitive: false,
      );
    }

    // 5. Type Text: E.g., 'Type "Flutter" into Search', 'Write "Hello World"'
    final typeRegex = RegExp(
      r'''^(?:can you\s+)?(?:please\s+)?(?:type|enter|write)\s+["']?([^"']+)["']?(?:\s+(?:in|into)\s+([a-zA-Z0-9_\s]+))?$''',
      caseSensitive: false,
    );
    final typeMatch = typeRegex.firstMatch(userPrompt.trim());
    if (typeMatch != null) {
      final textToInject = typeMatch.group(1)!.trim();
      final targetHint = typeMatch.group(2)?.trim();
      return AgentToolCall(
        toolName: AgentToolType.typeText.code,
        arguments: {'text': textToInject, 'targetHint': ?targetHint},
        rationale: 'Inject text "$textToInject" into screen input',
        isSensitive: false,
      );
    }

    // 6. Click / Tap UI Element: E.g., "Click on Settings", "Tap Next", "Click Pay Now"
    final clickRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:click on|click|tap on|tap)\s+(.+)$',
      caseSensitive: false,
    );
    final clickMatch = clickRegex.firstMatch(userPrompt.trim());
    if (clickMatch != null) {
      final target = clickMatch.group(1)!.trim();
      final isDangerous = ActionDispatcherService.dangerousFinancialKeywords
          .any((k) => target.toLowerCase().contains(k));
      return AgentToolCall(
        toolName: AgentToolType.clickUi.code,
        arguments: {'targetText': target},
        rationale: 'Click on UI element "$target"',
        isSensitive: isDangerous,
      );
    }

    // 7. Sensitive Action: Call Number
    final callRegex = RegExp(r'^(?:call|dial)\s+([+0-9\s\-]{6,20})$', caseSensitive: false);
    final callMatch = callRegex.firstMatch(userPrompt.trim());
    if (callMatch != null) {
      final number = callMatch.group(1)!.trim();
      return AgentToolCall(
        toolName: AgentToolType.makeCall.code,
        arguments: {'phoneNumber': number},
        rationale: 'Dialing phone number $number',
        isSensitive: true,
      );
    }

    // 8. Sensitive Action: WhatsApp Message
    final waRegex = RegExp(
      r'^(?:whatsapp|send whatsapp to)\s+([+0-9\s\-]{6,20})[:\s]+(?:saying\s+)?(.+)$',
      caseSensitive: false,
    );
    final waMatch = waRegex.firstMatch(userPrompt.trim());
    if (waMatch != null) {
      final number = waMatch.group(1)!.trim();
      final msg = waMatch.group(2)!.trim();
      return AgentToolCall(
        toolName: AgentToolType.sendWhatsApp.code,
        arguments: {'phoneNumber': number, 'message': msg},
        rationale: 'Composing WhatsApp message to $number',
        isSensitive: true,
      );
    }

    // 9. Open File / Document
    final openFileRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:open file|view file|open document)\s+(.+)$',
      caseSensitive: false,
    );
    final openFileMatch = openFileRegex.firstMatch(userPrompt.trim());
    if (openFileMatch != null) {
      final uri = openFileMatch.group(1)!.trim();
      return AgentToolCall(
        toolName: AgentToolType.openFile.code,
        arguments: {'uri': uri},
        rationale: 'Open file "$uri" on device',
        isSensitive: false,
      );
    }

    // 10. Deep Document, Passport & OCR Search
    if (lower.contains('passport') ||
        lower.contains('boarding pass') ||
        lower.contains('ticket') ||
        lower.contains('invoice') ||
        lower.contains('receipt') ||
        lower.contains('bill') ||
        lower.contains('statement') ||
        lower.contains('document') ||
        lower.contains('search files') ||
        lower.contains('find files') ||
        lower.contains('find my doc')) {
      return AgentToolCall(
        toolName: AgentToolType.searchFilesAndOcr.code,
        arguments: {'query': userPrompt.trim()},
        rationale: 'Searching personal OCR documents and device files',
        isSensitive: false,
      );
    }

    return null;
  }

  /// Parses a structured tool call from a Cloud LLM JSON response.
  AgentToolCall? parseToolCallFromJson(String responseText) {
    try {
      final trimmed = responseText.trim();
      final jsonStart = trimmed.indexOf('{');
      final jsonEnd = trimmed.lastIndexOf('}');
      if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) return null;

      final jsonStr = trimmed.substring(jsonStart, jsonEnd + 1);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (map.containsKey('tool_call')) {
        final toolCallMap = map['tool_call'] as Map<String, dynamic>;
        final name = (toolCallMap['name'] ?? '').toString().toUpperCase();
        final args = Map<String, dynamic>.from(toolCallMap['arguments'] as Map? ?? {});
        final thought = (map['thought'] ?? '').toString();

        final isDangerousClick = (name == 'CLICK_UI') &&
            ActionDispatcherService.dangerousFinancialKeywords.any((k) =>
                (args['targetText'] ?? args['text'] ?? '').toString().toLowerCase().contains(k));
        final isSensitive = (name == 'MAKE_CALL' || name == 'SEND_WHATSAPP' || isDangerousClick);

        return AgentToolCall(
          toolName: name,
          arguments: args,
          rationale: thought,
          isSensitive: isSensitive,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Executes the autonomous ReAct tool execution loop.
  Future<AgentLoopResult> executeAgentLoop(
    String userPrompt, {
    AgentToolCall? initialCall,
  }) async {
    final toolCall = initialCall ?? parseToolCall(userPrompt);
    if (toolCall == null) {
      return const AgentLoopResult(
        hasAction: false,
        steps: [],
        finalResponse: '',
      );
    }

    final steps = <AgentExecutionStep>[];
    final now = DateTime.now();

    // Step 1: Interpret Action
    steps.add(AgentExecutionStep(
      stepName: '🔍 Resolving tool: ${toolCall.toolName}',
      status: 'running',
      output: 'Arguments: ${toolCall.arguments}',
      timestamp: now,
    ));

    // Handle Sensitive Tools with Human-in-the-Loop Confirmation Gate
    if (toolCall.isSensitive) {
      final phoneAction = _mapToolCallToPhoneAction(toolCall);
      final pending = PendingActionConfirmation(
        action: phoneAction,
        promptMessage: 'Confirm Action: ${phoneAction.description}?',
        createdAt: DateTime.now(),
      );

      steps.add(AgentExecutionStep(
        stepName: '⚠️ Safety Gate: Human Approval Required',
        status: 'pending_approval',
        output: phoneAction.description,
        timestamp: DateTime.now(),
      ));

      return AgentLoopResult(
        hasAction: true,
        steps: steps,
        finalResponse: '⚠️ **Safety Confirmation Gate Required:**\n\n'
            'Please review and approve before execution:\n'
            '• **Action:** ${phoneAction.description}',
        pendingConfirmation: pending,
        actionBadge: 'Safety Gate',
      );
    }

    // Safe Tool Execution
    switch (toolCall.toolName) {
      case 'LAUNCH_APP':
        final rawName = (toolCall.arguments['name'] ?? '').toString().trim();
        steps.add(AgentExecutionStep(
          stepName: '🔍 Querying Android PackageManager for "$rawName"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final launchResult = await _actionDispatcher.launchAppByName(rawName);
        if (launchResult['success'] == true) {
          final appName = launchResult['appName'] ?? rawName;
          final pkg = launchResult['packageName'] ?? '';
          steps.add(AgentExecutionStep(
            stepName: '🚀 Launched $appName ($pkg)',
            status: 'success',
            output: 'Package: $pkg',
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: '✅ Successfully launched **$appName** (`$pkg`) on your device.',
            actionBadge: 'App Launcher',
          );
        } else {
          final error = launchResult['error'] ?? 'App not found';
          steps.add(AgentExecutionStep(
            stepName: '❌ Could not find installed app "$rawName"',
            status: 'failed',
            output: error.toString(),
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: 'I could not find an installed app matching "$rawName" on your device. '
                'Please verify the app name in your app drawer.',
            actionBadge: 'App Launcher',
          );
        }

      case 'SEARCH_FILES_AND_OCR':
        final query = (toolCall.arguments['query'] ?? userPrompt).toString();
        steps.add(AgentExecutionStep(
          stepName: '🔍 Searching encrypted vault for "$query"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        // 1. Check DeepDocumentFinderService (Two-stage retrieval: vault + on-demand live scan)
        if (_documentFinderService != null) {
          final docMatches = await _documentFinderService.findDocument(query);

          if (docMatches.isNotEmpty) {
            final fromLive = docMatches.any((m) => m.fromLiveScan);
            steps.add(AgentExecutionStep(
              stepName: fromLive
                  ? '📂 Scanned device storage & extracted text via ML Kit'
                  : '✅ Retrieved ${docMatches.length} document(s) from encrypted vault',
              status: 'success',
              output: 'Found ${docMatches.length} matching document(s)',
              timestamp: DateTime.now(),
            ));

            final buffer = StringBuffer();
            buffer.writeln('📄 **Found ${docMatches.length} Matching Document(s):**\n');
            for (final doc in docMatches) {
              buffer.writeln('• **${doc.title}** (`${doc.category}`)');
              if (doc.extractedSummary.isNotEmpty) {
                buffer.writeln('  *Summary:* ${doc.extractedSummary}');
              }
              if (doc.keyFields.isNotEmpty) {
                final fields = doc.keyFields.entries
                    .where((e) => e.value != null && e.value.toString().isNotEmpty && e.value.toString() != '[]')
                    .map((e) => '${e.key}: ${e.value}')
                    .join(', ');
                if (fields.isNotEmpty) {
                  buffer.writeln('  *Key Details:* $fields');
                }
              }
            }

            return AgentLoopResult(
              hasAction: true,
              steps: steps,
              finalResponse: buffer.toString().trim(),
              actionBadge: 'Document Finder',
              matchedDocuments: docMatches,
            );
          }
        }

        // 2. Fallback to KnowledgeGraphService
        final result = await _knowledgeGraphService.queryRelatedMemories(query);
        final docs = result.memories.where((m) => m.category == 'ocr_doc').toList();

        if (docs.isNotEmpty) {
          final buffer = StringBuffer();
          buffer.writeln('📄 **Found ${docs.length} matching document(s):**\n');
          for (final doc in docs) {
            buffer.writeln('• ${doc.content}');
            if (doc.metadataJson.isNotEmpty && doc.metadataJson != '{}') {
              buffer.writeln('  *Metadata:* `${doc.metadataJson}`');
            }
          }

          steps.add(AgentExecutionStep(
            stepName: '✅ Retrieved ${docs.length} OCR document(s)',
            status: 'success',
            output: 'Found ${docs.length} matches in local Knowledge Graph',
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: buffer.toString().trim(),
            actionBadge: 'Vision OCR',
          );
        } else {
          steps.add(AgentExecutionStep(
            stepName: '📄 No documents found matching "$query"',
            status: 'success',
            output: 'Zero matching documents',
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: 'No matching OCR documents or files were found for "$query". '
                'Make sure the document is located in your device Gallery or Downloads/Documents.',
            actionBadge: 'Vision OCR',
          );
        }

      case 'OPEN_FILE':
        final uri = (toolCall.arguments['uri'] ?? toolCall.arguments['fileUri'] ?? '').toString();
        final mime = toolCall.arguments['mimeType']?.toString();
        steps.add(AgentExecutionStep(
          stepName: '📂 Opening document file...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final res = await _actionDispatcher.openFileUri(uri, mimeType: mime);
        final success = res['success'] == true;
        steps.add(AgentExecutionStep(
          stepName: success ? '✅ Opened file in viewer' : '❌ Failed to open file',
          status: success ? 'success' : 'failed',
          output: res['error']?.toString() ?? res['message']?.toString(),
          timestamp: DateTime.now(),
        ));

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: success
              ? '✅ Opened document in your phone\'s default viewer.'
              : 'Could not open file: ${res['error'] ?? 'Unknown error'}',
          actionBadge: 'Document Viewer',
        );

      case 'QUERY_MEMORY':
        final query = (toolCall.arguments['query'] ?? userPrompt).toString();
        steps.add(AgentExecutionStep(
          stepName: '🧠 Searching encrypted personal memories for "$query"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final result = await _knowledgeGraphService.queryRelatedMemories(query);
        final nodes = result.memories;

        steps.add(AgentExecutionStep(
          stepName: '✅ Retrieved ${nodes.length} memory node(s)',
          status: 'success',
          output: 'Found ${nodes.length} local memories',
          timestamp: DateTime.now(),
        ));

        final text = nodes.isNotEmpty
            ? '🧠 **Local Memories Found:**\n\n${nodes.take(5).map((n) => '• [${n.category}] ${n.content}').join('\n')}'
            : 'No matching memories found for "$query".';

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: text,
          actionBadge: 'Personal Memory',
        );

      case 'UI_AUTOMATION_STEP':
        final action = (toolCall.arguments['action'] ?? 'read_screen').toString();
        if (action == 'read_screen') {
          steps.add(AgentExecutionStep(
            stepName: '📱 Reading visible screen via Accessibility Service...',
            status: 'running',
            timestamp: DateTime.now(),
          ));

          final phoneAction = PhoneAction(
            id: 'act_${DateTime.now().millisecondsSinceEpoch}',
            type: ActionType.readScreen,
            params: const {},
            description: 'Read visible screen content',
            isSensitive: false,
          );
          final res = await _actionDispatcher.executeConfirmedAction(phoneAction);
          final screenText = res.data as String? ?? '';

          steps.add(AgentExecutionStep(
            stepName: res.success ? '✅ Read screen content' : '❌ Accessibility disabled',
            status: res.success ? 'success' : 'failed',
            output: res.message,
            timestamp: DateTime.now(),
          ));

          final text = screenText.isNotEmpty
              ? '📱 **Foreground Screen Content:**\n\n$screenText'
              : '📱 Screen is empty or Accessibility Service is not enabled.';

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: text,
            actionBadge: 'Screen Reader',
          );
        } else {
          // System navigation
          steps.add(AgentExecutionStep(
            stepName: '📱 Performing Android Navigation ($action)...',
            status: 'running',
            timestamp: DateTime.now(),
          ));

          final phoneAction = PhoneAction(
            id: 'act_${DateTime.now().millisecondsSinceEpoch}',
            type: ActionType.globalNav,
            params: {'action': action},
            description: 'Navigate $action',
            isSensitive: false,
          );
          final res = await _actionDispatcher.executeConfirmedAction(phoneAction);

          steps.add(AgentExecutionStep(
            stepName: res.success ? '✅ Performed $action' : '❌ Navigation failed',
            status: res.success ? 'success' : 'failed',
            output: res.message,
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: '⚡ Performed navigation: **$action**',
            actionBadge: 'Navigation',
          );
        }

      case 'CLICK_UI':
        final target = (toolCall.arguments['targetText'] ?? toolCall.arguments['text'] ?? '').toString();
        steps.add(AgentExecutionStep(
          stepName: '🔍 Searching screen for "$target"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final res = await _actionDispatcher.clickUiElement(target);
        if (res['isFinancialBlocked'] == true) {
          steps.add(AgentExecutionStep(
            stepName: '⚠️ Blocked by Financial Safety Gate',
            status: 'failed',
            output: 'Sensitive financial action requires explicit approval',
            timestamp: DateTime.now(),
          ));
          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: '⚠️ **Action Blocked by Financial Safety Gate:**\n'
                'Clicking "$target" was prevented because it matches critical payment actions. '
                'Please perform this step manually.',
            actionBadge: 'Safety Gate',
          );
        }

        final success = res['success'] == true;
        final msg = res['message']?.toString() ?? (success ? 'Clicked on "$target"' : 'Could not find UI element');
        steps.add(AgentExecutionStep(
          stepName: success ? '✅ Clicked on "$target"' : '❌ Failed to click "$target"',
          status: success ? 'success' : 'failed',
          output: msg,
          timestamp: DateTime.now(),
        ));

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: success
              ? '⚡ Clicked on **${res['matchedText'] ?? target}** on screen.'
              : 'Unable to click on "$target": $msg',
          actionBadge: 'UI Automation',
        );

      case 'TYPE_TEXT':
        final text = (toolCall.arguments['text'] ?? '').toString();
        final hint = toolCall.arguments['targetHint']?.toString();
        steps.add(AgentExecutionStep(
          stepName: '⌨️ Injecting text into input field${hint != null ? ' ($hint)' : ''}...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final res = await _actionDispatcher.typeUiText(text, targetHint: hint);
        final success = res['success'] == true;
        final msg = res['message']?.toString() ?? (success ? 'Injected text' : 'No editable field');
        steps.add(AgentExecutionStep(
          stepName: success ? '✅ Injected "$text"' : '❌ Injection failed',
          status: success ? 'success' : 'failed',
          output: msg,
          timestamp: DateTime.now(),
        ));

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: success
              ? '⚡ Injected text: **"$text"** into the active input field.'
              : 'Failed to inject text: $msg',
          actionBadge: 'UI Automation',
        );

      case 'SCROLL_SCREEN':
        final direction = (toolCall.arguments['direction'] ?? 'down').toString().toLowerCase();
        steps.add(AgentExecutionStep(
          stepName: '📜 Scrolling screen $direction...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final res = await _actionDispatcher.scrollUi(direction);
        final success = res['success'] == true;
        steps.add(AgentExecutionStep(
          stepName: success ? '✅ Scrolled screen $direction' : '❌ Scroll failed',
          status: success ? 'success' : 'failed',
          output: res['method']?.toString(),
          timestamp: DateTime.now(),
        ));

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: success
              ? '⚡ Scrolled screen **$direction**.'
              : 'Unable to scroll screen in direction "$direction".',
          actionBadge: 'UI Automation',
        );

      case 'MULTI_STEP_WORKFLOW':
        final app = (toolCall.arguments['app'] ?? '').toString();
        final query = (toolCall.arguments['query'] ?? '').toString();

        // Step 1: Launch App
        steps.add(AgentExecutionStep(
          stepName: '🚀 Step 1/3: Launching "$app"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        final launchRes = await _actionDispatcher.launchAppByName(app);
        if (launchRes['success'] != true) {
          steps.add(AgentExecutionStep(
            stepName: '❌ Step 1/3: Could not launch "$app"',
            status: 'failed',
            output: launchRes['error']?.toString() ?? 'App not found',
            timestamp: DateTime.now(),
          ));
          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: 'Multi-step workflow failed: Could not launch "$app".',
            actionBadge: 'Multi-Step UI',
          );
        }

        final resolvedApp = launchRes['appName'] ?? app;
        steps.add(AgentExecutionStep(
          stepName: '✅ Step 1/3: Launched $resolvedApp',
          status: 'success',
          output: 'Package: ${launchRes['packageName']}',
          timestamp: DateTime.now(),
        ));

        // Step 2: Render delay
        steps.add(AgentExecutionStep(
          stepName: '⏳ Step 2/3: Waiting for $resolvedApp UI to settle...',
          status: 'running',
          timestamp: DateTime.now(),
        ));
        await Future.delayed(const Duration(milliseconds: 1200));
        steps.add(AgentExecutionStep(
          stepName: '✅ Step 2/3: UI ready',
          status: 'success',
          timestamp: DateTime.now(),
        ));

        // Step 3: Search
        steps.add(AgentExecutionStep(
          stepName: '🔍 Step 3/3: Searching for "$query"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

        // Click search if present
        await _actionDispatcher.clickUiElement('Search');
        final typeRes = await _actionDispatcher.typeUiText(query, targetHint: 'Search');

        steps.add(AgentExecutionStep(
          stepName: typeRes['success'] == true
              ? '✅ Step 3/3: Searched "$query"'
              : '⚠️ Step 3/3: Query entered',
          status: 'success',
          output: typeRes['message']?.toString(),
          timestamp: DateTime.now(),
        ));

        return AgentLoopResult(
          hasAction: true,
          steps: steps,
          finalResponse: '✅ **Multi-Step UI Automation Complete:**\n'
              '• Launched **$resolvedApp**\n'
              '• Activated search and queried **"$query"**',
          actionBadge: 'Multi-Step UI',
        );

      default:
        return AgentLoopResult(
          hasAction: false,
          steps: steps,
          finalResponse: 'Unknown tool call: ${toolCall.toolName}',
        );
    }
  }

  PhoneAction _mapToolCallToPhoneAction(AgentToolCall call) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (call.toolName == 'MAKE_CALL') {
      final number = (call.arguments['phoneNumber'] ?? '').toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.callContact,
        params: {'phoneNumber': number},
        description: 'Dial phone number $number',
        isSensitive: true,
      );
    } else if (call.toolName == 'SEND_WHATSAPP') {
      final number = (call.arguments['phoneNumber'] ?? '').toString();
      final msg = (call.arguments['message'] ?? '').toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.sendWhatsApp,
        params: {'phoneNumber': number, 'message': msg},
        description: 'Send WhatsApp to $number: "$msg"',
        isSensitive: true,
      );
    } else if (call.toolName == 'CLICK_UI') {
      final target = (call.arguments['targetText'] ?? call.arguments['text'] ?? '').toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.clickUi,
        params: {'targetText': target},
        description: 'Click on UI element "$target"',
        isSensitive: call.isSensitive,
      );
    } else if (call.toolName == 'TYPE_TEXT') {
      final text = (call.arguments['text'] ?? '').toString();
      final hint = call.arguments['targetHint']?.toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.typeText,
        params: call.arguments,
        description: 'Type "$text"${hint != null ? ' into "$hint"' : ''}',
        isSensitive: false,
      );
    } else if (call.toolName == 'SCROLL_SCREEN') {
      final dir = (call.arguments['direction'] ?? 'down').toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.scrollUi,
        params: call.arguments,
        description: 'Scroll screen $dir',
        isSensitive: false,
      );
    } else if (call.toolName == 'OPEN_FILE') {
      final uri = (call.arguments['uri'] ?? call.arguments['fileUri'] ?? '').toString();
      final mime = call.arguments['mimeType']?.toString();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.openFile,
        params: {'uri': uri, 'mimeType': ?mime},
        description: 'Open file "$uri"',
        isSensitive: false,
      );
    }

    return PhoneAction(
      id: 'act_$nowMs',
      type: ActionType.globalNav,
      params: call.arguments,
      description: 'Execute ${call.toolName}',
      isSensitive: call.isSensitive,
    );
  }
}
