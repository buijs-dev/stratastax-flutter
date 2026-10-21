import '../config.dart';
import '../contract/ir.dart';
import '../diagnostics.dart';
import '../i18n/i18n_frontend.dart';
import '../i18n/i18n_renderer.dart';
import '../naming.dart';
import 'annotation_frontend.dart';
import 'ui_ir.dart';

part 'list_plan.dart';

/// How a form field is rendered.
enum FieldKind { text, textArea, password, number, checkbox, select, autocomplete, date, dateTime, custom }

/// A Dart expression with the libraries it needs.
final class Code {
  const Code(this.text, [this.imports = const {}]);

  final String text;
  final Set<String> imports;
}

/// Converts a domain value to its contract value; [identity] when no conversion is needed.
final class Conversion {
  const Conversion(this.apply, {this.identity = false, this.imports = const {}});

  final String Function(String expr) apply;
  final bool identity;
  final Set<String> imports;
}

/// Merged validation rules of a field (contract ∩ UI), as `UiFieldValidation` arguments.
final class Rules {
  const Rules({
    this.required = false,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    this.pattern,
    this.format,
  });

  final bool required;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final num? minimum;
  final num? maximum;
  final String? pattern;

  /// `UiFormat` value name.
  final String? format;

  bool get isEmpty =>
      !required &&
      minLength == null &&
      maxLength == null &&
      minItems == null &&
      maxItems == null &&
      minimum == null &&
      maximum == null &&
      pattern == null &&
      format == null;
}

final class FieldPlan {
  FieldPlan({
    required this.field,
    required this.kind,
    required this.rules,
    required this.label,
    this.property,
    this.conversion,
    this.hint,
    this.help,
    this.source,
    this.widget,
    this.enumLabels = const {},
  });

  final FieldIR field;
  final FieldKind kind;
  final Rules rules;
  final PropertyIR? property;
  final Conversion? conversion;

  /// Dart expressions of the label / hint / help `Msg`s.
  final String label;
  final String? hint;
  final String? help;
  final DataSourcePlan? source;
  final FieldWidgetIR? widget;

  /// Enum value name → Msg expression, for selects.
  final Map<String, String> enumLabels;

  DartTypeRef get type => field.type;

  bool get isList => type.kind == TypeKind.list;

  bool get isBool => type.nonNull.kind == TypeKind.bool;

  /// The type the field state holds: lists stay non-null, everything else is nullable while editing.
  String get stateType => isList ? type.nonNull.code : type.withNullable(true).code;

  String get initial => isList ? 'const []' : (isBool && !type.nullable ? 'false' : 'null');

  /// Reads the validated state value as the command's field type.
  String commandValue(String state) {
    if (isList || type.nullable) return state;
    if (isBool) return '$state ?? false';
    return '$state!';
  }
}

final class DataSourcePlan {
  const DataSourcePlan({
    required this.source,
    required this.operation,
    required this.paramsClass,
    required this.queryParam,
    required this.responseType,
    required this.itemType,
    required this.itemsExpr,
    required this.valueProperty,
    required this.labelProperty,
    required this.valueType,
    required this.imports,
  });

  final DataSourceIR source;
  final OperationIR operation;
  final String paramsClass;
  final String? queryParam;
  final String responseType;
  final String itemType;

  /// `response` or `response.items`.
  final String itemsExpr;
  final String valueProperty;
  final String labelProperty;

  /// The Dart type of the option values (from the contract, e.g. `Uuid`).
  final String valueType;
  final Set<String> imports;

  String get serviceName => Naming.member(source.name);
}

final class MapperPlan {
  const MapperPlan({required this.entity, required this.schema, required this.assignments, required this.imports});

  final EntityIR entity;
  final ObjectSchemaIR schema;

  /// Contract constructor argument → expression on `v`.
  final Map<String, String> assignments;
  final Set<String> imports;
}

/// A page with a route: a form or an overview.
abstract interface class RoutedPlan {
  String get name;
  String get location;
  RouteIR? get routeIR;

  /// The page widget class.
  String get page;

  /// The route class.
  String get route;

  /// Dart expression of the title `Msg`.
  String get title;
}

