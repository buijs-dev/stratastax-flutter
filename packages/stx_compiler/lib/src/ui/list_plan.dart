part of 'app_plan.dart';

/// How a filter is edited and what RSQL it sends (stx_ui `StxFilter` subclasses).
enum FilterKind { text, choice, boolean, range, dateRange, source }

final class ColumnPlan {
  const ColumnPlan({
    required this.label,
    required this.value,
    required this.flex,
    required this.primary,
    this.sortField,
  });

  /// Dart expression of the header `Msg`.
  final String label;

  /// Dart expression of the cell `Msg`, on `context` and `item`.
  final String value;
  final String? sortField;
  final int flex;
  final bool primary;
}

final class FilterPlan {
  const FilterPlan({
    required this.kind,
    required this.field,
    required this.label,
    this.type,
    this.dateTime = false,
    this.source,
    this.wire,
  });

  final FilterKind kind;

  /// The filterable field as the endpoint names it.
  final String field;
  final String label;

  /// The value type: the enum of a choice, `int`/`double` of a range, the option type of a source.
  final String? type;

  /// A date range on a date-time field.
  final bool dateTime;
  final DataSourcePlan? source;

  /// Dart expression of a function from a value to its wire string (choice, source).
  final String? wire;
}

final class SortPlan {
  const SortPlan({required this.field, required this.label, required this.direction});

  final String field;
  final String label;

  /// `asc` or `desc`.
  final String direction;
}

/// An overview: what `@UiListPage` resolves to against its list (and count) operation.
final class ListPlan implements RoutedPlan {
  const ListPlan({
    required this.list,
    required this.contract,
    required this.operation,
    required this.countOperation,
    required this.paramsClass,
    required this.countParamsClass,
    required this.responseType,
    required this.itemType,
    required this.columns,
    required this.filters,
    required this.searchFields,
    required this.sorts,
    required this.initialSort,
    required this.enumLabels,
    required this.requires,
    required this.title,
    required this.imports,
    required this.pageSize,
    required this.cacheMode,
    required this.cacheTtl,
  });

  final ListPageIR list;
  final ContractIR contract;
  final OperationIR operation;
  final OperationIR? countOperation;
  final String paramsClass;
  final String? countParamsClass;
  final String responseType;
  final String itemType;
  final List<ColumnPlan> columns;
  final List<FilterPlan> filters;

  /// Aliases of the `@SearchText` fields; empty: no search box.
  final List<String> searchFields;
  final List<SortPlan> sorts;
  final SortPlan? initialSort;

  /// Enum type → value name → Msg expression, for cells and choice filters.
  final Map<String, Map<String, String>> enumLabels;
  final List<List<String>> requires;
  @override
  final String title;
  final Set<String> imports;
  final int pageSize;
  final String cacheMode;
  final int cacheTtl;

  String get base => list.name;

  @override
  String get name => list.name;

  @override
  String get location => list.location;

  @override
  RouteIR? get routeIR => list.route;

  @override
  String get page => '${base}Page';

  @override
  String get route => '${base}Route';

  /// The member of `AppServices`.
  String get serviceName => '${Naming.member(base)}Search';
}

