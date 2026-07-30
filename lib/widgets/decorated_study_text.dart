import 'package:flutter/material.dart';

enum StudyTextDecoration {
  plain,
  bold,
  highlight,
  underline,
  heading,
}

class StudyTextSegment {
  const StudyTextSegment({
    required this.text,
    required this.decoration,
  });

  final String text;
  final StudyTextDecoration decoration;
}

class ParsedStudyText {
  const ParsedStudyText({
    required this.segments,
  });

  final List<StudyTextSegment> segments;

  String get plainText => segments.map((segment) => segment.text).join();
}

class StudyTextParser {
  const StudyTextParser();

  static final RegExp _headingPattern = RegExp(r'^【[^【】\r\n]+】$');

  static const List<_DecorationToken> _tokens = <_DecorationToken>[
    _DecorationToken('**', StudyTextDecoration.bold),
    _DecorationToken('==', StudyTextDecoration.highlight),
    _DecorationToken('__', StudyTextDecoration.underline),
  ];

  ParsedStudyText parse(String source) {
    final segments = <StudyTextSegment>[];
    var lineStart = 0;
    var index = 0;

    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      final isCarriageReturn = codeUnit == 0x0D;
      final isLineFeed = codeUnit == 0x0A;

      if (!isCarriageReturn && !isLineFeed) {
        index += 1;
        continue;
      }

      _parseLine(
        source.substring(lineStart, index),
        segments,
      );

      var lineBreakEnd = index + 1;
      if (isCarriageReturn &&
          lineBreakEnd < source.length &&
          source.codeUnitAt(lineBreakEnd) == 0x0A) {
        lineBreakEnd += 1;
      }

      _appendSegment(
        segments,
        source.substring(index, lineBreakEnd),
        StudyTextDecoration.plain,
      );
      index = lineBreakEnd;
      lineStart = lineBreakEnd;
    }

    _parseLine(source.substring(lineStart), segments);

    return ParsedStudyText(
      segments: List<StudyTextSegment>.unmodifiable(segments),
    );
  }

  void _parseLine(
    String line,
    List<StudyTextSegment> segments,
  ) {
    if (line.isEmpty) {
      return;
    }

    if (_headingPattern.hasMatch(line)) {
      _appendSegment(
        segments,
        line,
        StudyTextDecoration.heading,
      );
      return;
    }

    var plainStart = 0;
    var index = 0;

    while (index < line.length) {
      final token = _tokenAt(line, index);

      if (token == null) {
        index += 1;
        continue;
      }

      final contentStart = index + token.marker.length;
      final closingIndex = line.indexOf(token.marker, contentStart);

      if (closingIndex == -1) {
        index = contentStart;
        continue;
      }

      if (closingIndex == contentStart) {
        index = closingIndex + token.marker.length;
        continue;
      }

      _appendSegment(
        segments,
        line.substring(plainStart, index),
        StudyTextDecoration.plain,
      );
      _appendSegment(
        segments,
        line.substring(contentStart, closingIndex),
        token.decoration,
      );

      index = closingIndex + token.marker.length;
      plainStart = index;
    }

    _appendSegment(
      segments,
      line.substring(plainStart),
      StudyTextDecoration.plain,
    );
  }

  _DecorationToken? _tokenAt(String source, int index) {
    for (final token in _tokens) {
      if (source.startsWith(token.marker, index)) {
        return token;
      }
    }

    return null;
  }

  void _appendSegment(
    List<StudyTextSegment> segments,
    String text,
    StudyTextDecoration decoration,
  ) {
    if (text.isEmpty) {
      return;
    }

    if (segments.isNotEmpty && segments.last.decoration == decoration) {
      final previous = segments.removeLast();
      segments.add(
        StudyTextSegment(
          text: '${previous.text}$text',
          decoration: decoration,
        ),
      );
      return;
    }

    segments.add(
      StudyTextSegment(
        text: text,
        decoration: decoration,
      ),
    );
  }
}

class DecoratedStudyText extends StatelessWidget {
  const DecoratedStudyText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  static const StudyTextParser _parser = StudyTextParser();

  @override
  Widget build(BuildContext context) {
    final parsed = _parser.parse(text);
    final effectiveStyle = style ??
        Theme.of(context).textTheme.bodyLarge ??
        DefaultTextStyle.of(context).style;
    final colorScheme = Theme.of(context).colorScheme;
    final highlightOpacity =
        colorScheme.brightness == Brightness.dark ? 72 : 48;
    final highlightColor = Color.alphaBlend(
      colorScheme.tertiary.withAlpha(highlightOpacity),
      colorScheme.surface,
    );
    final baseFontSize = effectiveStyle.fontSize ??
        DefaultTextStyle.of(context).style.fontSize ??
        14;

    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: parsed.segments.map((segment) {
          final segmentStyle = switch (segment.decoration) {
            StudyTextDecoration.plain => const TextStyle(),
            StudyTextDecoration.bold => const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            StudyTextDecoration.highlight => TextStyle(
                backgroundColor: highlightColor,
              ),
            StudyTextDecoration.underline => const TextStyle(
                decoration: TextDecoration.underline,
                decorationThickness: 1.5,
              ),
            StudyTextDecoration.heading => TextStyle(
                color: colorScheme.primary,
                fontSize: baseFontSize + 1.5,
                fontWeight: FontWeight.bold,
                height: 1.8,
              ),
          };

          return TextSpan(
            text: segment.text,
            style: segmentStyle,
          );
        }).toList(growable: false),
      ),
      textAlign: textAlign,
      softWrap: true,
      semanticsLabel: parsed.plainText,
    );
  }
}

class _DecorationToken {
  const _DecorationToken(
    this.marker,
    this.decoration,
  );

  final String marker;
  final StudyTextDecoration decoration;
}