final class FormPlan implements RoutedPlan {
  const FormPlan({
    required this.form,
    required this.contract,
    required this.operation,
    required this.body,
    required this.fields,
    required this.assignments,
    required this.requires,
    required this.title,
    required this.imports,
    required this.bodyType,
    required this.responseType,
  });

  final FormIR form;
  final ContractIR contract;
  final OperationIR operation;
  final ObjectSchemaIR body;
  final List<FieldPlan> fields;

  /// Contract constructor argument → expression on the command `c`.
  final Map<String, String> assignments;

  /// One group of alternative scope claims per operation the page uses.
  final List<List<String>> requires;
  @override
  final String title;
  final Set<String> imports;
  final String bodyType;
  final String responseType;

  String get base => form.name;

  @override
  String get name => form.name;

  @override
  String get location => form.location;

  @override
  RouteIR? get routeIR => form.route;

  String get controller => '${base}Form';

  @override
  String get page => '${base}Page';

  @override
  String get route => '${base.replaceFirst(RegExp(r'(Command|Form)$'), '')}Route';
}

final class AppPlan {
  const AppPlan({
    required this.package,
    required this.forms,
    required this.mappers,
    required this.sources,
    required this.appTitle,
    this.lists = const [],
  });

  final String package;
  final List<FormPlan> forms;
  final List<ListPlan> lists;

  /// Every page with a route, by path.
  List<RoutedPlan> get routed => [
    for (final page in <RoutedPlan>[...forms, ...lists])
      if (page.routeIR != null) page,
  ]..sort((a, b) => a.routeIR!.path.compareTo(b.routeIR!.path));

  /// The routed page named [name] (a `UiAction` target).
  RoutedPlan? routedNamed(String name) => routed.where((p) => p.name == name).firstOrNull;

  /// The page [page] is embedded in: the route with the longest path that is a segment prefix of
  /// its path (`/matches/new` in `/matches`); null: a top-level page.
  RoutedPlan? parentOf(RoutedPlan page) {
    final segments = _segments(page.routeIR!.path);
    RoutedPlan? parent;
    var depth = 0;
    for (final other in routed) {
      final s = _segments(other.routeIR!.path);
      if (s.length >= segments.length || s.length <= depth) continue;
      if (s.indexed.every((e) => segments[e.$1] == e.$2)) {
        parent = other;
        depth = s.length;
      }
    }
    return parent;
  }

  static List<String> _segments(String path) => path.split('/').where((s) => s.isNotEmpty).toList();
  final List<MapperPlan> mappers;
  final List<DataSourcePlan> sources;

  /// `MsgApp.title` when the translations define `app.title`.
  final String? appTitle;
}

/// Merges the UI IR with the contracts and translations, and validates the result.
final class AppPlanner {
  AppPlanner({
    required this.ui,
    required this.contracts,
    required this.i18n,
    required this.diagnostics,
    this.searchConfig = const SearchConfig(),
  });

  final UiIR ui;

  /// stx.yaml `search:`: defaults of every overview.
  final SearchConfig searchConfig;
  final List<ContractIR> contracts;
  final I18nIR i18n;
  final Diagnostics diagnostics;

  final _mappers = <String, MapperPlan>{};
  final _mapping = <String>{};
  final _sources = <String, DataSourcePlan>{};

  AppPlan plan() {
    // Every data source goes into AppServices, also those only custom field widgets use.
    for (final source in ui.dataSources.values) {
      _source(source);
    }
    final forms = [for (final form in ui.forms) ?_form(form)];
    final lists = [for (final list in ui.lists) ?_list(list)];
    final paths = <String, String>{};
    for (final page in <RoutedPlan>[...forms, ...lists]) {
      if (page.routeIR case final route?) {
        if (route.path.contains('{') || route.path.contains(':')) {
          _error(UiCodes.route, page.location, 'route parameters are not supported yet ("${route.path}")');
        }
        final existing = paths[route.path];
        if (existing != null) {
          _error(UiCodes.route, page.location, 'route "${route.path}" is also used by $existing');
        }
        paths[route.path] = page.name;
      }
    }
    final homes = [
      for (final page in <RoutedPlan>[...forms, ...lists])
        if (page.routeIR?.home ?? false) page,
    ];
    if (homes.length > 1) {
      _error(UiCodes.route, homes[1].location, '@UiRoute(home: true) is also set on ${homes.first.name}');
    }
    for (final list in lists) {
      for (final action in list.list.actions) {
        if (paths.containsValue(action)) continue;
        _error(UiCodes.route, list.location, 'UiAction($action): $action has no @UiRoute');
      }
    }
    return AppPlan(
      package: ui.package,
      forms: forms,
      mappers: [..._mappers.values]..sort((a, b) => a.entity.name.compareTo(b.entity.name)),
      sources: [..._sources.values]..sort((a, b) => a.source.name.compareTo(b.source.name)),
      lists: lists,
      appTitle: i18n.byKey('app.title') == null ? null : 'MsgApp.title',
    );
  }

