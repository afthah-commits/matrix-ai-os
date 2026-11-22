import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix_ai_os/features/ai_brain/data/tools/live_web_search_tool.dart';

void main() {
  group('LiveWebSearchTool Tests', () {
    test('Empty query returns empty results immediately without network call', () async {
      final tool = LiveWebSearchTool();
      final result = await tool.search('');

      expect(result.items, isEmpty);
      expect(result.isSuccess, isFalse);
    });

    test('Parses DuckDuckGo Instant Answer API JSON response correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.duckduckgo.com') {
          return http.Response(
            '''
            {
              "AbstractText": "Flutter is an open-source UI software development kit created by Google.",
              "AbstractSource": "Wikipedia",
              "AbstractURL": "https://en.wikipedia.org/wiki/Flutter_(software)",
              "Heading": "Flutter",
              "RelatedTopics": [
                {
                  "Text": "Dart - A programming language designed for client development.",
                  "FirstURL": "https://dart.dev"
                }
              ]
            }
            ''',
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final tool = LiveWebSearchTool(client: mockClient);
      final result = await tool.search('what is flutter');

      expect(result.isSuccess, isTrue);
      expect(result.source, equals('ddg_instant_answer'));
      expect(result.items.length, equals(2));
      expect(result.items.first.title, contains('Wikipedia'));
      expect(result.items.first.snippet, contains('open-source UI software'));
      expect(result.items.first.url, contains('wikipedia.org'));

      final formatted = result.formatForContext();
      expect(formatted, contains('LIVE WEB SEARCH RESULTS'));
      expect(formatted, contains('Flutter is an open-source'));
    });

    test('Falls back to HTML Lite scraper when Instant Answer is empty', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'api.duckduckgo.com') {
          // Empty instant answer
          return http.Response('{"AbstractText": "", "RelatedTopics": []}', 200);
        } else if (request.url.host == 'html.duckduckgo.com') {
          return http.Response(
            '''
            <html>
              <body>
                <div class="results">
                  <div class="result">
                    <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fnews.google.com&rut=...">Tech News Today</a>
                    <a class="result__snippet" href="#">Breaking developments in on-device AI and Flutter OS frameworks.</a>
                  </div>
                </div>
              </body>
            </html>
            ''',
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final tool = LiveWebSearchTool(client: mockClient);
      final result = await tool.search('latest tech news');

      expect(result.isSuccess, isTrue);
      expect(result.source, equals('ddg_html_lite'));
      expect(result.items.length, equals(1));
      expect(result.items.first.title, equals('Tech News Today'));
      expect(result.items.first.snippet, contains('Breaking developments in on-device AI'));
      expect(result.items.first.url, equals('https://news.google.com'));
    });

    test('Handles network failure / offline status gracefully', () async {
      final mockClient = MockClient((request) async {
        throw Exception('No network connection');
      });

      final tool = LiveWebSearchTool(client: mockClient);
      final result = await tool.search('champions league score');

      expect(result.isSuccess, isFalse);
      expect(result.items, isEmpty);
      expect(result.errorMessage, contains('unavailable or device is offline'));
    });
  });
}
