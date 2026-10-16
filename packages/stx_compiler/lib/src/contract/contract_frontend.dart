import 'dart:io';

import 'package:yaml/yaml.dart';

import '../config.dart';
import '../diagnostics.dart';
import '../naming.dart';
import 'ir.dart';

/// Parses one bundled OpenAPI 3.x document into a [ContractIR].
///
/// The input is the bundled artifact (`build/openapi/openapi-v1.yaml`), so every `$ref` is local
/// (`#/components/...`). Like `OpenApiOperationParser` in stratastax-codegen, the root-level
/// `security` is ignored: every operation must declare its own.
final class ContractFrontend {
  ContractFrontend(this.config, this.diagnostics);

  final ContractConfig config;
  final Diagnostics diagnostics;

  late Map<String, Object?> _root;
  late String _source;

  final Map<String, SchemaIR> _schemas = {};

  /// Dart name → schema key, to detect collisions; filled before a schema is converted so
  /// recursive schemas terminate.
  final Map<String, String> _dartNames = {};

  /// Reads and parses [ContractConfig.spec]; null when the file cannot be read.
  ContractIR? parseFile() {
    final file = File(config.spec);
    if (!file.existsSync()) {
      diagnostics.error(ContractCodes.unreadable, 'spec not found', location: config.displaySpec);
      return null;
    }
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
    } on YamlException catch (e) {
      diagnostics.error(ContractCodes.unreadable, 'invalid YAML: ${e.message}', location: config.displaySpec);
      return null;
    }
    final root = _plain(yaml);
    if (root is! Map<String, Object?>) {
      diagnostics.error(ContractCodes.unreadable, 'expected an OpenAPI document', location: config.displaySpec);
      return null;
    }
    return parse(root, source: config.displaySpec);
  }

  /// Parses a document from YAML text (tests, tooling).
  ContractIR parseSource(String yaml, {String source = 'spec.yaml'}) {
    final root = _plain(loadYaml(yaml));
    return parse(root is Map<String, Object?> ? root : const {}, source: source);
  }

  /// Parses an already loaded document; [source] is only used in locations.
  ContractIR parse(Map<String, Object?> root, {required String source}) {
    _root = root;
    _source = source;

    final schemas = _map(_map(root['components'])['schemas']);
    for (final key in schemas.keys.toList()..sort()) {
      final node = _map(schemas[key]);
      if (_isNamed(node)) _component(key);
    }

    final operations = _operations();
    _markPatchBodies(operations);

    final sortedSchemas = {for (final key in _schemas.keys.toList()..sort()) key: _schemas[key]!};
    operations.sort((a, b) {
      final byTag = a.tag.compareTo(b.tag);
      return byTag != 0 ? byTag : a.operationId.compareTo(b.operationId);
    });
    _checkTypeNames(operations);

    return ContractIR(
      name: config.name,
      source: source,
      modelSuffix: config.modelSuffix,
      apiSuffix: config.apiSuffix,
      schemas: sortedSchemas,
      operations: operations,
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Schemas

  /// Schemas that become a Dart type of their own; everything else (aliases such as `date_time`
  /// or `display_name`) is inlined where it is used.
  bool _isNamed(Map<String, Object?> node) =>
      node.containsKey('enum') || node.containsKey('properties') || node.containsKey('allOf');

  /// Ensures the component schema [key] is converted and returns it.
  void _component(String key) {
    if (_schemas.containsKey(key) || _dartNames.containsValue(key)) return;
    final pointer = '/components/schemas/${_escape(key)}';
    final node = _map(_map(_map(_root['components'])['schemas'])[key]);
    _convertNamed(node, pointer, key: key, base: Naming.pascal(key));
  }

  void _convertNamed(Map<String, Object?> node, String pointer, {required String key, required String base}) {
    final dartName = '$base${config.modelSuffix}';
    final existing = _dartNames[dartName];
    if (existing != null && existing != key) {
      diagnostics.error(
        ContractCodes.nameCollision,
        'schema "$key" and "$existing" both map to $dartName',
        location: _at(pointer),
      );
      return;
    }
    _dartNames[dartName] = key;
    final description = node['description'] as String?;

    if (node.containsKey('enum')) {
      _schemas[key] = _enum(node, pointer, key, dartName, description);
      return;
    }

    final collected = <String, ({Map<String, Object?> node, String pointer})>{};
    final required = <String>{};
    _collectProperties(node, pointer, collected, required, {});

    final properties = <PropertyIR>[];
    final usedNames = <String>{};
    for (final entry in collected.entries) {
      final wire = entry.key;
      final typed = _type(entry.value.node, entry.value.pointer, '$base${Naming.pascal(wire)}');
      var dartName = Naming.member(wire);
      while (!usedNames.add(dartName)) {
        dartName = '$dartName\$';
      }
      properties.add(
        PropertyIR(
          wireName: wire,
          dartName: dartName,
          type: typed.type,
          required: required.contains(wire),
          nullable: typed.nullable || entry.value.node['nullable'] == true,
          constraints: typed.constraints,
          description: typed.description,
        ),
      );
    }
    _schemas[key] = ObjectSchemaIR(
      key: key,
      dartName: dartName,
      location: _at(pointer),
      properties: properties,
      description: description,
    );
  }

  /// Flattens `properties`, `required` and `allOf` (including `$ref`'d parts) into one property list.
  void _collectProperties(
    Map<String, Object?> node,
    String pointer,
    Map<String, ({Map<String, Object?> node, String pointer})> properties,
    Set<String> required,
    Set<String> visited,
  ) {
    if (node[r'$ref'] case final String ref) {
      final target = _resolve(ref, pointer);
      if (target == null || !visited.add(target.pointer)) return;
      _collectProperties(target.node, target.pointer, properties, required, visited);
      return;
    }
    final allOf = node['allOf'];
    if (allOf is List) {
      for (var i = 0; i < allOf.length; i++) {
        _collectProperties(_map(allOf[i]), '$pointer/allOf/$i', properties, required, visited);
      }
    }
    final own = _map(node['properties']);
    for (final entry in own.entries) {
      properties[entry.key] = (node: _map(entry.value), pointer: '$pointer/properties/${_escape(entry.key)}');
    }
    final requiredList = node['required'];
    if (requiredList is List) required.addAll(requiredList.map((e) => e.toString()));
  }

  EnumSchemaIR _enum(Map<String, Object?> node, String pointer, String key, String dartName, String? description) {
    final values = <EnumValueIR>[];
    final used = <String>{};
    for (final value in node['enum'] as List) {
      if (value == null) continue; // `enum: [A, B, null]` in a nullable enum
      if (value is! String) {
        diagnostics.error(
          ContractCodes.unsupported,
          'only string enums are supported, found $value',
          location: _at(pointer),
        );
        continue;
      }
      var name = Naming.enumValue(value);
      for (var i = 2; !used.add(name); i++) {
        name = '${Naming.enumValue(value)}$i';
      }
      values.add(EnumValueIR(value, name));
    }
    return EnumSchemaIR(key: key, dartName: dartName, location: _at(pointer), values: values, description: description);
  }

  /// Resolves the type of a schema node. Named inline schemas (objects with properties, enums) are
  /// registered under [nameHint].
  _Typed _type(Map<String, Object?> node, String pointer, String nameHint) {
    final description = node['description'] as String?;

    if (node[r'$ref'] case final String ref) {
      final target = _resolve(ref, pointer);
      if (target == null) return const _Typed(PrimitiveTypeIR(PrimitiveKind.any));
      final key = _componentKey(target.pointer);
      if (key != null && _isNamed(target.node)) {
        _component(key);
        return _Typed(RefTypeIR(key), description: description ?? target.node['description'] as String?);
      }
      // An alias such as `date_time` or `display_name`: inline it, keep its constraints.
      final inner = _type(target.node, target.pointer, key == null ? nameHint : Naming.pascal(key));
      return _Typed(
        inner.type,
        nullable: inner.nullable,
        constraints: inner.constraints.mergedWith(_constraints(node)),
        description: description ?? inner.description,
      );
    }

    for (final keyword in const ['anyOf', 'oneOf']) {
      final options = node[keyword];
      if (options is! List) continue;
      final nonNull = [
        for (var i = 0; i < options.length; i++)
          if (_map(options[i])['type'] != 'null') (node: _map(options[i]), pointer: '$pointer/$keyword/$i'),
      ];
      if (nonNull.length == 1 && options.length == 2) {
        final inner = _type(nonNull.single.node, nonNull.single.pointer, nameHint);
        return _Typed(inner.type, nullable: true, constraints: inner.constraints, description: description);
      }
      diagnostics.error(
        ContractCodes.unsupported,
        '$keyword is only supported as "<schema> or null"',
        location: _at(pointer),
        hint: 'model alternatives with a discriminator (planned) or a single schema',
      );
      return const _Typed(PrimitiveTypeIR(PrimitiveKind.any));
    }

    var nullable = false;
    String? typeName;
    switch (node['type']) {
      case final String t:
        typeName = t;
      case final List<Object?> types:
        nullable = types.contains('null');
        final rest = types.where((t) => t != 'null').toList();
        if (rest.length == 1) {
          typeName = rest.single.toString();
        } else if (rest.length > 1) {
          diagnostics.error(ContractCodes.unsupported, 'union types $types are not supported', location: _at(pointer));
          return const _Typed(PrimitiveTypeIR(PrimitiveKind.any));
        }
    }

    final constraints = _constraints(node);
    _Typed typed(TypeIR type) => _Typed(type, nullable: nullable, constraints: constraints, description: description);

    if (node.containsKey('enum') || node.containsKey('properties') || node.containsKey('allOf')) {
      if (node.containsKey('allOf') && !node.containsKey('properties')) {
        final parts = node['allOf'] as List;
        if (parts.length == 1) {
          final inner = _type(_map(parts.single), '$pointer/allOf/0', nameHint);
          return _Typed(inner.type, nullable: nullable || inner.nullable, constraints: inner.constraints);
        }
      }
      if (!_schemas.containsKey(nameHint) && !_dartNames.containsValue(nameHint)) {
        _convertNamed(node, pointer, key: nameHint, base: nameHint);
      }
      return typed(RefTypeIR(nameHint));
    }

    switch (typeName) {
      case 'object' || null when node.containsKey('additionalProperties'):
        final additional = node['additionalProperties'];
        if (additional is Map) {
          final value = _type(_map(additional), '$pointer/additionalProperties', '${nameHint}Value');
          return typed(MapTypeIR(value.type));
        }
        return typed(const MapTypeIR(null));
      case 'object':
        return typed(const MapTypeIR(null));
      case 'array':
        final items = _type(_map(node['items']), '$pointer/items', '${nameHint}Item');
        if (items.nullable) {
          diagnostics.warning(
            ContractCodes.unsupported,
            'nullable array items are decoded as non-null',
            location: _at('$pointer/items'),
          );
        }
        return typed(ListTypeIR(items.type));
      case 'string':
        return typed(
          PrimitiveTypeIR(switch (node['format']) {
            'uuid' => PrimitiveKind.uuid,
            'date-time' => PrimitiveKind.dateTime,
            'date' => PrimitiveKind.date,
            'email' => PrimitiveKind.email,
            _ => PrimitiveKind.string,
          }),
        );
      case 'integer':
        return typed(const PrimitiveTypeIR(PrimitiveKind.integer));
      case 'number':
        return typed(const PrimitiveTypeIR(PrimitiveKind.number));
      case 'boolean':
        return typed(const PrimitiveTypeIR(PrimitiveKind.boolean));
      case null:
        return typed(const PrimitiveTypeIR(PrimitiveKind.any));
      default:
        diagnostics.error(ContractCodes.unsupported, 'type "$typeName" is not supported', location: _at(pointer));
        return typed(const PrimitiveTypeIR(PrimitiveKind.any));
    }
  }

  ConstraintIR _constraints(Map<String, Object?> node) {
    // OpenAPI 3.0: exclusiveMinimum is a flag; 3.1: it is the bound itself.
    num? minimum = node['minimum'] as num?;
    var exclusiveMinimum = node['exclusiveMinimum'] == true;
    if (node['exclusiveMinimum'] case final num bound) {
      minimum = bound;
      exclusiveMinimum = true;
    }
    num? maximum = node['maximum'] as num?;
    var exclusiveMaximum = node['exclusiveMaximum'] == true;
    if (node['exclusiveMaximum'] case final num bound) {
      maximum = bound;
      exclusiveMaximum = true;
    }
    return ConstraintIR(
      minLength: node['minLength'] as int?,
      maxLength: node['maxLength'] as int?,
      minItems: node['minItems'] as int?,
      maxItems: node['maxItems'] as int?,
      minimum: minimum,
      maximum: maximum,
      exclusiveMinimum: exclusiveMinimum,
      exclusiveMaximum: exclusiveMaximum,
      pattern: node['pattern'] as String?,
      format: node['format'] as String?,
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Operations

  static const _methods = {
    'get': HttpMethodIR.get,
    'head': HttpMethodIR.head,
    'post': HttpMethodIR.post,
    'put': HttpMethodIR.put,
    'patch': HttpMethodIR.patch,
    'delete': HttpMethodIR.delete,
  };

  List<OperationIR> _operations() {
    final operations = <OperationIR>[];
    final paths = _map(_root['paths']);
    for (final path in paths.keys.toList()..sort()) {
      var pointer = '/paths/${_escape(path)}';
      var item = _map(paths[path]);
      if (item[r'$ref'] case final String ref) {
        final target = _resolve(ref, pointer);
        if (target == null) continue;
        (pointer: pointer, node: item) = (pointer: target.pointer, node: target.node);
      }
      for (final entry in _methods.entries) {
        final node = item[entry.key];
        if (node is! Map<String, Object?>) continue;
        final operation = _operation(path, entry.value, node, '$pointer/${entry.key}', item, pointer);
        if (operation != null) operations.add(operation);
      }
    }
    return operations;
  }

  OperationIR? _operation(
    String path,
    HttpMethodIR method,
    Map<String, Object?> node,
    String pointer,
    Map<String, Object?> pathItem,
    String pathPointer,
  ) {
    final operationId = node['operationId'];
    if (operationId is! String || operationId.isEmpty) {
      diagnostics.error(
        ContractCodes.missingOperationId,
        '${method.name.toUpperCase()} $path has no operationId',
        location: _at(pointer),
      );
      return null;
    }
    final base = Naming.pascal(operationId);

    // Path-level parameters, overridden by operation-level ones with the same name and location.
    final declared = <String, ({Map<String, Object?> node, String pointer})>{};
    void addParameters(Object? list, String listPointer) {
      if (list is! List) return;
      for (var i = 0; i < list.length; i++) {
        var paramPointer = '$listPointer/$i';
        var param = _map(list[i]);
        if (param[r'$ref'] case final String ref) {
          final target = _resolve(ref, paramPointer);
          if (target == null) continue;
          (param, paramPointer) = (target.node, target.pointer);
        }
        declared['${param['in']}:${param['name']}'] = (node: param, pointer: paramPointer);
      }
    }

    addParameters(pathItem['parameters'], '$pathPointer/parameters');
    addParameters(node['parameters'], '$pointer/parameters');

    var idempotent = false;
    final params = <ParamIR>[];
    final usedNames = <String>{};
    for (final param in declared.values) {
      final name = param.node['name']?.toString() ?? '';
      final location = switch (param.node['in']) {
        'path' => ParamLocation.path,
        'query' => ParamLocation.query,
        'header' => ParamLocation.header,
        final other => () {
          diagnostics.warning(
            ContractCodes.unsupported,
            'parameter "$name" in $other is ignored',
            location: _at(param.pointer),
          );
          return null;
        }(),
      };
      if (location == null) continue;
      if (location == ParamLocation.header && name.toLowerCase() == 'idempotency-key') {
        idempotent = true;
        continue;
      }
      final typed = _type(_map(param.node['schema']), '${param.pointer}/schema', '$base${Naming.pascal(name)}');
      var dartName = Naming.member(name);
      while (!usedNames.add(dartName)) {
        dartName = '$dartName\$';
      }
      params.add(
        ParamIR(
          wireName: name,
          dartName: dartName,
          location: location,
          type: typed.type,
          required: location == ParamLocation.path || param.node['required'] == true,
          constraints: typed.constraints,
          description: param.node['description'] as String?,
        ),
      );
    }

    return OperationIR(
      operationId: operationId,
      dartName: Naming.member(operationId),
      tag: (node['tags'] as List?)?.firstOrNull?.toString() ?? 'default',
      method: method,
      path: path,
      params: params,
      body: _body(node['requestBody'], '$pointer/requestBody', base),
      response: _response(_map(node['responses']), '$pointer/responses', base),
      security: _security(node, pointer, operationId),
      idempotent: idempotent,
      location: _at(pointer),
      summary: node['summary'] as String?,
      description: node['description'] as String?,
    );
  }

  BodyIR? _body(Object? requestBody, String pointer, String base) {
    if (requestBody is! Map<String, Object?>) return null;
    var node = requestBody;
    var at = pointer;
    if (node[r'$ref'] case final String ref) {
      final target = _resolve(ref, pointer);
      if (target == null) return null;
      (node, at) = (target.node, target.pointer);
    }
    final content = _map(node['content']);
    if (content.containsKey('application/json')) {
      final schema = _map(_map(content['application/json'])['schema']);
      final typed = _type(schema, '$at/content/application~1json/schema', '${base}Request');
      return BodyIR(type: typed.type, contentType: 'application/json');
    }
    for (final type in content.keys.toList()..sort()) {
      final schema = _map(_map(content[type])['schema']);
      if (schema['type'] == 'string') {
        return BodyIR(type: const PrimitiveTypeIR(PrimitiveKind.string), contentType: type);
      }
    }
    diagnostics.error(
      ContractCodes.unsupported,
      'request body content ${content.keys.toList()} is not supported',
      location: _at(at),
      hint: 'use application/json, or a string schema for text content',
    );
    return null;
  }

  TypeIR? _response(Map<String, Object?> responses, String pointer, String base) {
    final success = responses.keys.where((code) => code.startsWith('2')).toList()..sort();
    if (success.isEmpty) return null;
    final code = success.first;
    var node = _map(responses[code]);
    var at = '$pointer/$code';
    if (node[r'$ref'] case final String ref) {
      final target = _resolve(ref, at);
      if (target == null) return null;
      (node, at) = (target.node, target.pointer);
    }
    final json = _map(_map(node['content'])['application/json']);
    if (!json.containsKey('schema')) return null;
    return _type(_map(json['schema']), '$at/content/application~1json/schema', '${base}Response').type;
  }

  SecurityIR _security(Map<String, Object?> node, String pointer, String operationId) {
    if (!node.containsKey('security')) {
      diagnostics.error(
        ContractCodes.undeclaredSecurity,
        'operation "$operationId" declares no security',
        location: _at(pointer),
        hint: 'add `security:` to the operation; the root-level security is ignored, as in stratastax-codegen',
      );
      return const UndeclaredSecurity();
    }
    final requirements = node['security'];
    if (requirements is! List || requirements.isEmpty) return const PublicSecurity();
    final scopes = <String>{};
    for (final requirement in requirements) {
      final map = _map(requirement);
      if (map.isEmpty) return const PublicSecurity();
      for (final list in map.values) {
        if (list is List) scopes.addAll(list.map((s) => s.toString()));
      }
    }
    return scopes.isEmpty ? const AuthenticatedSecurity() : ScopedSecurity(scopes.toList()..sort());
  }

  /// Optional + nullable properties of PATCH bodies become `Patch<T>`, like `PatchField` in the
  /// backend: absent leaves the value unchanged, null clears it.
  void _markPatchBodies(List<OperationIR> operations) {
    for (final operation in operations) {
      if (operation.method != HttpMethodIR.patch) continue;
      final type = operation.body?.type;
      if (type is! RefTypeIR) continue;
      final schema = _schemas[type.schema];
      if (schema is! ObjectSchemaIR) continue;
      _schemas[type.schema] = schema.withProperties([
        for (final p in schema.properties) (!p.required && p.nullable) ? p.asPatch() : p,
      ]);
    }
  }

  void _checkTypeNames(List<OperationIR> operations) {
    final names = {for (final s in _schemas.values) s.dartName: 'schema "${s.key}"'};
    void claim(String name, String owner, String location) {
      final existing = names[name];
      if (existing != null && existing != owner) {
        diagnostics.error(ContractCodes.nameCollision, '$owner and $existing both map to $name', location: location);
      }
      names[name] = owner;
    }

    for (final operation in operations) {
      claim('${Naming.pascal(operation.tag)}${config.apiSuffix}', 'tag "${operation.tag}"', operation.location);
      if (operation.params.isNotEmpty) {
        claim(
          '${Naming.pascal(operation.operationId)}Params',
          'parameters of "${operation.operationId}"',
          operation.location,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Document access

  ({String pointer, Map<String, Object?> node})? _resolve(String ref, String from) {
    if (!ref.startsWith('#/')) {
      diagnostics.error(
        ContractCodes.unresolvedRef,
        'external \$ref "$ref" is not supported',
        location: _at(from),
        hint: 'point stx.yaml at the bundled contract (build/openapi/openapi-v1.yaml)',
      );
      return null;
    }
    Object? node = _root;
    for (final segment in ref.substring(2).split('/')) {
      final key = segment.replaceAll('~1', '/').replaceAll('~0', '~');
      node = node is Map<String, Object?> ? node[key] : null;
    }
    if (node is! Map<String, Object?>) {
      diagnostics.error(ContractCodes.unresolvedRef, 'cannot resolve \$ref "$ref"', location: _at(from));
      return null;
    }
    return (pointer: ref.substring(1), node: node);
  }

  String? _componentKey(String pointer) {
    const prefix = '/components/schemas/';
    if (!pointer.startsWith(prefix)) return null;
    final rest = pointer.substring(prefix.length);
    return rest.contains('/') ? null : rest.replaceAll('~1', '/').replaceAll('~0', '~');
  }

  String _at(String pointer) => '$_source#$pointer';

  static String _escape(String segment) => segment.replaceAll('~', '~0').replaceAll('/', '~1');

  static Map<String, Object?> _map(Object? node) => node is Map<String, Object?> ? node : const {};

  static Object? _plain(Object? node) => switch (node) {
    YamlMap() => <String, Object?>{for (final e in node.entries) e.key.toString(): _plain(e.value)},
    YamlList() => [for (final e in node) _plain(e)],
    YamlScalar() => node.value,
    _ => node,
  };
}

final class _Typed {
  const _Typed(this.type, {this.nullable = false, this.constraints = ConstraintIR.none, this.description});

  final TypeIR type;
  final bool nullable;
  final ConstraintIR constraints;
  final String? description;
}
