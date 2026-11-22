import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/action_dispatcher_service.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/services/knowledge_graph_service.dart';

/// Available autonomous agent tools for on-device and cloud agent reasoning.
enum AgentToolType {
  launchApp('LAUNCH_APP', 'Open installed applications dynamically by name', isSensitive: false),
  searchFilesAndOcr('SEARCH_FILES_AND_OCR', 'Search personal OCR docs, bills, and passports', isSensitive: false),
  queryMemory('QUERY_MEMORY', 'Search encrypted personal memory, expenses, and screen time', isSensitive: false),
  makeCall('MAKE_CALL', 'Initiate phone call to a contact or number', isSensitive: true),
  sendWhatsApp('SEND_WHATSAPP', 'Compose or send a WhatsApp message', isSensitive: true),
  uiAutomationStep('UI_AUTOMATION_STEP', 'Read foreground screen or navigate Back/Home', isSensitive: false);

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

  const AgentLoopResult({
    required this.hasAction,
    required this.steps,
    required this.finalResponse,
    this.pendingConfirmation,
    this.actionBadge,
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

  AutonomousAgentService({
    required ActionDispatcherService actionDispatcher,
    required KnowledgeGraphService knowledgeGraphService,
  })  : _actionDispatcher = actionDispatcher,
        _knowledgeGraphService = knowledgeGraphService;

  /// System prompt instructions for Cloud LLMs to emit structured tool calls.
  static String getToolSystemInstructions() {
    return '''
You have access to the following local Android OS tools:
- LAUNCH_APP: {"name": "<app_name>"} - Launch any installed application on the device by common name (e.g. "whatsapp", "camera", "settings", "youtube").
- SEARCH_FILES_AND_OCR: {"query": "<search_term>"} - Search indexed OCR documents (passports, invoices, boarding passes).
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

    // 1. App Launch: "open whatsapp", "launch camera", "please open settings", "can you start youtube"
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

    // 2. UI Automation: Read Screen / Back / Home
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

    // 3. Sensitive Action: Call Number
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

    // 4. Sensitive Action: WhatsApp Message
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

    // 5. OCR & Document Search
    if (lower.contains('passport') ||
        lower.contains('boarding pass') ||
        lower.contains('invoice') ||
        lower.contains('receipt') ||
        lower.contains('find my document')) {
      return AgentToolCall(
        toolName: AgentToolType.searchFilesAndOcr.code,
        arguments: {'query': userPrompt.trim()},
        rationale: 'Searching personal OCR documents',
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

        final isSensitive = (name == 'MAKE_CALL' || name == 'SEND_WHATSAPP');
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
          stepName: '📄 Searching OCR documents for "$query"...',
          status: 'running',
          timestamp: DateTime.now(),
        ));

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
            stepName: '📄 No OCR documents found matching "$query"',
            status: 'success',
            output: 'Zero matching documents',
            timestamp: DateTime.now(),
          ));

          return AgentLoopResult(
            hasAction: true,
            steps: steps,
            finalResponse: 'No matching OCR documents or receipts were found in your local Knowledge Graph. '
                'You can tap "Index Gallery OCR" in the Dashboard to index gallery documents.',
            actionBadge: 'Vision OCR',
          );
        }

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