  // ---------------------------------------------------------------------------------------------

  FormPlan? _form(FormIR form) {
    final resolved = _operation(form.submit, form.location);
    if (resolved == null) return null;
    final (contract, operation) = resolved;
    final bodyType = operation.body?.type;
    final body = bodyType is RefTypeIR ? contract.schemas[bodyType.schema] : null;
    if (operation.params.isNotEmpty) {
      _error(
        UiCodes.annotation,
        form.location,
        '${form.submit.apiClass}.${form.submit.member} has parameters; forms submit to operations without '
        'path/query/header parameters for now',
      );
      return null;
    }
    if (body is! ObjectSchemaIR) {
      _error(
        UiCodes.typeMismatch,
        form.location,
        '${form.submit.apiClass}.${form.submit.member} has no JSON object body; a form needs one',
      );
      return null;
    }

    final keyBase = Naming.camel(form.name);
    final title = _key(
      '$keyBase.title',
      form.location,
      seed: humanize(form.name.replaceFirst(RegExp(r'(Command|Form)$'), '')),
    );
    final imports = <String>{form.library};
    final requires = <List<String>>[_scopes(operation)];
    for (final claim in form.requires) {
      requires.add([claim]);
    }

    // Orders
    final orders = <int, String>{};
    for (final field in form.fields) {
      if (field.order case final order?) {
        if (orders[order] case final other?) {
          _error(UiCodes.order, field.location, '@UiFormOrder($order) is also used by "$other"');
        }
        orders[order] = field.name;
      }
    }
    final sorted = [...form.fields]..sort((a, b) => (a.order ?? 1 << 20).compareTo(b.order ?? 1 << 20));

    final properties = {for (final p in body.properties) p.wireName: p};
    final mapped = <String>{};
    final fields = <FieldPlan>[];
    final assignments = <String, String>{};

    for (final field in sorted) {
      final wire = field.contractProperty ?? field.name;
      final property = properties[wire];
      if (field.ignore) {
        // Not in the form: the command gets the constructor default, which is still sent when the
        // contract has a property with this name.
        if (!field.hasDefault && !field.type.nullable) {
          _error(UiCodes.annotation, field.location, '@UiIgnore field "${field.name}" needs a default value');
          continue;
        }
        if (property != null) {
          final conversion = _convert(field.type, property, contract, field.location);
          if (conversion == null) continue;
          mapped.add(wire);
          imports.addAll(conversion.imports);
          assignments[property.dartName] = _assign(property, conversion, 'c.${field.name}', field.type.nullable);
        }
        continue;
      }
      if (property == null) {
        _error(
          UiCodes.unmappedField,
          field.location,
          '"${field.name}" has no property "$wire" in ${body.dartName}',
          hint: 'map it with @ContractProperty(\'…\') or exclude it with @UiIgnore()',
        );
        continue;
      }
      mapped.add(wire);
      final conversion = _convert(field.type, property, contract, field.location);
      if (conversion == null) continue;
      imports.addAll(conversion.imports);
      imports.addAll(field.type.libraries);
      final plan = _fieldPlan(form, field, property, conversion, keyBase, contract, requires);
      if (plan == null) continue;
      fields.add(plan);
      assignments[property.dartName] = _assign(property, conversion, 'c.${field.name}', field.type.nullable);
    }

    for (final property in body.properties) {
      if (mapped.contains(property.wireName)) continue;
      if (property.required && !property.nullable && !property.patch) {
        _error(
          UiCodes.unmappedRequired,
          form.location,
          'required property "${property.wireName}" of ${body.dartName} is not mapped by ${form.name}',
        );
      } else if (property.required) {
        assignments[property.dartName] = 'null';
      }
    }

    imports.add('package:${ui.package}/gen/contract/${form.submit.contractDir}/${form.submit.contractDir}.g.dart');
    return FormPlan(
      form: form,
      contract: contract,
      operation: operation,
      body: body,
      fields: fields,
      assignments: assignments,
      requires: requires,
      title: title,
      imports: imports,
      bodyType: body.dartName,
      responseType: _responseType(operation, contract),
    );
  }

