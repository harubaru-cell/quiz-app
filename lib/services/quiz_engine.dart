import '../models/quiz_question.dart';
import '../models/quiz_session.dart';

class QuizEngine {
  List<QuizSessionQuestion> buildQuestions({
    required List<QuizQuestion> source,
    required QuestionCountOption countOption,
    required bool shuffle,
    List<String>? onlyQuestionIds,
  }) {
    final allowedIds = onlyQuestionIds?.toSet();

    final candidates = source
        .where(
          (question) => allowedIds == null || allowedIds.contains(question.id),
        )
        .map(
          (question) => QuizSessionQuestion(
            question: question,
            displayChoices: List<String>.from(question.choices),
            correctIndex: question.answer,
          ),
        )
        .toList();

    if (shuffle) {
      candidates.shuffle();
    }

    final limit = countOption.limit;

    if (limit == null || candidates.length <= limit) {
      return candidates;
    }

    return candidates.take(limit).toList();
  }

  bool isCorrect(
    QuizSessionQuestion question,
    int selectedIndex,
  ) {
    final correctIndex = question.correctIndex;

    return correctIndex != null && correctIndex == selectedIndex;
  }

  bool isTextCorrect(
    QuizSessionQuestion question,
    String enteredAnswer,
  ) {
    final normalizedEnteredAnswer = normalizeAnswer(enteredAnswer);

    if (normalizedEnteredAnswer.isEmpty) {
      return false;
    }

    return question.question.answers.any(
      (correctAnswer) =>
          normalizeAnswer(correctAnswer) == normalizedEnteredAnswer,
    );
  }

  String normalizeAnswer(String answer) {
    final widthNormalized = _normalizeAsciiWidth(answer);
    final kanaNormalized = _katakanaToHiragana(widthNormalized);

    return kanaNormalized.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  String _normalizeAsciiWidth(String text) {
    final buffer = StringBuffer();

    for (final characterCode in text.runes) {
      if (characterCode == 0x3000) {
        // 全角スペースを半角スペースに変換
        buffer.write(' ');
      } else if (characterCode >= 0xFF01 && characterCode <= 0xFF5E) {
        // 全角の英数字・記号を半角に変換
        buffer.writeCharCode(characterCode - 0xFEE0);
      } else {
        buffer.writeCharCode(characterCode);
      }
    }

    return buffer.toString();
  }

  String _katakanaToHiragana(String text) {
    final buffer = StringBuffer();

    for (final characterCode in text.runes) {
      if (characterCode >= 0x30A1 && characterCode <= 0x30F6) {
        // カタカナをひらがなに変換
        buffer.writeCharCode(characterCode - 0x60);
      } else {
        buffer.writeCharCode(characterCode);
      }
    }

    return buffer.toString();
  }
}
