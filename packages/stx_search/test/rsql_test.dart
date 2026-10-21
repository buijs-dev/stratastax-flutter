import 'package:stx_search/stx_search.dart';
import 'package:test/test.dart';

void main() {
  test('comparisons encode as in stratastax-search', () {
    expect(
      Rsql.eq('gameId', '3fa85f64-5717-4562-b3fc-2c963f66afa6').encode(),
      'gameId==3fa85f64-5717-4562-b3fc-2c963f66afa6',
    );
    expect(Rsql.ge('playedAt', '2026-01-01T00:00:00.000Z').encode(), 'playedAt=ge=2026-01-01T00:00:00.000Z');
    expect(Rsql.isIn('scoreType', ['SCORE', 'WIN_LOSS']).encode(), 'scoreType=in=(SCORE,WIN_LOSS)');
    expect(Rsql.ne('status', 'DRAFT').encode(), 'status!=DRAFT');
  });

  test('values with reserved characters are quoted, quotes and backslashes escaped', () {
    expect(Rsql.eq('name', 'Ticket to Ride').encode(), 'name=="Ticket to Ride"');
    expect(Rsql.eq('name', 'a;b,c').encode(), 'name=="a;b,c"');
    expect(Rsql.eq('name', 'say "hi"').encode(), r'name=="say \"hi\""');
    expect(Rsql.eq('name', '').encode(), 'name==""');
  });

  test('contains escapes like-wildcards, then quoting escapes the backslash', () {
    expect(Rsql.contains('name', 'cat').encode(), 'name=ilike="%cat%"');
    // `100%` must match a literal %: pattern %100\%%, quoted "%100\\%%" (stratastax-search README).
    expect(Rsql.contains('code', '100%').encode(), r'code=ilike="%100\\%%"');
    expect(Rsql.contains('code', 'a_b').encode(), r'code=ilike="%a\\_b%"');
    expect(Rsql.escapeLike(r'a\b'), r'a\\b');
  });

  test('and/or drop nulls, collapse single parts and parenthesize OR inside AND', () {
    expect(Rsql.and([null, null]), isNull);
    expect(Rsql.and([null, Rsql.eq('a', '1')])!.encode(), 'a==1');
    expect(Rsql.and([Rsql.eq('a', '1'), Rsql.eq('b', '2')])!.encode(), 'a==1;b==2');
    final text = Rsql.or([Rsql.contains('name', 'x'), Rsql.contains('description', 'x')]);
    expect(
      Rsql.and([text, Rsql.eq('scoreType', 'SCORE')])!.encode(),
      '(name=ilike="%x%",description=ilike="%x%");scoreType==SCORE',
    );
  });

  test('equal filters are equal', () {
    expect(Rsql.and([Rsql.eq('a', '1'), Rsql.eq('b', '2')]), Rsql.and([Rsql.eq('a', '1'), Rsql.eq('b', '2')]));
  });

  test('sort encodes field:DIRECTION in priority order', () {
    expect(
      const SortSpec([SortField('playedAt', SortDirection.desc), SortField('id')]).encode(),
      'playedAt:DESC,id:ASC',
    );
    expect(SortSpec.none.encode(), isNull);
    expect(const SortField('name').flipped, const SortField('name', SortDirection.desc));
  });

  test('a query with a cursor sends only cursor and limit', () {
    const query = StxSearchQuery(filter: 'a==1', sort: 'name:ASC', limit: 20);
    expect(query.params, (limit: 20, cursor: null, filter: 'a==1', sort: 'name:ASC'));
    expect(query.at('abc').params, (limit: 20, cursor: 'abc', filter: null, sort: null));
    expect(query.key, isNot(query.at('abc').key));
    expect(query, const StxSearchQuery(filter: 'a==1', sort: 'name:ASC', limit: 20));
  });
}
