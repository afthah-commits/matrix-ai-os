import 'package:flutter/foundation.dart';
import 'package:matrix_ai_os/features/ai_brain/domain/mcp/matrix_mcp_plugin.dart';

/// Central Registry managing discovery, state, and routing for MCP Plugins.
class McpPluginRegistry extends ChangeNotifier {
  final Map<String, MatrixMcpPlugin> _plugins = {};
  final Map<String, bool> _enabledState = {};

  McpPluginRegistry({List<MatrixMcpPlugin>? initialPlugins}) {
    if (initialPlugins != null) {
      for (final p in initialPlugins) {
        registerPlugin(p);
      }
    }
  }

  /// Registers an MCP plugin into the system.
  void registerPlugin(MatrixMcpPlugin plugin, {bool enabled = true}) {
    _plugins[plugin.id] = plugin;
    _enabledState[plugin.id] = enabled;
    notifyListeners();
  }

  /// Unregisters an MCP plugin by [id].
  void unregisterPlugin(String id) {
    _plugins.remove(id);
    _enabledState.remove(id);
    notifyListeners();
  }

  /// Checks if a plugin is currently enabled.
  bool isPluginEnabled(String id) {
    return _enabledState[id] ?? true;
  }

  /// Toggles enablement of a plugin by [id].
  void setPluginEnabled(String id, bool enabled) {
    if (_plugins.containsKey(id)) {
      _enabledState[id] = enabled;
      notifyListeners();
    }
  }

  /// Returns all registered plugins.
  List<MatrixMcpPlugin> getAllPlugins() => _plugins.values.toList();

  /// Returns only currently enabled plugins.
  List<MatrixMcpPlugin> getEnabledPlugins() {
    return _plugins.values.where((p) => isPluginEnabled(p.id)).toList();
  }

  /// Finds the first enabled plugin capable of handling [query].
  MatrixMcpPlugin? findMatchingPlugin(String query) {
    for (final plugin in getEnabledPlugins()) {
      if (plugin.canHandle(query)) {
        return plugin;
      }
    }
    return null;
  }

  /// Executes an appropriate MCP tool if [query] matches an enabled plugin.
  Future<McpPluginResult?> processIfMatching(String query) async {
    final plugin = findMatchingPlugin(query);
    if (plugin == null) return null;

    try {
      return await plugin.execute({'query': query});
    } catch (e) {
      debugPrint('[McpPluginRegistry] Plugin ${plugin.id} execution failed: $e');
      return McpPluginResult(
        success: false,
        displayText: 'Error executing MCP plugin ${plugin.name}: $e',
        telemetryBadge: plugin.name,
      );
    }
  }
}
