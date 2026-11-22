import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The categories of device actions supported by Matrix AI OS.
enum ActionType {
  callContact('Call Contact', isSensitive: true),
  sendWhatsApp('Send WhatsApp', isSensitive: true),
  openApp('Open Application', isSensitive: false),
  readScreen('Read Foreground Screen', isSensitive: false),
  globalNav('System Navigation', isSensitive: false),
  clickUi('Click UI Element', isSensitive: false),
  typeText('Type Text', isSensitive: false),
  scrollUi('Scroll Screen', isSensitive: false),
  inspectUi('Inspect UI Tree', isSensitive: false),
  openFile('Open Document / File', isSensitive: false);

  final String displayName;
  final bool isSensitive;
  const ActionType(this.displayName, {required this.isSensitive});
}

/// Represents a concrete phone action to execute or confirm.
@immutable
class PhoneAction {
  final String id;
  final ActionType type;
  final Map<String, dynamic> params;
  final String description;
  final bool isSensitive;

  const PhoneAction({
    required this.id,
    required this.type,
    required this.params,
    required this.description,
    required this.isSensitive,
  });

  @override
  String toString() => 'PhoneAction($type, $description, sensitive: $isSensitive)';
}

/// Represents a pending action awaiting explicit Human-in-the-Loop user approval.
@immutable
class PendingActionConfirmation {
  final PhoneAction action;
  final String promptMessage;
  final DateTime createdAt;

  const PendingActionConfirmation({
    required this.action,
    required this.promptMessage,
    required this.createdAt,
  });
}

/// Result returned following action execution.
@immutable
class ActionResult {
  final bool success;
  final String message;
  final PhoneAction action;
  final dynamic data;

  const ActionResult({
    required this.success,
    required this.message,
    required this.action,
    this.data,
  });
}

/// Action Dispatcher & Safety Confirmation Gate.
///
/// Ensures that zero sensitive actions (calls, messages, external dispatch)
/// execute without explicit user approval in the UI, and resolves real installed
/// apps dynamically via Android's PackageManager.
class ActionDispatcherService {
  final MethodChannel _channel;

  static const String channelName = 'com.matrixai.os/action_executor';

  /// Dangerous financial and destructive action keywords that require explicit
  /// Human-in-the-Loop user approval before executing clicks.
  static const List<String> dangerousFinancialKeywords = [
    'pay now',
    'confirm payment',
    'make payment',
    'send money',
    'proceed to pay',
    'transfer funds',
    'transfer money',
    'delete account',
    'wipe data',
    'authorize payment',
  ];

  ActionDispatcherService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  // Common fallback app package hints if offline or legacy
  static const Map<String, String> _appPackages = {
    'whatsapp': 'com.whatsapp',
    'youtube': 'com.google.android.youtube',
    'chrome': 'com.android.chrome',
    'settings': 'com.android.settings',
    'maps': 'com.google.android.apps.maps',
    'camera': 'camera',
    'gmail': 'com.google.android.gm',
    'messages': 'com.google.android.apps.messaging',
    'spotify': 'com.spotify.music',
  };

  /// Parses an action intent from a user query or AI proposed command.
  PhoneAction? parseActionIntent(String text) {
    final lower = text.trim().toLowerCase();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Screen Reading
    if (lower.contains('read screen') ||
        lower.contains('read my screen') ||
        lower.contains('what is on my screen') ||
        lower.contains('what\'s on screen')) {
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.readScreen,
        params: const {},
        description: 'Read visible foreground screen content via Accessibility Service',
        isSensitive: false,
      );
    }

