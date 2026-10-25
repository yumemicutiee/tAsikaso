import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:study_app/data/app_store.dart';
import 'package:study_app/models/models.dart';
import 'package:study_app/services/study_ai.dart';

/// What the study server sends back for a study kit.
const kitJson = {
  'kit': {
    'title': 'Cell Biology',
    'summary': 'The parts of a cell.',
    'notes': '# Cell Biology\n- Mitochondria make ATP',
    'concepts': [
      {'term': 'ATP', 'explanation': 'The cell\'s energy currency.'},
    ],
    'cards': [
      {'front': 'What makes ATP?', 'back': 'The mitochondria'},
      {'front': 'Ribosome', 'back': 'Makes proteins'},
      {'front': '', 'back': 'no front'},
    ],
    'quiz': [
      {
        'type': 'multiple_choice',
        'prompt': 'What makes ATP?',
        'options': ['Ribosome', 'Mitochondria', 'Nucleus', 'Golgi'],
        'answerIndex': 1,
        'answer': 'Mitochondria',
        'acceptable': <String>[],
        'explanation': 'Respiration happens there.',
        'cardIndex': 0,
      },
      {
        'type': 'typed',
        'prompt': 'What does a ribosome do?',
        'options': <String>[],
        'answerIndex': -1,
        'answer': 'Makes proteins',
        'acceptable': ['protein synthesis'],
        'explanation': '',
        'cardIndex': 9,
      },
    ],
  },
  'model': 'claude-opus-5-5',
  'usage': {'input': 100, 'output': 200},
};

