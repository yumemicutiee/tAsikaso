import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/app_store.dart';
import '../models/models.dart';
import '../utils/format.dart';

/// What the study server made from a scan's text.
@immutable
class StudyKit {
  const StudyKit({
    required this.title,
    required this.summary,
    required this.notes,
    required this.concepts,
    required this.cards,
    required this.quiz,
  });

  final String title;
  final String summary;

  /// The notes typed up cleanly (see `notes_pdf.dart` for the line format).
  final String notes;
  final List<Concept> concepts;

  /// Ready-made cards, each with its own id.
  final List<Flashcard> cards;

  /// Quiz questions, already pointing at [cards] by id.
  final List<QuizQuestion> quiz;

  factory StudyKit.fromJson(Json j) {
    final cards = [
      for (final c in (j['cards'] as List<Object?>? ?? const []))
        if (c is Map<String, Object?>)
          if ((c['front'] as String? ?? '').isNotEmpty &&
              (c['back'] as String? ?? '').isNotEmpty)
            Flashcard(
              id: newId(),
              front: c['front'] as String,
              back: c['back'] as String,
            ),
    ];
    return StudyKit(
      title: j['title'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      concepts: Concept.listFromJson(j['concepts']),
      cards: cards,
      quiz: questionsFromServer(j['quiz'], cards),
    );
  }

  /// Server questions name the card they test by its index in [cards]; the
  /// app keeps the card's id instead.
  static List<QuizQuestion> questionsFromServer(
      Object? list, List<Flashcard> cards) {
    final out = <QuizQuestion>[];
    for (final q in (list as List<Object?>? ?? const [])) {
      if (q is! Map<String, Object?>) continue;
      final index = q['cardIndex'];
      final cardId = index is num && index >= 0 && index < cards.length
          ? cards[index.toInt()].id
          : null;
      try {
        out.add(QuizQuestion.fromJson({...q, 'card': cardId}));
      } on FormatException {
        // One unusable question is left out, the rest still play.
      }
    }
    return out;
  }
}

/// The study server's verdict on a typed answer.
@immutable
class AnswerCheck {
  const AnswerCheck({required this.verdict, required this.feedback});

  /// "correct", "partly" or "wrong".
  final String verdict;
  final String feedback;

  bool get correct => verdict == 'correct';
  bool get partly => verdict == 'partly';
}

/// Why the study server couldn't help, in words for the user.
class StudyAiException implements Exception {
  const StudyAiException(this.code, this.message);

  /// `offline`, `timeout`, `not_set`, `bad_reply`, or the server's own code
  /// (`unauthorized`, `rate_limited`, `declined`, `too_long`, …).
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Talks to the study server in `server/`, which asks Claude for clean
/// notes, key concepts, flashcards and quizzes, and marks typed answers.
///
/// The server's address and token come from Settings → Smart Study, or are
/// built into the app with `--dart-define=STUDY_AI_URL=… STUDY_AI_TOKEN=…`.
class StudyAi {
  StudyAi._();

  static const _builtInUrl = String.fromEnvironment('STUDY_AI_URL');
  static const _builtInToken = String.fromEnvironment('STUDY_AI_TOKEN');

  /// Set in tests to stand in for the network.
  @visibleForTesting
  static http.Client Function()? debugClient;

  /// Making a study kit at high effort can take a couple of minutes.
  static const timeout = Duration(minutes: 3);

  static AppPrefs get _prefs => AppStore.instance.prefs;

  static String get serverUrl {
    final typed = _prefs.aiServerUrl.trim();
    return typed.isNotEmpty ? typed : _builtInUrl.trim();
  }

  static String get token {
    final typed = _prefs.aiToken.trim();
    return typed.isNotEmpty ? typed : _builtInToken.trim();
  }

  /// A server address is known.
  static bool get hasServer => serverUrl.isNotEmpty;

  /// Smart Study is switched on and a server address is known.
  static bool get isOn => _prefs.useAi && hasServer;

