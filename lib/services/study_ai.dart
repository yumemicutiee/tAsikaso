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

  /// The user gave up waiting (see [CancelToken]).
  static const cancelled = StudyAiException(
      'cancelled', 'Cancelled. Nothing was changed.');

  /// `offline`, `timeout`, `not_set`, `bad_reply`, `cancelled`, or the
  /// server's own code (`unauthorized`, `rate_limited`, `declined`,
  /// `too_long`, …).
  final String code;
  final String message;

  /// The user cancelled: usually nothing needs saying.
  bool get isCancelled => code == cancelled.code;

  @override
  String toString() => message;
}

/// Lets the user give up on a long wait. A study server request that
/// carries one ends straight away with [StudyAiException.cancelled] once
/// [cancel] is called, and its connection is closed, so the server sees
/// the app has gone and can stop too.
class CancelToken {
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
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
    CancelToken? cancel,
  }) async {
    final trimmedTitle = title?.trim();
    final j = await _post('/v1/study-kit', {
      'text': text,
      'title': ?(trimmedTitle == null || trimmedTitle.isEmpty ? null : trimmedTitle),
      'maxCards': maxCards,
      'quizCount': quizCount,
    }, cancel: cancel);
    final kit = j['kit'];
    if (kit is! Map<String, Object?>) throw _badReply;
    return StudyKit.fromJson(kit);
  }

  /// A quiz on [cards]; each question points at its card by id. [count]
  /// questions (the server picks when null), of the given [types] only
  /// (all four when null).
  static Future<List<QuizQuestion>> makeQuiz({
    required String title,
    required List<Flashcard> cards,
    List<Concept> concepts = const [],
    int? count,
    Set<QuestionType>? types,
    CancelToken? cancel,
  }) async {
    final j = await _post('/v1/quiz', {
      'title': title,
      'cards': [
        for (final c in cards) {'front': c.front, 'back': c.back},
      ],
      if (concepts.isNotEmpty)
        'concepts': [for (final c in concepts) c.toJson()],
      'count': ?count,
      if (types != null && types.isNotEmpty)
        'types': [for (final t in QuestionType.values) if (types.contains(t)) t.key],
    }, cancel: cancel);
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

  /// How long [ping] waits. A server on a free host sleeps when unused and
  /// takes up to about a minute to wake on the first request.
  static const pingTimeout = Duration(seconds: 75);

  /// True if a study server answers at [url] (no token needed).
  static Future<bool> ping(String url) async {
    if (!isValidUrl(url)) return false;
    final client = (debugClient ?? http.Client.new)();
    try {
      final res = await client
          .get(_uri(url, '/health'))
          .timeout(pingTimeout);
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

  static Future<Json> _post(String path, Json body,
      {CancelToken? cancel}) async {
    final base = serverUrl;
    if (!isValidUrl(base)) {
      throw const StudyAiException('not_set',
          'No study server is set. Add its address in Settings → Smart Study.');
    }
    if (cancel != null && cancel.isCancelled) throw StudyAiException.cancelled;
    final client = (debugClient ?? http.Client.new)();
    try {
      var reply = client
          .post(
            _uri(base, path),
            headers: {
              'content-type': 'application/json',
              if (token.isNotEmpty) 'authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (cancel != null) {
        // Cancel doesn't wait for the server: the request is dropped (the
        // client is closed below, which closes the connection).
        reply = Future.any([
          reply,
          cancel.whenCancelled
              .then<http.Response>((_) => throw StudyAiException.cancelled),
        ]);
      }
      final res = await reply;

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
        // The server's request id, shortened, so a student can quote it
        // when reporting a problem (it finds the request in the server log).
        final id = error is Map && error['requestId'] is String
            ? (error['requestId'] as String).trim()
            : '';
        throw StudyAiException(
            code,
            id.isEmpty
                ? message
                : '$message (Ref ${id.length > 8 ? id.substring(0, 8) : id})');
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