void main() {
  final store = AppStore.instance;
  final requests = <http.Request>[];

  setUp(() {
    store.resetForTesting();
    store.updatePrefs(store.prefs
        .copyWith(aiServerUrl: 'https://study.test/api/', aiToken: 'secret'));
    requests.clear();
  });

  tearDown(() => StudyAi.debugClient = null);

  void answerWith(int status, Object body) {
    StudyAi.debugClient = () => MockClient((req) async {
          requests.add(req);
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json'});
        });
  }

  test('is on when a server is set and the switch is on', () {
    expect(StudyAi.isOn, isTrue);
    store.updatePrefs(store.prefs.copyWith(useAi: false));
    expect(StudyAi.isOn, isFalse);
    store.updatePrefs(store.prefs.copyWith(useAi: true, aiServerUrl: ''));
    expect(StudyAi.hasServer, isFalse);
    expect(StudyAi.isOn, isFalse);
  });

  test('only http(s) addresses with a host are accepted', () {
    expect(StudyAi.isValidUrl('https://study.test'), isTrue);
    expect(StudyAi.isValidUrl('http://192.168.1.5:8787'), isTrue);
    expect(StudyAi.isValidUrl('study.test'), isFalse);
    expect(StudyAi.isValidUrl('ftp://study.test'), isFalse);
    expect(StudyAi.isValidUrl(''), isFalse);
  });

  test('a study kit comes back with cards that have ids and a quiz that '
      'points at them', () async {
    answerWith(200, kitJson);
    final kit = await StudyAi.makeStudyKit(text: 'x' * 40, title: 'Bio');

    final req = requests.single;
    expect(req.url.toString(), 'https://study.test/api/v1/study-kit');
    expect(req.headers['authorization'], 'Bearer secret');
    final sent = jsonDecode(req.body) as Map<String, Object?>;
    expect(sent['title'], 'Bio');
    expect(sent['maxCards'], 30);

    expect(kit.title, 'Cell Biology');
    expect(kit.notes, startsWith('# Cell Biology'));
    expect(kit.concepts.single.term, 'ATP');
    expect(kit.cards.length, 2); // the one without a front is left out
    expect(kit.cards.map((c) => c.id).toSet().length, 2);
    expect(kit.quiz.length, 2);
    expect(kit.quiz.first.cardId, kit.cards.first.id);
    expect(kit.quiz.last.cardId, isNull); // index 9 is no card
    expect(kit.quiz.last.acceptable, ['protein synthesis']);
  });

  test('a quiz for existing cards maps the indexes back to card ids',
      () async {
    answerWith(200, {
      'quiz': {
        'questions': [
          {
            'type': 'true_false',
            'prompt': 'Ribosomes make ATP.',
            'options': ['True', 'False'],
            'answerIndex': 1,
            'answer': 'False',
            'acceptable': <String>[],
            'explanation': 'Mitochondria do.',
            'cardIndex': 1,
          },
        ],
      },
    });
    const cards = [
      Flashcard(id: 'a', front: 'A', back: 'a'),
      Flashcard(id: 'b', front: 'B', back: 'b'),
    ];
    final quiz = await StudyAi.makeQuiz(title: 'Set', cards: cards);
    expect(quiz.single.cardId, 'b');
    expect(quiz.single.type, QuestionType.trueFalse);
    final sent = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect((sent['cards'] as List).length, 2);
  });

  test('a quiz can ask for some question types only', () async {
    answerWith(200, {
      'quiz': {'questions': <Object>[]},
    });
    await StudyAi.makeQuiz(
      title: 'Set',
      cards: const [Flashcard(id: 'a', front: 'A', back: 'a')],
      count: 5,
      types: {QuestionType.typed, QuestionType.multipleChoice},
    );
    final sent = jsonDecode(requests.single.body) as Map<String, Object?>;
    expect(sent['count'], 5);
    expect(sent['types'], ['multiple_choice', 'typed']);
  });

  test('too little text is turned down in words, before anything is sent',
      () async {
    answerWith(200, kitJson);
    await expectLater(
      StudyAi.makeStudyKit(text: '  Chapter 3: Cells \n'),
      throwsA(isA<StudyAiException>()
          .having((e) => e.code, 'code', 'too_short')
          .having((e) => e.message, 'message', isNot(contains('expected')))),
    );
    expect(requests, isEmpty);
  });

  test('a set bigger than the server takes is quizzed on as many cards as it '
      'takes, and questions still find their card', () async {
    answerWith(200, {
      'quiz': {
        'questions': [
          {
            'type': 'typed',
            'prompt': 'Q?',
            'options': <String>[],
            'answerIndex': -1,
            'answer': 'A',
            'acceptable': <String>[],
            'explanation': '',
            'cardIndex': 5,
          },
        ],
      },
    });
    final cards = [
      for (var i = 0; i < StudyAi.maxQuizCards + 50; i++)
        Flashcard(id: 'id$i', front: 'Front $i', back: 'Back $i'),
    ];
    final quiz = await StudyAi.makeQuiz(title: 'Big', cards: cards);
    final sent = (jsonDecode(requests.single.body) as Map)['cards'] as List;
    expect(sent.length, StudyAi.maxQuizCards);
    final sixth = (sent[5] as Map)['front'] as String;
    expect(quiz.single.cardId, cards.firstWhere((c) => c.front == sixth).id);
  });

  test('Cancel ends a request at once and closes the connection', () async {
    final server = _SilentServer();
    StudyAi.debugClient = () => server;
    final cancel = CancelToken();
    final kit = StudyAi.makeStudyKit(text: 'x' * 40, cancel: cancel);
    await Future<void>.delayed(Duration.zero);
    expect(server.requests, 1);

    cancel.cancel();
    await expectLater(
      kit,
      throwsA(isA<StudyAiException>()
          .having((e) => e.isCancelled, 'isCancelled', isTrue)),
    );
    expect(server.closed, isTrue);

    // A token that was cancelled already sends nothing.
    await expectLater(
      StudyAi.makeQuiz(title: 'T', cards: const [], cancel: cancel),
      throwsA(isA<StudyAiException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(server.requests, 1);
  });

  test('an answer check returns the verdict and feedback', () async {
    answerWith(200, {
      'check': {'verdict': 'partly', 'feedback': 'Nearly: it also needs water.'},
    });
    final check = await StudyAi.checkAnswer(
        question: 'Q', answer: 'A', userAnswer: 'a-ish');
    expect(check.partly, isTrue);
    expect(check.correct, isFalse);
    expect(check.feedback, contains('water'));
  });

  test("the server's own error code and message come through", () async {
    answerWith(401, {
      'error': {'code': 'unauthorized', 'message': "This app isn't allowed."},
    });
    await expectLater(
      StudyAi.makeStudyKit(text: 'x' * 40),
      throwsA(isA<StudyAiException>()
          .having((e) => e.code, 'code', 'unauthorized')
          .having((e) => e.message, 'message', "This app isn't allowed.")),
    );
  });

  test("the server's request id is added to its message as a short Ref",
      () async {
    answerWith(429, {
      'error': {
        'code': 'daily_limit',
        'message': "You've reached today's limit.",
        'requestId': '53599e15-78c4-447d-8a0e-26dbce3f7eba',
      },
    });
    await expectLater(
      StudyAi.makeStudyKit(text: 'x' * 40),
      throwsA(isA<StudyAiException>()
          .having((e) => e.code, 'code', 'daily_limit')
          .having((e) => e.message, 'message',
              "You've reached today's limit. (Ref 53599e15)")),
    );
  });

  test('no connection is reported as offline, in plain words', () async {
    StudyAi.debugClient =
        () => MockClient((_) async => throw http.ClientException('refused'));
    await expectLater(
      StudyAi.makeStudyKit(text: 'x' * 40),
      throwsA(isA<StudyAiException>()
          .having((e) => e.code, 'code', 'offline')
          .having((e) => e.message, 'message', contains('Settings'))),
    );
  });

  test('a reply that is not JSON is a bad reply', () async {
    StudyAi.debugClient =
        () => MockClient((_) async => http.Response('<html>', 200));
    await expectLater(
      StudyAi.makeStudyKit(text: 'x' * 40),
      throwsA(isA<StudyAiException>().having((e) => e.code, 'code', 'bad_reply')),
    );
  });

  test('no server set is reported before any request is made', () async {
    store.updatePrefs(store.prefs.copyWith(aiServerUrl: ''));
    answerWith(200, kitJson);
    await expectLater(
      StudyAi.makeStudyKit(text: 'x' * 40),
      throwsA(isA<StudyAiException>().having((e) => e.code, 'code', 'not_set')),
    );
    expect(requests, isEmpty);
  });

  test('ping says whether a study server answers', () async {
    answerWith(200, {'ok': true, 'model': 'claude-opus-5-5'});
    expect(await StudyAi.ping('https://study.test'), isTrue);
    expect(requests.single.url.path, '/health');
    answerWith(200, {'hello': 'world'});
    expect(await StudyAi.ping('https://study.test'), isFalse);
    expect(await StudyAi.ping('not a url'), isFalse);
  });
}

/// A study server that never answers, until the app hangs up.
class _SilentServer extends http.BaseClient {
  int requests = 0;
  bool closed = false;
  final _hangUp = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    await _hangUp.future;
    throw http.ClientException('Connection closed', request.url);
  }

  @override
  void close() {
    closed = true;
    if (!_hangUp.isCompleted) _hangUp.complete();
  }
}
