import 'package:flutter/foundation.dart';

/// Result returned from an MCP (Model Context Protocol) tool execution.
@immutable
class McpPluginResult {
  final bool success;
  final String displayText;
  final dynamic rawData;
  final String telemetryBadge; // e.g. "Device Health", "Math & Currency", "Life Digest"

  const McpPluginResult({
    required this.success,
    required this.displayText,
    this.rawData,
    required this.telemetryBadge,
  });

  @override
  String toString() => 'McpPluginResult(success: $success, badge: $telemetryBadge)';
}

/// Abstract Interface for Matrix AI OS MCP (Model Context Protocol) Plugins.
///
/// Enables modular, extensible tools to be registered, discovered,
/// and invoked deterministically by the AI brain.
abstract class MatrixMcpPlugin {
  String get id;
  String get name;
  String get description;
  Map<String, dynamic> get inputSchema;

  /// Returns true if this plugin can resolve or execute [query].
  bool canHandle(String query);

  /// Executes the plugin tool using [args] or the raw query.
  Future<McpPluginResult> execute(Map<String, dynamic> args);
}