  FieldPlan? _fieldPlan(
    FormIR form,
    FieldIR field,
    PropertyIR property,
    Conversion conversion,
    String keyBase,
    ContractIR contract,
    List<List<String>> requires,
  ) {
    final type = field.type.nonNull;
    final keyField = '$keyBase.${field.name}';
    final label = field.labelKeyId != null
        ? _keyById(field.labelKeyId!, field.location)
        : _key(
            '$keyField.label',
            field.location,
            seed: _shortDescription(property.description) ?? humanize(field.name),
          );
    final hint = field.hint ? _key('$keyField.hint', field.location, seed: '${humanize(field.name)}…') : null;
    final help = field.help
        ? _key('$keyField.help', field.location, seed: _shortDescription(property.description) ?? humanize(field.name))
        : null;

    DataSourcePlan? source;
    if (field.dataSource case final name?) {
      final ir = ui.dataSources[name];
      if (ir == null) {
        _error(UiCodes.dataSource, field.location, '$name is not annotated with @UiDataSource');
        return null;
      }
      source = _source(ir);
      if (source == null) return null;
      final valueType = type.kind == TypeKind.converter ? type.converterTarget?.name : type.name;
      if (valueType != source.valueType) {
        _error(
          UiCodes.typeMismatch,
          field.location,
          '${field.type.code} cannot hold values of $name (${source.valueType})',
          hint: 'use ${source.valueType}, or a @BuildTypeConverter(${source.valueType}) type',
        );
        return null;
      }
      requires.add(_scopes(source.operation));
    }

    FieldWidgetIR? widget;
    if (field.widget case final name?) {
      widget = ui.fieldWidgets[name];
      if (widget == null) {
        _error(UiCodes.widgetType, field.location, '$name is not annotated with @UiFieldWidget()');
        return null;
      }
      final state = type.kind == TypeKind.list ? type.code : type.withNullable(true).code;
      if (widget.valueType?.code != state) {
        _error(
          UiCodes.widgetType,
          field.location,
          '$name edits ${widget.valueType?.code}, but "${field.name}" needs StxFieldWidget<$state>',
        );
        return null;
      }
    }

    final kind = _kind(field, type, source, widget);
    if (kind == null) return null;

    var enumLabels = const <String, String>{};
    if (kind == FieldKind.select) {
      enumLabels = {
        for (final value in type.enumValues)
          value: _key('enum.${type.name}.$value', field.location, seed: humanize(value)),
      };
    }

    final rules = _rules(field, property, type);
    if (rules == null) return null;
    return FieldPlan(
      field: field,
      kind: kind,
      rules: rules,
      label: label,
      property: property,
      conversion: conversion,
      hint: hint,
      help: help,
      source: source,
      widget: widget,
      enumLabels: enumLabels,
    );
  }