extension on AppPlanner {
  ListPlan? _list(ListPageIR ir) {
    final resolved = _operation(ir.list, ir.location);
    if (resolved == null) return null;
    final (contract, operation) = resolved;
    final where = '${ir.list.apiClass}.${ir.list.member}';

    // The list operation: GET, the four parameters of stratastax-contract, a page of objects.
    if (operation.method != HttpMethodIR.get) {
      _error(UiCodes.list, ir.location, '$where is not a GET operation');
      return null;
    }
    final params = {for (final p in operation.params) p.wireName: p};
    final missing = [
      for (final name in const ['limit', 'cursor', 'filter', 'sort'])
        if (params[name]?.location != ParamLocation.query) name,
    ];
    if (missing.isNotEmpty) {
      _error(
        UiCodes.list,
        ir.location,
        '$where has no query parameter ${missing.map((m) => '"$m"').join(', ')}',
        hint: 'an overview needs the limit, cursor, filter and sort parameters of stratastax-contract',
      );
      return null;
    }
    for (final param in operation.params) {
      if (param.required) {
        _error(
          UiCodes.list,
          ir.location,
          '$where requires parameter "${param.wireName}", which an overview cannot fill',
        );
        return null;
      }
    }
    final response = operation.response;
    final page = response is RefTypeIR ? contract.schemas[response.schema] : null;
    PropertyIR? prop(SchemaIR? schema, String name) =>
        schema is ObjectSchemaIR ? schema.properties.where((p) => p.wireName == name).firstOrNull : null;
    final items = prop(page, 'items');
    final itemRef = switch (items?.type) {
      ListTypeIR(item: final RefTypeIR ref) => ref,
      _ => null,
    };
    final item = itemRef == null ? null : contract.schemas[itemRef.schema];
    if (page is! ObjectSchemaIR ||
        item is! ObjectSchemaIR ||
        prop(page, 'nextCursor') == null ||
        prop(page, 'prevCursor') == null) {
      _error(
        UiCodes.list,
        ir.location,
        '$where does not return a page: an object with "items" (objects), "nextCursor" and "prevCursor"',
      );
      return null;
    }

    // The count operation: GET with only `filter`, answering `{count}`.
    OperationIR? countOperation;
    if (ir.count case final count?) {
      final resolvedCount = _operation(count, ir.location);
      if (resolvedCount == null) return null;
      countOperation = resolvedCount.$2;
      final countWhere = '${count.apiClass}.${count.member}';
      final countResponse = countOperation.response;
      final countSchema = countResponse is RefTypeIR ? resolvedCount.$1.schemas[countResponse.schema] : null;
      final countProp = prop(countSchema, 'count');
      final valid =
          countOperation.method == HttpMethodIR.get &&
          countOperation.params.length == 1 &&
          countOperation.params.single.wireName == 'filter' &&
          countProp != null &&
          countProp.type is PrimitiveTypeIR &&
          (countProp.type as PrimitiveTypeIR).kind == PrimitiveKind.integer;
      if (!valid) {
        _error(
          UiCodes.list,
          ir.location,
          '$countWhere is not a count operation: GET with only a "filter" parameter, returning {count: integer}',
        );
        return null;
      }
      if (Naming.snake(resolvedCount.$1.name) != Naming.snake(contract.name)) {
        _error(UiCodes.list, ir.location, '$countWhere is in another contract than $where');
        return null;
      }
    }

    final keyBase = Naming.camel(ir.name);
    final title = _key('$keyBase.title', ir.location, seed: humanize(ir.name));
    final imports = <String>{
      ir.library,
      'package:${ui.package}/gen/contract/${ir.list.contractDir}/${ir.list.contractDir}.g.dart',
    };
    final requires = <List<String>>[_scopes(operation), if (countOperation != null) _scopes(countOperation)];
    for (final claim in ir.requires) {
      requires.add([claim]);
    }
    final search = operation.search;

    final enumLabels = <String, Map<String, String>>{};
    Map<String, String> labelsOf(EnumSchemaIR schema, String location) => enumLabels.putIfAbsent(
      schema.dartName,
      () => {
        for (final v in schema.values)
          v.dartName: _key('enum.${schema.dartName}.${v.dartName}', location, seed: humanize(v.wire)),
      },
    );

    final columns = <(int, ColumnPlan)>[];
    final filters = <FilterPlan>[];
    final searchFields = <String>[];
    final sorts = <SortPlan>[];
    SortPlan? initialSort;
    final orders = <int, String>{};
    var ok = true;

    for (final field in ir.fields) {
      if (field.ignore) continue;
      final used = field.column != null || field.filter != null || field.sort != null || field.searchText != null;
      if (!used) continue;
      final path = field.contractProperty ?? field.name;
      final resolvedPath = _path(item, contract, path, field.location);
      if (resolvedPath == null) {
        ok = false;
        continue;
      }
      final (:property, :access, :nullable) = resolvedPath;
      if (nullable && !field.type.nullable) {
        _error(
          UiCodes.typeMismatch,
          field.location,
          '"$path" may be absent in ${item.dartName}; declare ${field.name} as ${field.type.withNullable(true).code}',
        );
        ok = false;
        continue;
      }
      if (_map(field.type.nonNull, property.type, contract, field.location, 0) == null) {
        ok = false;
        continue;
      }
      final flat = _flatten(path);
      // A field that is only searched has no label of its own.
      final labelled = field.column != null || field.filter != null || field.sort != null;
      final label = !labelled
          ? 'StxKeys.searchLabel'
          : field.labelKeyId != null
          ? _keyById(field.labelKeyId!, field.location)
          : _key(
              '$keyBase.${field.name}.label',
              field.location,
              seed: AppPlanner._shortDescription(property.description) ?? humanize(field.name),
            );
      final leaf = property.type;
      final enumSchema = leaf is RefTypeIR ? contract.schemas[leaf.schema] : null;

      if (field.column case final column?) {
        if (column.order case final order?) {
          if (orders[order] case final other?) {
            _error(UiCodes.order, field.location, '@UiColumn(order: $order) is also used by "$other"');
          }
          orders[order] = field.name;
        }
        final cell = _cell(leaf, enumSchema, field.location, labelsOf);
        if (cell == null) {
          ok = false;
        } else {
          final value = nullable
              ? 'switch ($access) { final v? => ${cell('v')}, null => StxListColumn.none }'
              : cell(access);
          columns.add((
            column.order ?? 1 << 20,
            ColumnPlan(
              label: label,
              value: value,
              flex: column.flex,
              primary: column.primary,
              sortField: field.sort == null ? null : (field.sort!.alias.isEmpty ? flat : field.sort!.alias),
            ),
          ));
        }
      }

      if (field.searchText case final alias?) {
        if (leaf case PrimitiveTypeIR(kind: PrimitiveKind.string)) {
          final name = alias.isEmpty ? flat : alias;
          if (_whitelisted(search?.filter, name, 'filter', where, field.location)) searchFields.add(name);
        } else {
          _error(
            UiCodes.list,
            field.location,
            '@SearchText needs a string field; "$path" is ${_describe(leaf, contract)}',
          );
          ok = false;
        }
      }

      if (field.filter case final filter?) {
        final name = filter.alias.isEmpty ? flat : filter.alias;
        if (!_whitelisted(search?.filter, name, 'filter', where, field.location)) {
          ok = false;
        } else if (_filter(field, filter, name, label, leaf, enumSchema, contract, requires, labelsOf)
            case final plan?) {
          filters.add(plan);
        } else {
          ok = false;
        }
      }

      if (field.sort case final sort?) {
        final name = sort.alias.isEmpty ? flat : sort.alias;
        if (!_whitelisted(search?.sort, name, 'sort', where, field.location)) {
          ok = false;
        } else {
          final plan = SortPlan(field: name, label: label, direction: sort.direction);
          sorts.add(plan);
          if (sort.initial) {
            if (initialSort != null) {
              _error(
                UiCodes.list,
                field.location,
                'only one field can be the initial sort (also: ${initialSort.field})',
              );
              ok = false;
            }
            initialSort = plan;
          }
        }
      }
    }

    if (columns.isEmpty) {
      _error(UiCodes.list, ir.location, '${ir.name} has no @UiColumn field to show');
      ok = false;
    }
    final pageSize = ir.pageSize ?? searchConfig.pageSize;
    if (pageSize < 1 || pageSize > 100) {
      _error(UiCodes.list, ir.location, 'pageSize $pageSize is outside 1–100');
      ok = false;
    }
    if (!ok) return null;
    columns.sort((a, b) => a.$1.compareTo(b.$1));

    return ListPlan(
      list: ir,
      contract: contract,
      operation: operation,
      countOperation: countOperation,
      paramsClass: '${Naming.pascal(operation.operationId)}Params',
      countParamsClass: countOperation == null ? null : '${Naming.pascal(countOperation.operationId)}Params',
      responseType: page.dartName,
      itemType: item.dartName,
      columns: [for (final c in columns) c.$2],
      filters: filters,
      searchFields: searchFields,
      sorts: sorts,
      // The client always sends a sort, so the order never depends on the server's default.
      initialSort: initialSort ?? sorts.firstOrNull,
      enumLabels: enumLabels,
      requires: requires,
      title: title,
      imports: imports,
      pageSize: pageSize,
      cacheMode: ir.cacheMode ?? searchConfig.cacheMode,
      cacheTtl: ir.cacheTtl ?? searchConfig.cacheTtl,
    );
  }