    // 2. Navigation Actions
    if (lower == 'go back' || lower == 'back') {
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.globalNav,
        params: {'action': 'back'},
        description: 'Perform Android Back navigation',
        isSensitive: false,
      );
    }
    if (lower == 'go home' || lower == 'home') {
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.globalNav,
        params: {'action': 'home'},
        description: 'Perform Android Home navigation',
        isSensitive: false,
      );
    }

    // 3. Call Contact / Dial Number
    // E.g.: "Call +91 98765 43210" or "Call 9876543210" or "Dial 1234567890"
    final callRegex = RegExp(r'(?:call|dial)\s+([+0-9\s\-]{6,20})\b', caseSensitive: false);
    final callMatch = callRegex.firstMatch(text);
    if (callMatch != null) {
      final number = callMatch.group(1)!.trim();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.callContact,
        params: {'phoneNumber': number},
        description: 'Dial phone number $number',
        isSensitive: true,
      );
    }

    // 4. Send WhatsApp
    // E.g.: "WhatsApp +91 98765 43210: Hello there" or "Send WhatsApp to 9876543210 saying Hello"
    final waRegex = RegExp(
      r'(?:whatsapp|send whatsapp to)\s+([+0-9\s\-]{6,20})[:\s]+(?:saying\s+)?(.+)',
      caseSensitive: false,
    );
    final waMatch = waRegex.firstMatch(text);
    if (waMatch != null) {
      final number = waMatch.group(1)!.trim();
      final msg = waMatch.group(2)!.trim();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.sendWhatsApp,
        params: {'phoneNumber': number, 'message': msg},
        description: 'Compose WhatsApp message to $number: "$msg"',
        isSensitive: true,
      );
    }

    // 5. Open Application (Dynamic App Launcher)
    // E.g.: "Open WhatsApp", "Launch Camera", "Please open Settings", "Can you launch YouTube"
    final openAppRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:open|launch|start|switch to)\s+([a-zA-Z0-9_\s\-]+)$',
      caseSensitive: false,
    );
    final openMatch = openAppRegex.firstMatch(text.trim());
    if (openMatch != null) {
      final rawAppName = openMatch.group(1)!.trim();
      final cleanAppName = rawAppName.toLowerCase();
      final pkg = _appPackages[cleanAppName] ?? cleanAppName;
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.openApp,
        params: {'packageName': pkg, 'appName': rawAppName},
        description: 'Open application "$rawAppName"',
        isSensitive: false,
      );
    }

    // 6. UI Inspection / Tree Elements
    if (lower.contains('inspect ui') ||
        lower.contains('inspect ui tree') ||
        lower.contains('inspect screen elements') ||
        lower == 'ui tree') {
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.inspectUi,
        params: const {},
        description: 'Inspect interactive UI tree elements via Accessibility',
        isSensitive: false,
      );
    }

    // 7. Scroll Screen (down, up, left, right)
    // E.g.: "Scroll down", "Swipe up", "Scroll right"
    final scrollRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:scroll|swipe)\s+(down|up|left|right)$',
      caseSensitive: false,
    );
    final scrollMatch = scrollRegex.firstMatch(text.trim());
    if (scrollMatch != null) {
      final direction = scrollMatch.group(1)!.toLowerCase();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.scrollUi,
        params: {'direction': direction},
        description: 'Scroll screen $direction',
        isSensitive: false,
      );
    }

    // 8. Type / Inject Text
    // E.g.: 'Type "Flutter" into Search', 'Enter "Hello World"', 'Write "Matrix OS"'
    final typeRegex = RegExp(
      r'''^(?:can you\s+)?(?:please\s+)?(?:type|enter|write)\s+["']?([^"']+)["']?(?:\s+(?:in|into)\s+([a-zA-Z0-9_\s]+))?$''',
      caseSensitive: false,
    );
    final typeMatch = typeRegex.firstMatch(text.trim());
    if (typeMatch != null) {
      final textToInject = typeMatch.group(1)!.trim();
      final targetHint = typeMatch.group(2)?.trim();
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.typeText,
        params: {'text': textToInject, 'targetHint': ?targetHint},
        description: 'Type "$textToInject"${targetHint != null ? ' into "$targetHint"' : ''}',
        isSensitive: false,
      );
    }

    // 9. Click / Tap UI Element
    // E.g.: "Click on Search", "Tap Subscribe", "Click Next", "Click Pay Now"
    final clickRegex = RegExp(
      r'^(?:can you\s+)?(?:please\s+)?(?:click on|click|tap on|tap)\s+(.+)$',
      caseSensitive: false,
    );
    final clickMatch = clickRegex.firstMatch(text.trim());
    if (clickMatch != null) {
      final target = clickMatch.group(1)!.trim();
      final isDangerous = dangerousFinancialKeywords.any((k) => target.toLowerCase().contains(k));
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.clickUi,
        params: {'targetText': target},
        description: 'Click on "$target"',
        isSensitive: isDangerous,
      );
    }

    return null;
  }

  /// Processes an action with the Human-in-the-Loop Confirmation Gate.
  ///
  /// If the action is [isSensitive], returns a [PendingActionConfirmation] requiring
  /// explicit user UI approval. If safe, executes directly.
  Future<dynamic> processAction(PhoneAction action) async {
    if (action.isSensitive) {
      return PendingActionConfirmation(
        action: action,
        promptMessage: 'Confirm Action: ${action.description}?',
        createdAt: DateTime.now(),
      );
    }

    // Safe action: execute directly
    return executeConfirmedAction(action);
  }

  /// Executes an action that has been approved or confirmed safe.
  Future<ActionResult> executeConfirmedAction(PhoneAction action) async {
    try {
      switch (action.type) {
        case ActionType.callContact:
          final number = action.params['phoneNumber'] as String? ?? '';
          final success = await _channel.invokeMethod<bool>('dialNumber', {'phoneNumber': number});
          return ActionResult(
            success: success ?? false,
            message: 'Opened dialer with number $number',
            action: action,
          );

        case ActionType.sendWhatsApp:
          final number = action.params['phoneNumber'] as String? ?? '';
          final message = action.params['message'] as String? ?? '';
          final success = await _channel.invokeMethod<bool>(
            'composeWhatsAppMessage',
            {'phoneNumber': number, 'message': message},
          );
          return ActionResult(
            success: success ?? false,
            message: 'Opened WhatsApp composition for $number',
            action: action,
          );

        case ActionType.openApp:
          final appName = action.params['appName'] as String? ?? '';
          final pkg = action.params['packageName'] as String? ?? '';

          // 1. Dynamic resolution via native PackageManager
          if (appName.isNotEmpty) {
            final dynamicResult = await launchAppByName(appName);
            if (dynamicResult['success'] == true) {
              final launchedPkg = dynamicResult['packageName'] ?? pkg;
              final launchedName = dynamicResult['appName'] ?? appName;
              return ActionResult(
                success: true,
                message: 'Launched $launchedName ($launchedPkg)',
                action: action,
                data: dynamicResult,
              );
            }
          }

          // 2. Fallback to direct package launch if package provided
          if (pkg.isNotEmpty) {
            final success = await _channel.invokeMethod<bool>('launchApp', {'packageName': pkg});
            if (success == true) {
              return ActionResult(
                success: true,
                message: 'Launched application ($pkg)',
                action: action,
              );
            }
          }

          return ActionResult(
            success: false,
            message: 'Could not find or launch application for "$appName"',
            action: action,
          );

        case ActionType.readScreen:
          final screenData = await _channel.invokeMapMethod<String, dynamic>('getCurrentScreenContext');
          final text = screenData?['screenText'] as String? ?? '';
          final isEnabled = screenData?['isAccessibilityEnabled'] as bool? ?? false;
          return ActionResult(
            success: isEnabled,
            message: isEnabled ? 'Successfully read screen content' : 'Accessibility Service is disabled',
            action: action,
            data: text,
          );

        case ActionType.globalNav:
          final navAction = action.params['action'] as String? ?? 'back';
          final success = await _channel.invokeMethod<bool>('performGlobalAction', {'action': navAction});
          return ActionResult(
            success: success ?? false,
            message: 'Performed global action: $navAction',
            action: action,
          );

        case ActionType.clickUi:
          final target = action.params['targetText'] as String? ?? '';
          final res = await clickUiElement(target);
          final success = res['success'] == true;
          final msg = res['message']?.toString() ??
              (success ? 'Clicked on "$target"' : 'Could not click on "$target"');
          return ActionResult(
            success: success,
            message: msg,
            action: action,
            data: res,
          );

        case ActionType.typeText:
          final text = action.params['text'] as String? ?? '';
          final hint = action.params['targetHint'] as String?;
          final res = await typeUiText(text, targetHint: hint);
          final success = res['success'] == true;
          final msg = res['message']?.toString() ??
              (success ? 'Typed "$text"' : 'Failed to type text');
          return ActionResult(
            success: success,
            message: msg,
            action: action,
            data: res,
          );

        case ActionType.scrollUi:
          final direction = action.params['direction'] as String? ?? 'down';
          final res = await scrollUi(direction);
          final success = res['success'] == true;
          final msg = success ? 'Scrolled screen $direction' : 'Failed to scroll screen $direction';
          return ActionResult(
            success: success,
            message: msg,
            action: action,
            data: res,
          );

        case ActionType.inspectUi:
          final tree = await inspectUiTree();
          return ActionResult(
            success: true,
            message: 'Inspected ${tree.length} interactive UI elements',
            action: action,
            data: tree,
          );

        case ActionType.openFile:
          final uri = (action.params['uri'] ?? action.params['fileUri'] ?? '').toString();
          final mime = action.params['mimeType'] as String?;
          final res = await openFileUri(uri, mimeType: mime);
          final success = res['success'] == true;
          return ActionResult(
            success: success,
            message: res['message']?.toString() ?? (success ? 'Opened file' : 'Failed to open file'),
            action: action,
            data: res,
          );
      }
    } catch (e) {
      return ActionResult(
        success: false,
        message: 'Action execution failed: $e',
        action: action,
      );
    }
  }

  /// Opens a local image or PDF document URI directly in the phone's native viewer.
  Future<Map<String, dynamic>> openFileUri(String uri, {String? mimeType}) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'openFileUri',
        {'uri': uri, 'mimeType': ?mimeType},
      );
      return res ?? {'success': false, 'error': 'No response from native channel'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Clicks a visible UI element matching [targetText] via Accessibility Service.
  Future<Map<String, dynamic>> clickUiElement(String targetText) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'clickUiElement',
        {'targetText': targetText},
      );
      return res ?? {'success': false, 'error': 'No response from native channel'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Injects text into a focused or hinted editable input field via Accessibility Service.
  Future<Map<String, dynamic>> typeUiText(String text, {String? targetHint}) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'typeUiText',
        {'text': text, 'targetHint': ?targetHint},
      );
      return res ?? {'success': false, 'error': 'No response from native channel'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Scrolls the active window in the specified [direction] ('down', 'up', 'left', 'right').
  Future<Map<String, dynamic>> scrollUi(String direction) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'scrollUi',
        {'direction': direction},
      );
      return res ?? {'success': false, 'error': 'No response from native channel'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Retrieves structured interactive UI elements from the active window.
  Future<List<Map<String, dynamic>>> inspectUiTree() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('inspectUiTree');
      if (list == null) return [];
      return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    } catch (e) {
      debugPrint('Error inspecting UI tree: $e');
      return [];
    }
  }

  /// Retrieves all launchable installed apps on the device dynamically via PackageManager.
  Future<List<Map<String, String>>> getInstalledApps() async {
    try {
      final list = await _channel.invokeListMethod<dynamic>('getInstalledApps');
      if (list == null) return [];
      return list.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return {
          'appName': (map['appName'] ?? '').toString(),
          'packageName': (map['packageName'] ?? '').toString(),
        };
      }).toList();
    } catch (e) {
      debugPrint('Error getting installed apps: $e');
      return [];
    }
  }

  /// Dynamically resolves and launches an installed app by natural query name.
  Future<Map<String, dynamic>> launchAppByName(String query) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'launchAppByName',
        {'name': query},
      );
      return res ?? {'success': false, 'error': 'No response from native channel'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Checks if Accessibility Service is enabled in Android Settings.
  Future<bool> checkAccessibilityEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('checkAccessibilityEnabled');
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Accessibility Settings screen.
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<bool>('openAccessibilitySettings');
    } catch (_) {}
  }
}
