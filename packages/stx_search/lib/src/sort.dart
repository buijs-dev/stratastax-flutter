import 'package:meta/meta.dart';

enum SortDirection {
  asc('ASC'),
  desc('DESC');

  const SortDirection(this.wire);

  final String wire;

  SortDirection get flipped => this == asc ? desc : asc;
}

/// One sort key: a sortable field as the endpoint names it, and its direction.
@immutable
final class SortField {
  const SortField(this.field, [this.direction = SortDirection.asc]);

  final String field;
  final SortDirection direction;

  SortField get flipped => SortField(field, direction.flipped);

  String encode() => '$field:${direction.wire}';

  @override
  bool operator ==(Object other) => other is SortField && other.field == field && other.direction == direction;

  @override
  int get hashCode => Object.hash(field, direction);

  @override
  String toString() => encode();
}

/// The `sort` query parameter: `playedAt:DESC,createdAt:ASC`. The server appends its tiebreaker
/// (the id), so a page boundary is always well defined.
@immutable
final class SortSpec {
  const SortSpec(this.keys);

  /// No sort: the endpoint's default order.
  static const none = SortSpec([]);

  /// In priority order.
  final List<SortField> keys;

  bool get isEmpty => keys.isEmpty;

  /// Null when there is nothing to sort on.
  String? encode() => isEmpty ? null : keys.map((k) => k.encode()).join(',');

  @override
  bool operator ==(Object other) => other is SortSpec && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => encode() ?? '';
}
