import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itaaleem/core/theme/app_theme.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_screen.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_failures.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool _ours(String? url) =>
    url != null && Uri.parse(url).host == 'demo.example.com';

WebResourceError _err({
  int code = -1004,
  bool? main = true,
  String? url = 'https://demo.example.com/app',
  WebResourceErrorType? type,
}) => WebResourceError(
  errorCode: code,
  description: 'x',
  isForMainFrame: main,
  url: url,
  errorType: type,
);

void main() {
  group('classifyLoadError', () {
    test('iOS content process terminated -> reload, not fallback', () {
      expect(
        classifyLoadError(
          _err(
            code: 2,
            url: null,
            type: WebResourceErrorType.webContentProcessTerminated,
          ),
          onOrigin: _ours,
        ),
        SmartLoadError.processGone,
      );
    });

    test('sub-resources (image, font, iframe) are ignored', () {
      expect(
        classifyLoadError(_err(main: false), onOrigin: _ours),
        SmartLoadError.ignore,
      );
      expect(
        classifyLoadError(_err(main: null), onOrigin: _ours),
        SmartLoadError.ignore,
      );
    });

    test('other sites (YouTube) and cancelled loads are ignored', () {
      expect(
        classifyLoadError(
          _err(url: 'https://www.youtube.com/embed/x'),
          onOrigin: _ours,
        ),
        SmartLoadError.ignore,
      );
      expect(
        classifyLoadError(_err(code: -999), onOrigin: _ours),
        SmartLoadError.ignore,
      );
      expect(
        classifyLoadError(_err(code: -3), onOrigin: _ours),
        SmartLoadError.ignore,
      );
    });

    test('the smart UI main page failing counts', () {
      expect(
        classifyLoadError(_err(), onOrigin: _ours),
        SmartLoadError.pageFailed,
      );
    });
  });

  group('isPageHttpError: only the smart UI pages count', () {
    const cases = <(String, int, bool)>[
      ('https://demo.example.com/app', 500, true),
      ('https://demo.example.com/app/', 500, true),
      ('https://demo.example.com/app/lesson/5', 404, true),
      ('https://demo.example.com/app?x=1', 502, true),
      ('https://demo.example.com/app/handoff', 419, true),
      ('https://demo.example.com/app/api/profile', 500, false),
      ('https://demo.example.com/app/assets/index-abc.js', 404, false),
      ('https://demo.example.com/app/x.png', 404, false),
      ('https://demo.example.com/app/f.WOFF2', 404, false),
      ('https://demo.example.com/app/doc.pdf', 404, false),
      ('https://demo.example.com/app/data.json', 500, false),
      ('https://demo.example.com/apps', 500, false),
      ('https://other.example.com/app', 500, false),
      ('https://demo.example.com/app', 200, false),
    ];
    for (final (url, status, counts) in cases) {
      test('$url $status -> ${counts ? 'counts' : 'ignored'}', () {
        final uri = Uri.parse(url);
        expect(isPageHttpError(uri, status, onOrigin: _ours(url)), counts);
      });
    }
  });

  group('isPageHttpError (legacy cases)', () {
    test('only the app documents', () {
      final app = Uri.parse('https://demo.example.com/app/handoff');
      final pdf = Uri.parse('https://demo.example.com/storage/a.pdf');
      expect(isPageHttpError(app, 500, onOrigin: true), isTrue);
      expect(isPageHttpError(app, 200, onOrigin: true), isFalse);
      expect(isPageHttpError(app, 500, onOrigin: false), isFalse);
      expect(isPageHttpError(pdf, 404, onOrigin: true), isFalse);
    });
  });

  group('SmartFailureTracker', () {
    test('falls back on the second failure in a row, and logs why', () {
      final logs = <String>[];
      final t = SmartFailureTracker(log: logs.add);
      expect(t.fail('HTTP 502 /app'), isFalse);
      expect(t.fail('load error -1001'), isTrue);
      expect(logs.first, contains('HTTP 502 /app'));
      expect(logs.last, contains('falling back'));
    });

    test('a successful load resets the count', () {
      final t = SmartFailureTracker(log: (_) {});
      t.fail('a');
      t.reset();
      expect(t.fail('b'), isFalse);
    });
  });

  group('ProcessGoneLimiter', () {
    late DateTime clock;
    late List<String> logs;
    late ProcessGoneLimiter limiter;
    setUp(() {
      clock = DateTime(2026, 11, 16, 12);
      logs = [];
      limiter = ProcessGoneLimiter(now: () => clock, log: logs.add);
    });

    test('3 terminations reload, the 4th within 2 minutes shows the error', () {
      for (var i = 0; i < 3; i++) {
        expect(limiter.record(), isTrue);
        clock = clock.add(const Duration(seconds: 20));
      }
      expect(limiter.record(), isFalse);
      expect(logs, [
        '[SmartShell] process terminated 1/3 -> reload',
        '[SmartShell] process terminated 2/3 -> reload',
        '[SmartShell] process terminated 3/3 -> reload',
        '[SmartShell] process terminated 4/3 -> error screen',
      ]);
    });

    test('terminations older than 120 s drop out of the window', () {
      for (var i = 0; i < 3; i++) {
        limiter.record();
      }
      clock = clock.add(const Duration(seconds: 120));
      expect(limiter.record(), isTrue);
      expect(limiter.count, 1);
    });

    test('3 terminations, ready 30 s, then a termination -> 1/3', () {
      for (var i = 0; i < 3; i++) {
        limiter.record();
      }
      limiter.markReady();
      clock = clock.add(const Duration(seconds: 30));
      expect(limiter.record(), isTrue);
      expect(logs.last, '[SmartShell] process terminated 1/3 -> reload');
    });

    test('3 terminations, ready 29 s, then a termination -> 4/3, error', () {
      for (var i = 0; i < 3; i++) {
        limiter.record();
      }
      limiter.markReady();
      clock = clock.add(const Duration(seconds: 29));
      expect(limiter.record(), isFalse);
      expect(logs.last, '[SmartShell] process terminated 4/3 -> error screen');
    });

    test('retry (reset) starts counting from zero', () {
      for (var i = 0; i < 4; i++) {
        limiter.record();
      }
      limiter.reset();
      expect(limiter.record(), isTrue);
      expect(logs.last, contains('1/3 -> reload'));
    });
  });

  testWidgets('error screen: text and a retry button', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(children: [SmartLoadErrorView(onRetry: () => retried++)]),
        ),
      ),
    );
    expect(find.text('حصلت مشكلة في تحميل الصفحة'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retried, 1);
  });
}
