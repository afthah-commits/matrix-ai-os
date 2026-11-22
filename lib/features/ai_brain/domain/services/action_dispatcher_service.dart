import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The categories of device actions supported by Matrix AI OS.
enum ActionType {
  callContact('Call Contact', isSensitive: true),
  sendWhatsApp('Send WhatsApp', isSensitive: true),
  openApp('Open Application', isSensitive: false),
  readScreen('Read Foreground Screen', isSensitive: false),
  globalNav('System Navigation', isSensitive: false);

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
/// execute without explicit user approval in the UI.
class ActionDispatcherService {
  final MethodChannel _channel;

  static const String channelName = 'com.matrixai.os/action_executor';

  ActionDispatcherService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  // Common app package mappings
  static const Map<String, String> _appPackages = {
    'whatsapp': 'com.whatsapp',
    'youtube': 'com.google.android.youtube',
    'chrome': 'com.android.chrome',
    'settings': 'com.android.settings',
    'maps': 'com.google.android.apps.maps',
    'camera': 'com.google.android.GoogleCamera',
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

    // 5. Open Application
    // E.g.: "Open WhatsApp", "Launch YouTube", "Open Settings"
    final openAppRegex = RegExp(r'(?:open|launch)\s+([a-zA-Z0-9_\s]+)', caseSensitive: false);
    final openMatch = openAppRegex.firstMatch(text);
    if (openMatch != null) {
      final appName = openMatch.group(1)!.trim().toLowerCase();
      final pkg = _appPackages[appName] ?? appName;
      return PhoneAction(
        id: 'act_$nowMs',
        type: ActionType.openApp,
        params: {'packageName': pkg, 'appName': appName},
        description: 'Open application "$appName"',
        isSensitive: false,
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
          final pkg = action.params['packageName'] as String? ?? '';
          final success = await _channel.invokeMethod<bool>('launchApp', {'packageName': pkg});
          return ActionResult(
            success: success ?? false,
            message: (success ?? false) ? 'Launched application' : 'Failed to launch application',
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
      }
    } catch (e) {
      return ActionResult(
        success: false,
        message: 'Action execution failed: $e',
        action: action,
      );
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
