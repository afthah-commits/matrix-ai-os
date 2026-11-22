import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Individual search result snippet.
@immutable
class WebSearchItem {
  final String title;
  final String snippet;
  final String url;

  const WebSearchItem({
    required this.title,
    required this.snippet,
    required this.url,
  });

  @override
  String toString() => 'WebSearchItem(title: $title, snippet: $snippet, url: $url)';
}

/// Comprehensive search result returned to the RAG pipeline.
@immutable
class WebSearchResult {
  final String query;
  final List<WebSearchItem> items;
  final String source; // e.g., 'ddg_instant_answer', 'ddg_html_lite', or 'fallback'
  final String? errorMessage;

  const WebSearchResult({
    required this.query,
    required this.items,
    required this.source,
    this.errorMessage,
  });

  bool get isSuccess => items.isNotEmpty;

  /// Formats search results into a clean context block for LLM ingestion.
  String formatForContext() {
    if (items.isEmpty) {
      return 'No live web results found.';
    }

    final buffer = StringBuffer();
    buffer.writeln('=== LIVE WEB SEARCH RESULTS (Source: DuckDuckGo) ===');
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      buffer.writeln('[${i + 1}] ${item.title}');
      buffer.writeln('Snippet: ${item.snippet}');
      if (item.url.isNotEmpty) {
        buffer.writeln('Source URL: ${item.url}');
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }
}

/// 100% Free, zero-API-key Live Web Search Tool.
///
/// Queries DuckDuckGo Instant Answer API and HTML Lite parser
/// with graceful fallback, timeout protection, and zero heavy SDKs.
class LiveWebSearchTool {
  final http.Client _client;
  final Duration timeout;

  LiveWebSearchTool({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  static const String _ddgApiBase = 'https://api.duckduckgo.com/';
  static const String _ddgHtmlBase = 'https://html.duckduckgo.com/html/';

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; MatrixAI-OS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Searches the web for [query] and returns structured web snippets.
  Future<WebSearchResult> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return const WebSearchResult(
        query: '',
        items: [],
        source: 'empty_query',
      );
    }

    // Step 1: Attempt Instant Answer API
    try {
      final instantResult = await _searchInstantAnswer(cleanQuery);
      if (instantResult.items.isNotEmpty) {
        return instantResult;
      }
    } catch (e) {
      debugPrint('[LiveWebSearchTool] Instant answer query failed: $e');
    }

    // Step 2: Fallback to DuckDuckGo HTML Lite scraping
    try {
      final htmlResult = await _searchHtmlLite(cleanQuery);
      if (htmlResult.items.isNotEmpty) {
        return htmlResult;
      }
    } catch (e) {
      debugPrint('[LiveWebSearchTool] HTML Lite query failed: $e');
    }

    return WebSearchResult(
      query: cleanQuery,
      items: const [],
      source: 'unavailable',
      errorMessage: 'Live search currently unavailable or device is offline.',
    );
  }

  /// Queries DuckDuckGo Instant Answer JSON API
  Future<WebSearchResult> _searchInstantAnswer(String query) async {
    final uri = Uri.parse(_ddgApiBase).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'no_html': '1',
      'skip_disambig': '1',
    });

    final response = await _client.get(uri, headers: _headers).timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = <WebSearchItem>[];

      // Check AbstractText
      final abstractText = data['AbstractText'] as String? ?? '';
      final abstractSource = data['AbstractSource'] as String? ?? '';
      final abstractUrl = data['AbstractURL'] as String? ?? '';

      if (abstractText.isNotEmpty) {
        items.add(
          WebSearchItem(
            title: abstractSource.isNotEmpty ? 'Instant Answer ($abstractSource)' : 'Instant Answer',
            snippet: abstractText,
            url: abstractUrl,
          ),
        );
      }

      // Check RelatedTopics
      final relatedTopics = data['RelatedTopics'] as List<dynamic>? ?? [];
      for (final topic in relatedTopics) {
        if (topic is Map<String, dynamic>) {
          final text = topic['Text'] as String? ?? '';
          final firstUrl = topic['FirstURL'] as String? ?? '';
          if (text.isNotEmpty) {
            items.add(
              WebSearchItem(
                title: text.split(' - ').first,
                snippet: text,
                url: firstUrl,
              ),
            );
          }
        }
        if (items.length >= 4) break;
      }

      return WebSearchResult(
        query: query,
        items: items,
        source: 'ddg_instant_answer',
      );
    }

    return WebSearchResult(
      query: query,
      items: const [],
      source: 'ddg_instant_answer',
      errorMessage: 'Status code ${response.statusCode}',
    );
  }

  /// Queries DuckDuckGo HTML Lite endpoint and parses result snippets
  Future<WebSearchResult> _searchHtmlLite(String query) async {
    final uri = Uri.parse(_ddgHtmlBase).replace(queryParameters: {
      'q': query,
    });

    final response = await _client.get(uri, headers: _headers).timeout(timeout);

    if (response.statusCode == 200) {
      final html = response.body;
      final items = _parseHtmlSnippets(html);

      return WebSearchResult(
        query: query,
        items: items,
        source: 'ddg_html_lite',
      );
    }

    return WebSearchResult(
      query: query,
      items: const [],
      source: 'ddg_html_lite',
      errorMessage: 'HTML endpoint responded with ${response.statusCode}',
    );
  }

  /// Pure regex/string HTML parser to extract snippets without heavy DOM dependencies
  List<WebSearchItem> _parseHtmlSnippets(String html) {
    final items = <WebSearchItem>[];

    // Regex matching result snippets in DuckDuckGo HTML
    // E.g.: <a class="result__snippet[^"]*"[^>]*>(.*?)</a>
    // or <div class="result__snippet[^"]*"[^>]*>(.*?)</div>
    final resultBlockRegex = RegExp(
      r'class="result__snippet[^"]*"[^>]*>([\s\S]*?)<\/(?:a|div)>',
      caseSensitive: false,
    );

    final titleRegex = RegExp(
      r'class="result__a"[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>',
      caseSensitive: false,
    );

    final titleMatches = titleRegex.allMatches(html).toList();
    final snippetMatches = resultBlockRegex.allMatches(html).toList();

    final count = titleMatches.length < snippetMatches.length
        ? titleMatches.length
        : snippetMatches.length;

    for (int i = 0; i < count && i < 5; i++) {
      final titleMatch = titleMatches[i];
      final snippetMatch = snippetMatches[i];

      final rawUrl = titleMatch.group(1) ?? '';
      final rawTitle = _cleanHtml(titleMatch.group(2) ?? '');
      final rawSnippet = _cleanHtml(snippetMatch.group(1) ?? '');

      if (rawSnippet.isNotEmpty && rawTitle.isNotEmpty) {
        items.add(
          WebSearchItem(
            title: rawTitle,
            snippet: rawSnippet,
            url: _cleanDdgUrl(rawUrl),
          ),
        );
      }
    }

    return items;
  }

  /// Decodes HTML entities and strips HTML tags
  static String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Extracts actual target URL from DDG redirect url (uddg=...)
  static String _cleanDdgUrl(String ddgUrl) {
    try {
      if (ddgUrl.contains('uddg=')) {
        final uri = Uri.parse(ddgUrl);
        final target = uri.queryParameters['uddg'];
        if (target != null && target.isNotEmpty) {
          return target;
        }
      }
    } catch (_) {}
    return ddgUrl;
  }
}