  FieldKind? _kind(FieldIR field, DartTypeRef type, DataSourcePlan? source, FieldWidgetIR? widget) {
    if (widget != null) return FieldKind.custom;
    if (source != null) {
      if (type.kind == TypeKind.list) {
        _error(
          UiCodes.typeMismatch,
          field.location,
          'multi-select data sources are not supported yet; use a @UiFieldWidget',
        );
        return null;
      }
      return FieldKind.autocomplete;
    }
    final inferred = switch (type.kind) {
      TypeKind.string => FieldKind.text,
      TypeKind.int || TypeKind.double => FieldKind.number,
      TypeKind.bool => FieldKind.checkbox,
      TypeKind.dateTime => FieldKind.dateTime,
      TypeKind.localDate => FieldKind.date,
      TypeKind.enumType => FieldKind.select,
      _ => null,
    };
    final explicit = field.kind;
    if (explicit != null) {
      final allowed = switch (explicit) {
        'text' || 'textArea' || 'password' => type.kind == TypeKind.string,
        'number' => inferred == FieldKind.number,
        'checkbox' => inferred == FieldKind.checkbox,
        'select' => inferred == FieldKind.select,
        'date' => inferred == FieldKind.date,
        'dateTime' => inferred == FieldKind.dateTime,
        'autocomplete' || 'multiAutocomplete' => false, // needs a data source
        _ => false,
      };
      if (!allowed) {
        _error(
          UiCodes.typeMismatch,
          field.location,
          '@UiFieldType(UiFieldType.$explicit) does not fit ${field.type.code}'
          '${explicit.contains('utocomplete') ? ' without @UiFieldDataSource' : ''}',
        );
        return null;
      }
      return FieldKind.values.firstWhere((k) => k.name == explicit);
    }
    if (inferred == null) {
      _error(
        UiCodes.typeMismatch,
        field.location,
        'no input for ${field.type.code}',
        hint: 'add @UiFieldDataSource(…) or @UiFieldWidget(…)',
      );
    }
    return inferred;
  }

  /// Contract constraints, tightened by `@UiFieldValidate`; loosening is an error.
  Rules? _rules(FieldIR field, PropertyIR property, DartTypeRef type) {
    final c = property.constraints;
    final ui = field.validate;
    var ok = true;
    int? tighterMax(int? contract, int? annotation, String name) {
      if (annotation != null && contract != null && annotation > contract) {
        _error(UiCodes.loosened, field.location, '$name $annotation is looser than the contract ($contract)');
        ok = false;
      }
      return annotation ?? contract;
    }

    int? tighterMin(int? contract, int? annotation, String name) {
      if (annotation != null && contract != null && annotation < contract) {
        _error(UiCodes.loosened, field.location, '$name $annotation is looser than the contract ($contract)');
        ok = false;
      }
      return annotation ?? contract;
    }

    if (ui.pattern != null && c.pattern != null && ui.pattern != c.pattern) {
      _error(UiCodes.loosened, field.location, 'the contract already has a pattern; a second one cannot be combined');
      ok = false;
    }
    final contractRequired = property.required && !property.nullable;
    if (ui.required == false && contractRequired) {
      _error(UiCodes.loosened, field.location, 'required: false is looser than the contract');
      ok = false;
    }
    final isString = type.kind == TypeKind.string;
    final isNum = type.kind == TypeKind.int || type.kind == TypeKind.double;
    final isList = type.kind == TypeKind.list;
    final rules = Rules(
      required:
          !isList && (!field.type.nullable && type.kind != TypeKind.bool || contractRequired || ui.required == true),
      minLength: isString ? tighterMin(c.minLength, ui.minLength, 'minLength') : null,
      maxLength: isString ? tighterMax(c.maxLength, ui.maxLength, 'maxLength') : null,
      minItems: isList ? tighterMin(c.minItems, ui.minItems, 'minItems') : null,
      maxItems: isList ? tighterMax(c.maxItems, ui.maxItems, 'maxItems') : null,
      minimum: isNum ? (ui.minimum ?? c.minimum) : null,
      maximum: isNum ? (ui.maximum ?? c.maximum) : null,
      pattern: isString ? (ui.pattern ?? c.pattern) : null,
      format: isString
          ? switch (c.format) {
              'email' => 'email',
              'uri' => 'uri',
              'uuid' => 'uuid',
              _ => null,
            }
          : null,
    );
    if (isNum) {
      if (ui.minimum != null && c.minimum != null && ui.minimum! < c.minimum!) {
        _error(UiCodes.loosened, field.location, 'minimum ${ui.minimum} is looser than the contract (${c.minimum})');
        ok = false;
      }
      if (ui.maximum != null && c.maximum != null && ui.maximum! > c.maximum!) {
        _error(UiCodes.loosened, field.location, 'maximum ${ui.maximum} is looser than the contract (${c.maximum})');
        ok = false;
      }
    }
    return ok ? rules : null;
  }

  // ---------------------------------------------------------------------------------------------
  // Type mapping

  Conversion? _convert(DartTypeRef type, PropertyIR property, ContractIR contract, String location) {
    if (type.nullable && property.required && !property.nullable) {
      _error(
        UiCodes.typeMismatch,
        location,
        '${type.code} may be null but "${property.wireName}" is required in the contract',
      );
      return null;
    }
    return _map(type.nonNull, property.type, contract, location, 0);
  }