  /// True if [url] looks like a server address the app can call.
  static bool isValidUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Clean notes, key concepts, flashcards and a quiz for [text]. Zero
  /// [maxCards] or [quizCount] asks for none of those (cheaper).
  static Future<StudyKit> makeStudyKit({
    required String text,
    String? title,
    int maxCards = 30,
    int quizCount = 12,
  }) async {
    final trimmedTitle = title?.trim();
    final j = await _post('/v1/study-kit', {
      'text': text,
      'title': ?(trimmedTitle == null || trimmedTitle.isEmpty ? null : trimmedTitle),
      'maxCards': maxCards,
      'quizCount': quizCount,
    });
    final kit = j['kit'];
    if (kit is! Map<String, Object?>) throw _badReply;
    return StudyKit.fromJson(kit);
  }

  /// A quiz on [cards]; each question points at its card by id.
  static Future<List<QuizQuestion>> makeQuiz({
    required String title,
    required List<Flashcard> cards,
    List<Concept> concepts = const [],
    int? count,
  }) async {
    final j = await _post('/v1/quiz', {
      'title': title,
      'cards': [
        for (final c in cards) {'front': c.front, 'back': c.back},
      ],
      if (concepts.isNotEmpty)
        'concepts': [for (final c in concepts) c.toJson()],
      'count': ?count,
    });
    final quiz = j['quiz'];
    if (quiz is! Map<String, Object?>) throw _badReply;
    return StudyKit.questionsFromServer(quiz['questions'], cards);
  }

  /// Marks a typed answer by meaning.
  static Future<AnswerCheck> checkAnswer({
    required String question,
    required String answer,
    List<String> acceptable = const [],
    required String userAnswer,
  }) async {
    final j = await _post('/v1/check-answer', {
      'question': question,
      'answer': answer,
      if (acceptable.isNotEmpty) 'acceptable': acceptable,
      'userAnswer': userAnswer,
    });
    final check = j['check'];
    if (check is! Map<String, Object?>) throw _badReply;
    return AnswerCheck(
      verdict: check['verdict'] as String? ?? 'wrong',
      feedback: check['feedback'] as String? ?? '',
    );
  }

  /// True if a study server answers at [url] (no token needed).
  static Future<bool> ping(String url) async {
    if (!isValidUrl(url)) return false;
    final client = (debugClient ?? http.Client.new)();
    try {
      final res = await client
          .get(_uri(url, '/health'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return false;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j is Map && j['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static const _badReply = StudyAiException(
      'bad_reply', "The study server sent something the app couldn't read.");

  static Uri _uri(String base, String path) =>
      Uri.parse(base.trim().replaceFirst(RegExp(r'/+$'), '') + path);

  static Future<Json> _post(String path, Json body) async {
    final base = serverUrl;
    if (!isValidUrl(base)) {
      throw const StudyAiException('not_set',
          'No study server is set. Add its address in Settings → Smart Study.');
    }
    final client = (debugClient ?? http.Client.new)();
    try {
      final res = await client
          .post(
            _uri(base, path),
            headers: {
              'content-type': 'application/json',
              if (token.isNotEmpty) 'authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
      if (res.statusCode >= 400) {
        final error = decoded is Map ? decoded['error'] : null;
        final code = error is Map && error['code'] is String
            ? error['code'] as String
            : 'http_${res.statusCode}';
        final message = error is Map && error['message'] is String
            ? error['message'] as String
            : 'The study server replied with an error (${res.statusCode}).';
        throw StudyAiException(code, message);
      }
      if (decoded is! Map<String, Object?>) throw _badReply;
      return decoded;
    } on StudyAiException {
      rethrow;
    } on TimeoutException {
      throw const StudyAiException('timeout',
          'The study server took too long to answer. Please try again.');
    } catch (e) {
      debugPrint('Study server unreachable: $e');
      throw const StudyAiException('offline',
          "Couldn't reach the study server. Check your internet connection "
          'and the server address in Settings → Smart Study.');
    } finally {
      client.close();
    }
  }
}
