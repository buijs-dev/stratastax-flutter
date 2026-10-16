import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

/// One choice of a data source. [label] is user data (a name from the server), not UI copy.
final class StxOption<T> {
  const StxOption(this.value, this.label);

  final T value;
  final String label;

  StxOption<U> map<U>(U Function(T value) convert) => StxOption(convert(value), label);
}

/// Supplies options for autocomplete and select fields.
abstract interface class StxDataSource<T> {
  Future<Result<List<StxOption<T>>, Problem>> search(String query);
}

/// A data source backed by a contract operation; generated from `@UiDataSource`.
final class StxEndpointSource<T, P, R, I> implements StxDataSource<T> {
  const StxEndpointSource({
    required this.client,
    required this.endpoint,
    required this.params,
    required this.items,
    required this.value,
    required this.label,
  });

  final StxClient client;
  final Endpoint<P, NoBody, R> endpoint;
  final P Function(String query) params;
  final List<I> Function(R response) items;
  final T Function(I item) value;
  final String Function(I item) label;

  @override
  Future<Result<List<StxOption<T>>, Problem>> search(String query) async => (await client.fetch(
    endpoint,
    params(query),
  )).map((response) => [for (final item in items(response)) StxOption(value(item), label(item))]);
}

/// A source whose values are converted, e.g. `Uuid` → `GameId`.
final class _MappedSource<T, U> implements StxDataSource<U> {
  const _MappedSource(this.source, this.convert);

  final StxDataSource<T> source;
  final U Function(T value) convert;

  @override
  Future<Result<List<StxOption<U>>, Problem>> search(String query) async =>
      (await source.search(query)).map((options) => [for (final o in options) o.map(convert)]);
}

extension StxDataSourceMap<T> on StxDataSource<T> {
  StxDataSource<U> map<U>(U Function(T value) convert) => _MappedSource(this, convert);
}
