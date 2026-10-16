import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

void main() {
  test('decodes a validation problem from the contract', () {
    final problem = Problem.decode({
      'type': 'https://errors.stratastax.io/validation',
      'title': 'Validation failed',
      'status': 400,
      'detail': 'Request body is invalid',
      'instance': '/v1/matches',
      'errors': [
        {'field': 'players', 'code': 'OUT_OF_RANGE', 'message': 'size must be between 2 and 8'},
      ],
    }, fallbackStatus: 400);

    expect(problem.type, ProblemType.validation);
    expect(problem.status, 400);
    expect(problem.instance, '/v1/matches');
    expect(problem.violations.single.code, 'OUT_OF_RANGE');
  });

  test('an unknown type URI becomes unknown, not an error', () {
    final problem = Problem.decode({'type': 'https://example.com/x', 'title': 'X', 'status': 418}, fallbackStatus: 418);
    expect(problem.type, ProblemType.unknown);
  });

  test('a non-problem body falls back to the status', () {
    expect(Problem.decode('<html>', fallbackStatus: 404), Problem.fromStatus(404));
    expect(Problem.decode(null, fallbackStatus: 503).type, ProblemType.internal);
  });

  test('forStatus mirrors problem-core', () {
    expect(ProblemType.forStatus(401), ProblemType.authentication);
    expect(ProblemType.forStatus(403), ProblemType.authorization);
    expect(ProblemType.forStatus(404), ProblemType.notFound);
    expect(ProblemType.forStatus(409), ProblemType.conflict);
    expect(ProblemType.forStatus(412), ProblemType.preconditionFailed);
    expect(ProblemType.forStatus(422), ProblemType.validation);
    expect(ProblemType.forStatus(500), ProblemType.internal);
  });

  test('client-side problems', () {
    expect(Problem.network(Exception('offline')).type.isClientSide, isTrue);
    expect(Problem.decoding(JsonDecodeException('string', 1, ['name'])).status, 0);
  });

  test('pattern matching as used in hand-written services', () {
    const Result<int, Problem> result = Err(Problem(type: ProblemType.notFound, title: 'Not found', status: 404));
    final message = switch (result) {
      Ok(:final value) => 'ok $value',
      Err(error: Problem(status: 404)) => 'not found',
      Err() => 'other',
    };
    expect(message, 'not found');
  });

  test('a JSON body without a problem type is typed by its status', () {
    final problem = Problem.decode({'error': 'Player not found'}, fallbackStatus: 404);
    expect(problem.type, ProblemType.notFound);
    expect(problem.status, 404);
  });
}
