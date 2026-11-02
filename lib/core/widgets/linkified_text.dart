import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// `https://…` runs inside plain text. Only https: anything else stays text.
final _httpsLink = RegExp(r'https://[^\s<>"]+', caseSensitive: false);

/// Trailing punctuation that ends a sentence, not the link.
final _trailing = RegExp(r'[.,!?؛،:)\]»"]+$');

/// One run of [splitLinks]: plain text or a link.
typedef TextRun = ({String text, bool isLink});

/// Splits [text] into plain runs and https links (never HTML).
List<TextRun> splitLinks(String text) {
  final runs = <TextRun>[];
  var at = 0;
  for (final m in _httpsLink.allMatches(text)) {
    var link = m.group(0)!;
    final tail = _trailing.firstMatch(link)?.group(0) ?? '';
    link = link.substring(0, link.length - tail.length);
    if (m.start > at) {
      runs.add((text: text.substring(at, m.start), isLink: false));
    }
    if (link.length > 'https://'.length) {
      runs.add((text: link, isLink: true));
    } else {
      runs.add((text: link, isLink: false));
    }
    at = m.start + link.length;
  }
  if (at < text.length) runs.add((text: text.substring(at), isLink: false));
  return runs;
}

/// Plain text with tappable https links, clamped to [maxLines] behind
/// «عرض المزيد» when long.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    required this.onLink,
    this.style,
    this.maxLines = 8,
  });

  final String text;
  final ValueChanged<String> onLink;
  final TextStyle? style;
  final int maxLines;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  bool _expanded = false;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TextSpan _span(TextStyle base, Color linkColor) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    return TextSpan(
      style: base,
      children: [
        for (final run in splitLinks(widget.text))
          if (run.isLink)
            TextSpan(
              text: run.text,
              style: TextStyle(
                color: linkColor,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
              recognizer:
                  (TapGestureRecognizer()
                        ..onTap = () => widget.onLink(run.text))
                      .also(_recognizers.add),
            )
          else
            TextSpan(text: run.text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base =
        widget.style ??
        Theme.of(context).textTheme.bodyLarge ??
        const TextStyle();
    final span = _span(base, scheme.primary);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              span,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.fade,
            ),
            if (overflows && !_expanded)
              InkWell(
                onTap: () => setState(() => _expanded = true),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'عرض المزيد',
                    style: base.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

extension<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