  /// `game.displayName` in [item]: the leaf property, a Dart access on `item` and whether a step
  /// may be absent.
  ({PropertyIR property, String access, bool nullable})? _path(
    ObjectSchemaIR item,
    ContractIR contract,
    String path,
    String location,
  ) {
    var schema = item;
    var access = 'item';
    var nullable = false;
    final segments = path.split('.');
    for (var i = 0; i < segments.length; i++) {
      final property = schema.properties.where((p) => p.wireName == segments[i]).firstOrNull;
      if (property == null) {
        _error(
          UiCodes.unmappedField,
          location,
          '${schema.dartName} has no property "${segments[i]}"${segments.length > 1 ? ' (in "$path")' : ''}',
          hint: 'properties: ${schema.properties.map((p) => p.wireName).join(', ')}',
        );
        return null;
      }
      access = '$access${nullable ? '?' : ''}.${property.dartName}';
      nullable = nullable || !property.required || property.nullable;
      if (i == segments.length - 1) return (property: property, access: access, nullable: nullable);
      final next = property.type is RefTypeIR ? contract.schemas[(property.type as RefTypeIR).schema] : null;
      if (next is! ObjectSchemaIR) {
        _error(UiCodes.unmappedField, location, '"${segments[i]}" in "$path" is not an object');
        return null;
      }
      schema = next;
    }
    return null;
  }