  Conversion? _map(DartTypeRef type, TypeIR target, ContractIR contract, String location, int depth) {
    Conversion? mismatch() {
      _error(
        UiCodes.typeMismatch,
        location,
        '${type.code} cannot be sent as ${_describe(target, contract)}',
        hint: 'use the contract type, or annotate ${type.name} with @BuildTypeConverter',
      );
      return null;
    }

    if (target is PrimitiveTypeIR && target.kind == PrimitiveKind.any) return Conversion((e) => e, identity: true);
    switch (type.kind) {
      case TypeKind.converter:
        final inner = type.converterTarget;
        if (inner == null || type.representation == null) return mismatch();
        final next = _map(inner, target, contract, location, depth);
        if (next == null) return null;
        return Conversion((e) => next.apply('$e.${type.representation}'), imports: next.imports);
      case TypeKind.list:
        if (target is! ListTypeIR || type.args.length != 1) return mismatch();
        final item = _map(type.args.single.nonNull, target.item, contract, location, depth + 1);
        if (item == null) return null;
        if (item.identity) return Conversion((e) => e, identity: true);
        final v = 'e$depth';
        return Conversion((e) => '[for (final $v in $e) ${item.apply(v)}]', imports: item.imports);
      case TypeKind.entity:
        if (target is! RefTypeIR || contract.schemas[target.schema] is! ObjectSchemaIR) return mismatch();
        final entity = ui.entities[type.name];
        if (entity == null) return mismatch();
        _mapper(entity, contract.schemas[target.schema]! as ObjectSchemaIR, contract);
        return Conversion((e) => '${entity.name}Mapper.toContract($e)');
      case TypeKind.enumType || TypeKind.contractModel:
        if (target is RefTypeIR && contract.schemas[target.schema]?.dartName == type.name && type.isContract) {
          return Conversion((e) => e, identity: true);
        }
        return mismatch();
      default:
        final expected = switch (type.kind) {
          TypeKind.string => PrimitiveKind.string,
          TypeKind.int => PrimitiveKind.integer,
          TypeKind.double => PrimitiveKind.number,
          TypeKind.bool => PrimitiveKind.boolean,
          TypeKind.dateTime => PrimitiveKind.dateTime,
          TypeKind.localDate => PrimitiveKind.date,
          TypeKind.uuid => PrimitiveKind.uuid,
          TypeKind.email => PrimitiveKind.email,
          _ => null,
        };
        if (target is PrimitiveTypeIR && target.kind == expected) return Conversion((e) => e, identity: true);
        return mismatch();
    }
  }

  void _mapper(EntityIR entity, ObjectSchemaIR schema, ContractIR contract) {
    final key = '${entity.name}→${schema.key}';
    if (_mappers.containsKey(entity.name) || !_mapping.add(key)) return;
    final properties = {for (final p in schema.properties) p.wireName: p};
    final mapped = <String>{};
    final assignments = <String, String>{};
    final imports = <String>{entity.library};
    for (final field in entity.fields) {
      final wire = field.contractProperty ?? field.name;
      final property = properties[wire];
      if (field.ignore && property == null) continue;
      if (property == null) {
        _error(
          UiCodes.unmappedField,
          field.location,
          '"${field.name}" has no property "$wire" in ${schema.dartName}',
          hint: 'map it with @ContractProperty(\'…\') or exclude it with @UiIgnore()',
        );
        continue;
      }
      mapped.add(wire);
      final conversion = _convert(field.type, property, contract, field.location);
      if (conversion == null) continue;
      imports
        ..addAll(conversion.imports)
        ..addAll(field.type.libraries);
      assignments[property.dartName] = _assign(property, conversion, 'v.${field.name}', field.type.nullable);
    }
    for (final property in schema.properties) {
      if (mapped.contains(property.wireName)) continue;
      if (property.required && !property.nullable) {
        _error(
          UiCodes.unmappedRequired,
          entity.location,
          'required property "${property.wireName}" of ${schema.dartName} is not mapped by ${entity.name}',
        );
      } else if (property.required) {
        assignments[property.dartName] = 'null';
      }
    }
    _mappers[entity.name] = MapperPlan(entity: entity, schema: schema, assignments: assignments, imports: imports);
  }

