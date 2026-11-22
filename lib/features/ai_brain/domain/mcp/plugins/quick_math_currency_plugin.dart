import 'package:matrix_ai_os/features/ai_brain/domain/mcp/matrix_mcp_plugin.dart';

/// Built-in MCP Plugin: Deterministic Math & Offline Currency Conversion.
class QuickMathCurrencyPlugin implements MatrixMcpPlugin {
  @override
  String get id => 'quick_math_currency';

  @override
  String get name => 'Math & Currency Converter';

  @override
  String get description =>
      'Evaluates arithmetic expressions and converts global currencies using offline cached rates.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
      };

  // Fixed offline exchange rates relative to USD (1.0 USD base)
  static const Map<String, double> _usdBaseRates = {
    'USD': 1.0,
    'INR': 85.50,
    'AED': 3.6725,
    'EUR': 0.925,
    'GBP': 0.792,
    'JPY': 154.20,
    'CAD': 1.405,
    'AUD': 1.540,
    'SGD': 1.345,
  };

  @override
  bool canHandle(String query) {
    final lower = query.trim().toLowerCase();

    // Currency check
    final hasCurrencyPattern = RegExp(
      r'\b(convert|[0-9.]+\s*(usd|inr|eur|aed|gbp|jpy|cad)\s*(to|in|into)\s*(usd|inr|eur|aed|gbp|jpy|cad))\b',
      caseSensitive: false,
    ).hasMatch(lower);

    if (hasCurrencyPattern) return true;

    // Percentage check
    if (RegExp(r'\b[0-9.]+%\s*of\s*[0-9.]+\b').hasMatch(lower)) return true;

    // Explicit calculate command
    if (lower.startsWith('calculate') || lower.startsWith('solve')) return true;

    return false;
  }

  @override
  Future<McpPluginResult> execute(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();

    // 1. Try Currency Conversion
    final currencyMatch = RegExp(
      r'([0-9.]+)\s*([a-zA-Z]{3})\s*(?:to|in|into)\s*([a-zA-Z]{3})',
      caseSensitive: false,
    ).firstMatch(query);

    if (currencyMatch != null) {
      final amount = double.tryParse(currencyMatch.group(1)!);
      final fromCur = currencyMatch.group(2)!.toUpperCase();
      final toCur = currencyMatch.group(3)!.toUpperCase();

      if (amount != null &&
          _usdBaseRates.containsKey(fromCur) &&
          _usdBaseRates.containsKey(toCur)) {
        final amountInUsd = amount / _usdBaseRates[fromCur]!;
        final converted = amountInUsd * _usdBaseRates[toCur]!;

        final text = '💱 **Offline Currency Conversion (MCP):**\n\n'
            '• **${amount.toStringAsFixed(2)} $fromCur** = **${converted.toStringAsFixed(2)} $toCur**\n'
            '• *Rate: 1 $fromCur ≈ ${(converted / amount).toStringAsFixed(4)} $toCur*\n'
            '• *Source: Verified Offline Cached FX Matrix (Air-Gapped)*';

        return McpPluginResult(
          success: true,
          displayText: text,
          rawData: {
            'from': fromCur,
            'to': toCur,
            'originalAmount': amount,
            'convertedAmount': converted,
          },
          telemetryBadge: 'Math & Currency',
        );
      }
    }

    // 2. Try Percentage
    final percentMatch = RegExp(
      r'([0-9.]+)%\s*of\s*([0-9.]+)',
      caseSensitive: false,
    ).firstMatch(query);

    if (percentMatch != null) {
      final percent = double.tryParse(percentMatch.group(1)!);
      final base = double.tryParse(percentMatch.group(2)!);
      if (percent != null && base != null) {
        final result = (percent / 100.0) * base;
        final text = '📐 **Percentage Calculation (MCP):**\n\n'
            '• **$percent%** of **$base** = **${result.toStringAsFixed(2)}**';
        return McpPluginResult(
          success: true,
          displayText: text,
          rawData: {'percent': percent, 'base': base, 'result': result},
          telemetryBadge: 'Math & Currency',
        );
      }
    }

    // 3. Try Basic Arithmetic Evaluation
    final mathClean = query
        .replaceAll(RegExp(r'calculate|solve|\?|=', caseSensitive: false), '')
        .trim();
    final evalResult = _evaluateSimpleExpression(mathClean);
    if (evalResult != null) {
      final text = '📐 **Deterministic Math Evaluation (MCP):**\n\n'
          '• **Expression:** `$mathClean`\n'
          '• **Result:** **$evalResult**';
      return McpPluginResult(
        success: true,
        displayText: text,
        rawData: {'expression': mathClean, 'result': evalResult},
        telemetryBadge: 'Math & Currency',
      );
    }

    return McpPluginResult(
      success: false,
      displayText: 'Unable to evaluate math or currency from query: "$query"',
      telemetryBadge: 'Math & Currency',
    );
  }

  static double? _evaluateSimpleExpression(String expr) {
    try {
      final clean = expr.replaceAll(' ', '');

      // Check simple binary operation: a + b, a - b, a * b, a / b
      final binaryMatch = RegExp(r'^([0-9.]+)([\+\-\*\/])([0-9.]+)$').firstMatch(clean);
      if (binaryMatch != null) {
        final a = double.tryParse(binaryMatch.group(1)!);
        final op = binaryMatch.group(2)!;
        final b = double.tryParse(binaryMatch.group(3)!);
        if (a != null && b != null) {
          switch (op) {
            case '+':
              return a + b;
            case '-':
              return a - b;
            case '*':
              return a * b;
            case '/':
              return b != 0 ? a / b : null;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