  /// `game.id` → `gameId`: how stratastax-contract names a field of a related entity.
  static String _flatten(String path) {
    final segments = path.split('.');
    return [segments.first, for (final s in segments.skip(1)) s[0].toUpperCase() + s.substring(1)].join();
  }

  /// With `x-stx-search`, [name] must be one of [allowed]; without it the server decides (400).
  bool _whitelisted(List<String>? allowed, String name, String what, String where, String location) {
    if (allowed == null || allowed.contains(name)) return true;
    _error(
      UiCodes.list,
      location,
      '$where cannot $what on "$name" (x-stx-search)',
      hint: '$what fields: ${allowed.join(', ')}',
    );
    return false;
  }

  /// The cell `Msg` of a value of [leaf], as a function of the value expression.
  String Function(String v)? _cell(
    TypeIR leaf,
    SchemaIR? enumSchema,
    String location,
    Map<String, String> Function(EnumSchemaIR, String) labelsOf,
  ) {
    switch (leaf) {
      case PrimitiveTypeIR(:final kind):
        return switch (kind) {
              PrimitiveKind.string => (v) => 'Msg.data($v)',
              PrimitiveKind.email || PrimitiveKind.uuid => (v) => 'Msg.data($v.value)',
              PrimitiveKind.integer || PrimitiveKind.number => (v) => 'Msg.data(context.formats.number($v))',
              PrimitiveKind.boolean => (v) => '($v ? StxKeys.searchYes : StxKeys.searchNo)',
              PrimitiveKind.dateTime => (v) => 'Msg.data(context.formats.dateTime($v.toLocal()))',
              PrimitiveKind.date => (v) => 'Msg.data(context.formats.date($v.toDateTimeUtc()))',
              PrimitiveKind.any => null,
            } ??
            () {
              _error(UiCodes.list, location, 'a value without a type cannot be shown');
              return null;
            }();
      case RefTypeIR() when enumSchema is EnumSchemaIR:
        labelsOf(enumSchema, location);
        return (v) => '_${Naming.member(enumSchema.dartName)}Label($v)';
      default:
        _error(
          UiCodes.list,
          location,
          'only single values can be columns; point @ContractProperty at a property of it (e.g. "game.displayName")',
        );
        return null;
    }
  }