  String _assign(PropertyIR property, Conversion conversion, String expr, bool nullable) {
    final value = !nullable || conversion.identity
        ? conversion.apply(expr)
        : 'switch ($expr) { final x? => ${conversion.apply('x')}, null => null }';
    return property.patch ? 'Patch.value($value)' : value;
  }

  // ---------------------------------------------------------------------------------------------
  // Data sources

  DataSourcePlan? _source(DataSourceIR ir) {
    if (_sources[ir.name] case final existing?) return existing;
    final resolved = _operation(ir.endpoint, ir.location);
    if (resolved == null) return null;
    final (contract, operation) = resolved;
    final response = operation.response;

    RefTypeIR? item;
    var itemsExpr = 'response';
    if (response is ListTypeIR && response.item is RefTypeIR) {
      item = response.item as RefTypeIR;
    } else if (response is RefTypeIR) {
      final schema = contract.schemas[response.schema];
      final items = schema is ObjectSchemaIR ? schema.properties.where((p) => p.wireName == 'items').firstOrNull : null;
      if (items?.type case ListTypeIR(item: final RefTypeIR ref)) {
        item = ref;
        itemsExpr = 'response.items';
      }
    }
    final itemSchema = item == null ? null : contract.schemas[item.schema];
    if (itemSchema is! ObjectSchemaIR) {
      _error(
        UiCodes.dataSource,
        ir.location,
        '${operation.operationId} returns no list of objects (or an object with "items")',
      );
      return null;
    }
    PropertyIR? prop(String name) => itemSchema.properties.where((p) => p.wireName == name).firstOrNull;
    final value = prop(ir.value);
    final label = prop(ir.label);
    if (value == null || label == null) {
      _error(
        UiCodes.dataSource,
        ir.location,
        '${itemSchema.dartName} has no property "${value == null ? ir.value : ir.label}"',
        hint: 'properties: ${itemSchema.properties.map((p) => p.wireName).join(', ')}',
      );
      return null;
    }
    if (label.type case PrimitiveTypeIR(kind: PrimitiveKind.string)) {
    } else {
      _error(UiCodes.dataSource, ir.location, 'label "${ir.label}" must be a string property');
      return null;
    }
    final valueType = switch (value.type) {
      PrimitiveTypeIR(kind: PrimitiveKind.uuid) => 'Uuid',
      PrimitiveTypeIR(kind: PrimitiveKind.string) => 'String',
      PrimitiveTypeIR(kind: PrimitiveKind.integer) => 'int',
      RefTypeIR(schema: final key) => contract.schemas[key]!.dartName,
      _ => null,
    };
    if (valueType == null || !value.required || value.nullable) {
      _error(UiCodes.dataSource, ir.location, 'value "${ir.value}" must be a required id, string, int or enum');
      return null;
    }

    final query = operation.params.where((p) => p.wireName == ir.query).firstOrNull;
    if (ir.query != null && query == null) {
      _error(
        UiCodes.dataSource,
        ir.location,
        '${operation.operationId} has no query parameter "${ir.query}"',
        hint: 'parameters: ${operation.params.map((p) => p.wireName).join(', ')}',
      );
      return null;
    }
    if (query != null) {
      if (query.type case PrimitiveTypeIR(kind: PrimitiveKind.string)) {
      } else {
        _error(UiCodes.dataSource, ir.location, 'query parameter "${ir.query}" must be a string');
        return null;
      }
    }
    for (final param in operation.params) {
      if (param != query && param.required) {
        _error(
          UiCodes.dataSource,
          ir.location,
          '${operation.operationId} requires parameter "${param.wireName}", which a data source cannot fill',
        );
        return null;
      }
    }
    final queryParam = query?.dartName;

    final plan = DataSourcePlan(
      source: ir,
      operation: operation,
      paramsClass: operation.params.isEmpty ? 'NoParams' : '${Naming.pascal(operation.operationId)}Params',
      queryParam: queryParam,
      responseType: _responseType(operation, contract),
      itemType: itemSchema.dartName,
      itemsExpr: itemsExpr,
      valueProperty: value.dartName,
      labelProperty: label.dartName,
      valueType: valueType,
      imports: {'package:${ui.package}/gen/contract/${ir.endpoint.contractDir}/${ir.endpoint.contractDir}.g.dart'},
    );
    _sources[ir.name] = plan;
    return plan;
  }

