import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_quiz_study/widgets/decorated_study_text.dart';

void main() {
  group('StudyTextParser', () {
    const parser = StudyTextParser();

    test('装飾なしの文字列を改変しない', () {
      const source = '労働契約法第3条に基づき、XとYの関係を検討する。';
      final parsed = parser.parse(source);

      expect(parsed.plainText, source);
      expect(parsed.segments, hasLength(1));
      expect(parsed.segments.single.decoration, StudyTextDecoration.plain);
    });

    test('太字・背景強調・下線を同じ文章内で別々に解析する', () {
      const source = '**職種限定合意**がある場合、==個別的同意なしに=='
          '__配置転換を命ずることはできない__。';
      final parsed = parser.parse(source);

      expect(
        parsed.plainText,
        '職種限定合意がある場合、個別的同意なしに配置転換を命ずることはできない。',
      );
      expect(
        parsed.segments
            .firstWhere((segment) => segment.text == '職種限定合意')
            .decoration,
        StudyTextDecoration.bold,
      );
      expect(
        parsed.segments
            .firstWhere((segment) => segment.text == '個別的同意なしに')
            .decoration,
        StudyTextDecoration.highlight,
      );
      expect(
        parsed.segments
            .firstWhere(
              (segment) => segment.text == '配置転換を命ずることはできない',
            )
            .decoration,
        StudyTextDecoration.underline,
      );
      expect(parsed.plainText, isNot(contains('**')));
      expect(parsed.plainText, isNot(contains('==')));
      expect(parsed.plainText, isNot(contains('__')));
    });

    test('複数段落・空行・CRLFを保持する', () {
      const source = '【論点】\r\n**第1段落**\r\n\r\n==第2段落==\n__結論__';
      final parsed = parser.parse(source);

      expect(parsed.plainText, '【論点】\r\n第1段落\r\n\r\n第2段落\n結論');
    });

    test('不完全・空の記法でも文字を欠落させない', () {
      const source = '**閉じていない文章\n'
          '==強調が終わっていない\n'
          '__\n'
          '****\n'
          '終了記号だけ**\n'
          '**未完了でも ==有効な強調== は解析する';
      final parsed = parser.parse(source);

      expect(
        parsed.plainText,
        '**閉じていない文章\n'
        '==強調が終わっていない\n'
        '__\n'
        '****\n'
        '終了記号だけ**\n'
        '**未完了でも 有効な強調 は解析する',
      );
      expect(
        parsed.segments
            .firstWhere((segment) => segment.text == '有効な強調')
            .decoration,
        StudyTextDecoration.highlight,
      );
    });

    test('空文字列を安全に処理する', () {
      final parsed = parser.parse('');

      expect(parsed.plainText, isEmpty);
      expect(parsed.segments, isEmpty);
    });

    test('非常に長く装飾記号が多い文章を最後まで解析する', () {
      final source = List<String>.generate(
        2000,
        (index) => '**X$index** ==Y$index== __第${index + 1}条__',
      ).join('\n\n');

      final parsed = parser.parse(source);

      expect(parsed.plainText, startsWith('X0 Y0 第1条'));
      expect(parsed.plainText, endsWith('X1999 Y1999 第2000条'));
      expect(parsed.plainText, isNot(contains('**')));
      expect(parsed.plainText, isNot(contains('==')));
      expect(parsed.plainText, isNot(contains('__')));
    });

    test('行全体の隅付き括弧だけを見出しとして扱う', () {
      const source = '本文中の【判旨】は通常の語句。\n【判旨】\n本文';
      final parsed = parser.parse(source);
      final headingSegments = parsed.segments
          .where(
            (segment) => segment.decoration == StudyTextDecoration.heading,
          )
          .toList();

      expect(headingSegments, hasLength(1));
      expect(headingSegments.single.text, '【判旨】');
      expect(
        parsed.segments.first.decoration,
        StudyTextDecoration.plain,
      );
    });

    test('入れ子は外側だけを解釈し内側の記号を通常文字として残す', () {
      final parsed = parser.parse('==**最重要部分**==');

      expect(parsed.segments, hasLength(1));
      expect(parsed.segments.single.decoration, StudyTextDecoration.highlight);
      expect(parsed.segments.single.text, '**最重要部分**');
      expect(parsed.plainText, '**最重要部分**');
    });
  });

  group('DecoratedStudyText', () {
    testWidgets('3種類の装飾をTextSpanのスタイルへ変換する', (tester) async {
      final textWidget = await _pumpDecoratedText(
        tester,
        '**太字** ==重要表示== __下線__',
      );
      final spans = _childSpansOf(textWidget);

      expect(
        _spanWithText(spans, '太字').style?.fontWeight,
        FontWeight.bold,
      );
      expect(
        _spanWithText(spans, '重要表示').style?.backgroundColor,
        isNotNull,
      );
      expect(
        _spanWithText(spans, '下線').style?.decoration,
        TextDecoration.underline,
      );
      expect(textWidget.textSpan!.toPlainText(), '太字 重要表示 下線');
      expect(textWidget.semanticsLabel, '太字 重要表示 下線');
    });

    testWidgets('見出しを本文より大きい太字とテーマ色で表示する', (tester) async {
      final textWidget = await _pumpDecoratedText(
        tester,
        '【判旨】\n本文',
      );
      final spans = _childSpansOf(textWidget);
      final headingSpan = _spanWithText(spans, '【判旨】');

      expect(headingSpan.style?.fontWeight, FontWeight.bold);
      expect(headingSpan.style?.fontSize, greaterThan(16));
      expect(headingSpan.style?.color, isNotNull);
    });

    testWidgets('ライト・ダークテーマで異なるテーマ由来の背景色を使用する', (tester) async {
      final lightWidget = await _pumpDecoratedText(
        tester,
        '==重要==',
        brightness: Brightness.light,
      );
      final lightColor = _spanWithText(_childSpansOf(lightWidget), '重要')
          .style
          ?.backgroundColor;

      final darkWidget = await _pumpDecoratedText(
        tester,
        '==重要==',
        brightness: Brightness.dark,
      );
      final darkColor =
          _spanWithText(_childSpansOf(darkWidget), '重要').style?.backgroundColor;

      expect(lightColor, isNotNull);
      expect(darkColor, isNotNull);
      expect(lightColor, isNot(darkColor));
    });

    testWidgets('空文字列と不完全な記法でも例外なく全文を表示する', (tester) async {
      await _pumpDecoratedText(tester, '');
      expect(tester.takeException(), isNull);

      final malformedWidget = await _pumpDecoratedText(
        tester,
        '**閉じていない\n__\n****',
      );

      expect(tester.takeException(), isNull);
      expect(
        malformedWidget.textSpan!.toPlainText(),
        '**閉じていない\n__\n****',
      );
    });
  });
}

Future<Text> _pumpDecoratedText(
  WidgetTester tester,
  String source, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF256D85),
          brightness: brightness,
        ),
      ),
      home: Scaffold(
        body: DecoratedStudyText(
          key: const ValueKey('decorated-study-text'),
          text: source,
          style: const TextStyle(
            fontSize: 16,
            height: 1.6,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester.widget<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('decorated-study-text')),
      matching: find.byType(Text),
    ),
  );
}

List<TextSpan> _childSpansOf(Text textWidget) {
  final rootSpan = textWidget.textSpan! as TextSpan;
  return rootSpan.children!.cast<TextSpan>();
}

TextSpan _spanWithText(List<TextSpan> spans, String text) {
  return spans.firstWhere((span) => span.text == text);
}