  FilterPlan? _filter(
    FieldIR field,
    FilterIR filter,
    String name,
    String label,
    TypeIR leaf,
    SchemaIR? enumSchema,
    ContractIR contract,
    List<List<String>> requires,
    Map<String, String> Function(EnumSchemaIR, String) labelsOf,
  ) {
    if (filter.source case final sourceName?) {
      final ir = ui.dataSources[sourceName];
      if (ir == null) {
        _error(UiCodes.dataSource, field.location, '$sourceName is not annotated with @UiDataSource');
        return null;
      }
      final source = _source(ir);
      if (source == null) return null;
      final leafType = switch (leaf) {
        PrimitiveTypeIR(kind: PrimitiveKind.uuid) => 'Uuid',
        PrimitiveTypeIR(kind: PrimitiveKind.string) => 'String',
        PrimitiveTypeIR(kind: PrimitiveKind.integer) => 'int',
        RefTypeIR(schema: final key) => contract.schemas[key]?.dartName,
        _ => null,
      };
      if (leafType != source.valueType) {
        _error(
          UiCodes.typeMismatch,
          field.location,
          '$sourceName gives ${source.valueType} values, but "$name" holds ${leafType ?? _describe(leaf, contract)}',
        );
        return null;
      }
      requires.add(_scopes(source.operation));
      final wire = switch (leafType) {
        'Uuid' => '(v) => v.value',
        'String' => '(v) => v',
        'int' => r"(v) => '$v'",
        _ => '(v) => v.wire',
      };
      return FilterPlan(kind: FilterKind.source, field: name, label: label, type: leafType, source: source, wire: wire);
    }
    switch (leaf) {
      case PrimitiveTypeIR(:final kind):
        return switch (kind) {
          PrimitiveKind.string || PrimitiveKind.email => FilterPlan(kind: FilterKind.text, field: name, label: label),
          PrimitiveKind.boolean => FilterPlan(kind: FilterKind.boolean, field: name, label: label),
          PrimitiveKind.integer => FilterPlan(kind: FilterKind.range, field: name, label: label, type: 'int'),
          PrimitiveKind.number => FilterPlan(kind: FilterKind.range, field: name, label: label, type: 'double'),
          PrimitiveKind.dateTime => FilterPlan(kind: FilterKind.dateRange, field: name, label: label, dateTime: true),
          PrimitiveKind.date => FilterPlan(kind: FilterKind.dateRange, field: name, label: label),
          PrimitiveKind.uuid || PrimitiveKind.any => () {
            _error(
              UiCodes.list,
              field.location,
              'no filter input for "$name" (${kind.name})',
              hint: 'pick values from a data source: @SearchFilter(source: …)',
            );
            return null;
          }(),
        };
      case RefTypeIR() when enumSchema is EnumSchemaIR:
        labelsOf(enumSchema, field.location);
        return FilterPlan(
          kind: FilterKind.choice,
          field: name,
          label: label,
          type: enumSchema.dartName,
          wire: '(v) => v.wire',
        );
      default:
        _error(
          UiCodes.list,
          field.location,
          'no filter input for "$name" (${_describe(leaf, contract)})',
          hint: 'filter on a property of it instead, e.g. @ContractProperty(\'game.id\') with a data source',
        );
        return null;
    }
  }
}