  // ---------------------------------------------------------------------------------------------

  (ContractIR, OperationIR)? _operation(EndpointRef ref, String location) {
    for (final contract in contracts) {
      if (Naming.snake(contract.name) != ref.contractDir) continue;
      for (final operation in contract.operations) {
        if (operation.operationId == ref.operationId) return (contract, operation);
      }
    }
    _error(UiCodes.annotation, location, 'operation "${ref.operationId}" not found in the contracts');
    return null;
  }

  List<String> _scopes(OperationIR operation) => switch (operation.security) {
    ScopedSecurity(:final scopes) => scopes,
    _ => const [],
  };

  String _responseType(OperationIR operation, ContractIR contract) {
    final response = operation.response;
    if (response == null) return 'NoContent';
    String type(TypeIR t) => switch (t) {
      RefTypeIR(schema: final key) => contract.schemas[key]!.dartName,
      ListTypeIR(:final item) => 'List<${type(item)}>',
      MapTypeIR(value: null) => 'Map<String, Object?>',
      MapTypeIR(:final value) => 'Map<String, ${type(value!)}>',
      PrimitiveTypeIR(:final kind) => switch (kind) {
        PrimitiveKind.string => 'String',
        PrimitiveKind.integer => 'int',
        PrimitiveKind.number => 'double',
        PrimitiveKind.boolean => 'bool',
        PrimitiveKind.uuid => 'Uuid',
        PrimitiveKind.dateTime => 'DateTime',
        PrimitiveKind.date => 'LocalDate',
        PrimitiveKind.email => 'Email',
        PrimitiveKind.any => 'Object?',
      },
    };
    return type(response);
  }

  String _describe(TypeIR target, ContractIR contract) => switch (target) {
    PrimitiveTypeIR(:final kind) => kind.name,
    RefTypeIR(schema: final key) => contract.schemas[key]!.dartName,
    ListTypeIR(:final item) => 'a list of ${_describe(item, contract)}',
    MapTypeIR() => 'an object',
  };

  /// Keys a page needs that the base locale lacks, with a suggested text (`stx i18n sync`).
  final missingKeys = <String, String>{};

  /// A contract description short enough to serve as a label.
  static String? _shortDescription(String? description) {
    final text = description?.trim();
    return text == null || text.isEmpty || text.contains('\n') || text.length > 60 ? null : text;
  }

  /// A required translation key; returns the Dart expression of its `Msg`.
  String _key(String key, String location, {required String seed}) {
    final message = i18n.byKey(key);
    if (message == null) {
      missingKeys[key] = seed;
      diagnostics.error(
        I18nCodes.missingBase,
        'missing translation "$key" in the base locale (${i18n.base})',
        location: location,
        hint: 'run `stx i18n sync`, or add it to i18n/${i18n.base}.yaml (and the other locales)',
      );
      return 'StxKeys.stateEmpty';
    }
    return _msgExpr(message);
  }

  String _keyById(int id, String location) {
    if (id < 0 || id >= i18n.messages.length) {
      _error(UiCodes.annotation, location, 'unknown message key id $id (stale lib/gen? run stx build)');
      return 'StxKeys.stateEmpty';
    }
    return _msgExpr(i18n.messages[id]);
  }

  String _msgExpr(MessageIR message) {
    if (message.isFramework) {
      final rest = message.key.split('.').skip(1).map(Naming.pascal).join();
      return 'StxKeys.${Naming.member(rest)}';
    }
    final name = msgName(message.key);
    return '${name.className}.${name.member}';
  }

  void _error(String code, String location, String message, {String? hint}) =>
      diagnostics.error(code, message, location: location, hint: hint);
}

/// `playedAt` → `Played at`, `WIN_LOSS` → `Win loss`, `MatchCreate` → `Match create`.
String humanize(String name) {
  final words = Naming.words(name);
  if (words.isEmpty) return name;
  return [words.first[0].toUpperCase() + words.first.substring(1), ...words.skip(1)].join(' ');
}
