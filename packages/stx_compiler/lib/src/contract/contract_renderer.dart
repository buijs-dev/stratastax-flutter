import '../config.dart';
import '../naming.dart';
import '../output.dart';
import 'dart_types.dart';
import 'ir.dart';
import 'scope_registry.dart';

/// Renders the code of one contract into `contract/<name>/`:
///
/// * `models/<schema>.g.dart`: a final class (or enum) per schema with straight-line codecs
/// * `validation/<schema>.g.dart`: the contract's validation rules as `UiFieldValidation` constants
/// * `api/<tag>_api.g.dart`: a const `Endpoint` per operation, plus a params class per operation
/// * `models.g.dart` and `<name>.g.dart`: barrels
final class ContractRenderer {
  ContractRenderer(this.contract, this.scopes, {this.backend = const BackendConfig(name: BackendConfig.defaultName)});

  /// The backend that serves [contract]; its endpoint type is used for every operation.
  final BackendConfig backend;

  final ContractIR contract;
  final ScopeRegistry scopes;

  String get dir => 'contract/${Naming.snake(contract.name)}';

  List<GeneratedFile> render() {
    final files = <GeneratedFile>[];
    final modelFiles = <String>[];
    final validationFiles = <String>[];
    final apiFiles = <String>[];

    for (final schema in contract.schemas.values) {
      final file = 'models/${Naming.snake(schema.key)}.g.dart';
      modelFiles.add(file);
      files.add(GeneratedFile('$dir/$file', _model(schema)));
      if (schema is ObjectSchemaIR && schema.properties.isNotEmpty) {
        final validation = 'validation/${Naming.snake(schema.key)}.g.dart';
        validationFiles.add(validation);
        files.add(GeneratedFile('$dir/$validation', _validation(schema)));
      }
    }

    for (final entry in contract.operationsByTag.entries) {
      final className = '${Naming.pascal(entry.key)}${contract.apiSuffix}';
      final file = 'api/${Naming.snake(className)}.g.dart';
      apiFiles.add(file);
      files.add(GeneratedFile('$dir/$file', _api(className, entry.key, entry.value)));
    }

    files.add(
      GeneratedFile('$dir/models.g.dart', _barrel('Models of ${contract.name}.', [for (final f in modelFiles) f])),
    );
    files.add(
      GeneratedFile(
        '$dir/${Naming.snake(contract.name)}.g.dart',
        _barrel('Generated code of contract ${contract.name} (${contract.source}).', [
          'models.g.dart',
          ...apiFiles,
          ...validationFiles,
        ]),
      ),
    );
    return files;
  }

  String _header(String location) => '$generatedHeader\n// Source: $location\n';

  String _barrel(String doc, List<String> exports) {
    final b = StringBuffer()
      ..writeln(generatedHeader)
      ..writeln('/// $doc')
      ..writeln('library;')
      ..writeln();
    for (final e in exports) {
      b.writeln("export '$e';");
    }
    return b.toString();
  }

  String _imports(DartTypes types, {String models = '../models.g.dart', bool api = false, bool scopes = false}) {
    final relative = [
      if (api) '../../backends.g.dart',
      if (scopes) '../../scopes.g.dart',
      if (types.referenced.isNotEmpty) models,
    ];
    final b = StringBuffer("import 'package:stx_core/stx_core.dart';\n");
    if (relative.isNotEmpty) b.write('\n${relative.map((r) => "import '$r';\n").join()}');
    return b.toString();
  }

  // ---------------------------------------------------------------------------------------------
  // Models

  String _model(SchemaIR schema) {
    final types = DartTypes(contract);
    final body = switch (schema) {
      ObjectSchemaIR() => _object(schema, types),
      EnumSchemaIR() => _enum(schema),
    };
    // Self-references do not need the barrel.
    types.referenced.remove(schema.key);
    final imports = schema is EnumSchemaIR ? "import 'package:stx_core/stx_core.dart';\n" : _imports(types);
    return '${_header(schema.location)}\n$imports\n$body';
  }

  String _enum(EnumSchemaIR schema) {
    final b = StringBuffer();
    Naming.docLines(schema.description).forEach(b.writeln);
    b.writeln('enum ${schema.dartName} {');
    for (final v in schema.values) {
      b.writeln('  ${v.dartName}(${Naming.stringLiteral(v.wire)}),');
    }
    b
      ..writeln(';')
      ..writeln()
      ..writeln('  const ${schema.dartName}(this.wire);')
      ..writeln()
      ..writeln('  /// The value on the wire.')
      ..writeln('  final String wire;')
      ..writeln()
      ..writeln('  static ${schema.dartName} decode(Object? json) => switch (json) {');
    for (final v in schema.values) {
      b.writeln('    ${Naming.stringLiteral(v.wire)} => ${v.dartName},');
    }
    b
      ..writeln("    _ => throw JsonDecodeException('${schema.dartName}', json),")
      ..writeln('  };')
      ..writeln('}');
    return b.toString();
  }

  String _object(ObjectSchemaIR schema, DartTypes types) {
    final name = schema.dartName;
    final props = schema.properties;
    final b = StringBuffer();
    Naming.docLines(schema.description).forEach(b.writeln);
    b.writeln('final class $name {');

    // Constructor
    if (props.isEmpty) {
      b.writeln('  const $name();');
    } else {
      b.writeln('  const $name({');
      for (final p in props) {
        if (p.patch) {
          b.writeln('    this.${p.dartName} = const Patch.unset(),');
        } else if (p.required && !p.nullable) {
          b.writeln('    required this.${p.dartName},');
        } else if (p.required) {
          // Required but nullable: the caller decides, null is sent explicitly.
          b.writeln('    required this.${p.dartName},');
        } else {
          b.writeln('    this.${p.dartName},');
        }
      }
      b.writeln('  });');
    }

    // Fields
    for (final p in props) {
      b.writeln();
      Naming.docLines(p.description).forEach((l) => b.writeln('  $l'));
      b.writeln('  final ${types.propertyType(p)} ${p.dartName};');
    }

    // encode
    b
      ..writeln()
      ..writeln('  static Map<String, Object?> encode($name v) => {');
    for (final p in props) {
      final key = Naming.stringLiteral(p.wireName);
      final field = 'v.${p.dartName}';
      if (p.patch) {
        final value = types.isIdentity(p.type)
            ? 'value'
            : 'switch (value) { final x? => ${types.encode(p.type, 'x')}, null => null }';
        b.writeln('    if ($field case PatchValue(:final value)) $key: $value,');
      } else if (p.required && !p.nullable) {
        b.writeln('    $key: ${types.encode(p.type, field)},');
      } else if (p.required) {
        final value = types.isIdentity(p.type)
            ? field
            : 'switch ($field) { final x? => ${types.encode(p.type, 'x')}, null => null }';
        b.writeln('    $key: $value,');
      } else if (types.isIdentity(p.type)) {
        b.writeln('    $key: ?$field,');
      } else {
        b.writeln('    if ($field case final x?) $key: ${types.encode(p.type, 'x')},');
      }
    }
    b.writeln('  };');

    // decode
    b.writeln();
    if (props.isEmpty) {
      b
        ..writeln('  static $name decode(Object? json) {')
        ..writeln('    Json.object(json);')
        ..writeln('    return const $name();')
        ..writeln('  }');
    } else {
      b
        ..writeln('  static $name decode(Object? json) {')
        ..writeln('    final j = Json.object(json);')
        ..writeln('    return $name(');
      for (final p in props) {
        b.writeln('      ${p.dartName}: ${types.decodeProperty(p)},');
      }
      b
        ..writeln('    );')
        ..writeln('  }');
    }

    // ==, hashCode, toString
    b
      ..writeln()
      ..writeln('  @override')
      ..write('  bool operator ==(Object other) => identical(this, other) || other is $name');
    for (final p in props) {
      final f = p.dartName;
      b.write(types.isCollection(p.type) && !p.patch ? ' && DeepEquality.equals($f, other.$f)' : ' && $f == other.$f');
    }
    b
      ..writeln(';')
      ..writeln()
      ..writeln('  @override');
    if (props.isEmpty) {
      b.writeln('  int get hashCode => ($name).hashCode;');
    } else {
      final parts = [
        for (final p in props) types.isCollection(p.type) && !p.patch ? 'DeepEquality.hash(${p.dartName})' : p.dartName,
      ];
      b.writeln(
        parts.length == 1
            ? '  int get hashCode => Object.hash($name, ${parts.single});'
            : '  int get hashCode => Object.hashAll([${parts.join(', ')}]);',
      );
    }
    final fields = [for (final p in props) '${p.wireName}: ${_interpolate(p.dartName)}'];
    b
      ..writeln()
      ..writeln('  @override')
      ..writeln("  String toString() => '$name(${fields.join(', ')})';")
      ..writeln('}');
    return b.toString();
  }

  static String _interpolate(String identifier) => identifier.contains(r'$') ? '\${$identifier}' : '\$$identifier';

  // ---------------------------------------------------------------------------------------------
  // Validation

  static const _formats = {
    'uuid': 'uuid',
    'date': 'date',
    'date-time': 'dateTime',
    'email': 'email',
    'uri': 'uri',
    'password': 'password',
  };

  String _validation(ObjectSchemaIR schema) {
    final b = StringBuffer()
      ..write(_header(schema.location))
      ..writeln()
      ..writeln("import 'package:stx_core/stx_core.dart';")
      ..writeln()
      ..writeln(
        '/// Validation rules of `${schema.dartName}`, from the contract. UI annotations can only tighten them.',
      )
      ..writeln('abstract final class ${schema.dartName}Validation {');
    var first = true;
    for (final p in schema.properties) {
      if (!first) b.writeln();
      first = false;
      final c = p.constraints;
      final args = <String>[
        if (p.required && !p.nullable) 'required: true',
        if (c.minLength != null) 'minLength: ${c.minLength}',
        if (c.maxLength != null) 'maxLength: ${c.maxLength}',
        if (c.minItems != null) 'minItems: ${c.minItems}',
        if (c.maxItems != null) 'maxItems: ${c.maxItems}',
        if (c.minimum != null) 'minimum: ${c.minimum}',
        if (c.maximum != null) 'maximum: ${c.maximum}',
        if (c.exclusiveMinimum) 'exclusiveMinimum: true',
        if (c.exclusiveMaximum) 'exclusiveMaximum: true',
        if (c.pattern != null) 'pattern: ${Naming.stringLiteral(c.pattern!)}',
        if (_formats[c.format] case final f?) 'format: UiFormat.$f',
      ];
      b.writeln(
        args.isEmpty
            ? '  static const ${p.dartName} = UiFieldValidation.none;'
            : '  static const ${p.dartName} = UiFieldValidation(${args.join(', ')});',
      );
    }
    b.writeln('}');
    return b.toString();
  }

  // ---------------------------------------------------------------------------------------------
  // API

  String _api(String className, String tag, List<OperationIR> operations) {
    final types = DartTypes(contract);
    final params = StringBuffer();
    final endpoints = StringBuffer();
    final helpers = StringBuffer();

    for (final o in operations) {
      final paramsClass = o.params.isEmpty ? 'NoParams' : '${Naming.pascal(o.operationId)}Params';
      if (o.params.isNotEmpty) params.write(_paramsClass(paramsClass, className, o, types));

      final bodyType = o.body == null ? 'NoBody' : types.type(o.body!.type);
      final responseType = o.response == null ? 'NoContent' : types.type(o.response!);
      final base = o.dartName.replaceAll(r'$', '');

      final args = <String>[
        "operationId: '${o.operationId}'",
        'method: HttpMethod.${o.method.name}',
        'path: PathTemplate([${o.segments.map(Naming.stringLiteral).join(', ')}])',
        'security: ${_security(o.security)}',
        if (o.idempotent) 'idempotent: true',
        if (o.body != null && !o.body!.isJson) 'requestContentType: ${Naming.stringLiteral(o.body!.contentType)}',
      ];

      final pathParams = o.params.where((p) => p.location == ParamLocation.path).toList();
      if (pathParams.isNotEmpty) {
        args.add('encodePath: _${base}Path');
        final segments = [for (final s in o.segments) _segment(s, o, types)];
        helpers
          ..writeln()
          ..writeln('  static List<String> _${base}Path($paramsClass p) => [${segments.join(', ')}];');
      }
      final query = o.params.where((p) => p.location == ParamLocation.query).toList();
      if (query.isNotEmpty) {
        args.add('encodeQuery: _${base}Query');
        helpers
          ..writeln()
          ..writeln('  static Map<String, List<String>> _${base}Query($paramsClass p) => {');
        for (final q in query) {
          helpers.writeln('    ${_queryEntry(q, types)},');
        }
        helpers.writeln('  };');
      }
      final headers = o.params.where((p) => p.location == ParamLocation.header).toList();
      if (headers.isNotEmpty) {
        args.add('encodeHeaders: _${base}Headers');
        helpers
          ..writeln()
          ..writeln('  static Map<String, String> _${base}Headers($paramsClass p) => {');
        for (final h in headers) {
          final key = Naming.stringLiteral(h.wireName);
          final value = types.paramString(h.type, 'v');
          helpers.writeln(
            h.required
                ? '    $key: ${types.paramString(h.type, 'p.${h.dartName}')},'
                : value == 'v'
                ? '    $key: ?p.${h.dartName},'
                : '    if (p.${h.dartName} case final v?) $key: $value,',
          );
        }
        helpers.writeln('  };');
      }

      if (o.body case final body?) {
        final t = body.type;
        if (t is RefTypeIR && types.schema(t.schema) is ObjectSchemaIR) {
          args.add('encodeBody: ${types.type(t)}.encode');
        } else {
          args.add('encodeBody: _${base}Body');
          helpers
            ..writeln()
            ..writeln('  static Object? _${base}Body($bodyType body) => ${types.encode(t, 'body')};');
        }
      }

      final response = o.response;
      if (response == null) {
        args.add('decode: NoContent.decode');
      } else if (response is ListTypeIR || response is MapTypeIR) {
        args.add('decode: _${base}Response');
        helpers
          ..writeln()
          ..writeln('  static $responseType _${base}Response(Object? json) => ${types.decodeValue(response, 'json')};');
      } else {
        args.add('decode: ${types.decoder(response)}');
      }

      endpoints.writeln();
      final doc = [
        ...Naming.docLines(o.summary),
        if (o.summary != null && o.description != null) '///',
        ...Naming.docLines(o.description),
        if (o.summary != null || o.description != null) '///',
        '/// `${o.method.name.toUpperCase()} ${o.path}`${_securityDoc(o.security)}',
      ];
      for (final line in doc) {
        endpoints.writeln('  $line');
      }
      endpoints
        ..writeln(
          '  static const ${o.dartName} = ${backend.typePrefix}Endpoint<$paramsClass, $bodyType, $responseType>(',
        )
        ..writeln('    ${args.join(',\n    ')},')
        ..writeln('  );');
    }

    final b = StringBuffer()
      ..write(_header('${contract.source} tag "$tag"'))
      ..writeln()
      ..write(_imports(types, api: true, scopes: operations.any((o) => o.security is ScopedSecurity)))
      ..write(params)
      ..writeln()
      ..writeln('/// Operations of tag `$tag`.')
      ..writeln('abstract final class $className {')
      ..write(endpoints)
      ..write(helpers)
      ..writeln('}');
    return b.toString();
  }

  String _paramsClass(String name, String apiClass, OperationIR o, DartTypes types) {
    final b = StringBuffer()
      ..writeln()
      ..writeln('/// Parameters of [$apiClass.${o.dartName}].')
      ..writeln('final class $name {')
      ..writeln('  const $name({');
    for (final p in o.params) {
      b.writeln(p.required ? '    required this.${p.dartName},' : '    this.${p.dartName},');
    }
    b.writeln('  });');
    for (final p in o.params) {
      b.writeln();
      Naming.docLines(p.description).forEach((l) => b.writeln('  $l'));
      b.writeln('  final ${p.required ? types.type(p.type) : types.nullableType(p.type)} ${p.dartName};');
    }
    b.writeln('}');
    return b.toString();
  }

  String _segment(String segment, OperationIR o, DartTypes types) {
    final whole = RegExp(r'^\{([^}]+)\}$').firstMatch(segment);
    if (whole != null) {
      final param = _pathParam(o, whole[1]!);
      return types.paramString(param.type, 'p.${param.dartName}');
    }
    if (!segment.contains('{')) return Naming.stringLiteral(segment);
    final interpolated = segment.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) {
      final param = _pathParam(o, m[1]!);
      return '\${${types.paramString(param.type, 'p.${param.dartName}')}}';
    });
    return "'$interpolated'";
  }

  ParamIR _pathParam(OperationIR o, String name) =>
      o.params.firstWhere((p) => p.location == ParamLocation.path && p.wireName == name);

  String _queryEntry(ParamIR q, DartTypes types) {
    final key = Naming.stringLiteral(q.wireName);
    String values(String expr) => switch (q.type) {
      ListTypeIR(:final item) => '[for (final e in $expr) ${types.paramString(item, 'e')}]',
      _ => '[${types.paramString(q.type, expr)}]',
    };
    return q.required
        ? '$key: ${values('p.${q.dartName}')}'
        : 'if (p.${q.dartName} case final v?) $key: ${values('v')}';
  }

  String _security(SecurityIR security) => switch (security) {
    PublicSecurity() => 'Secured.public()',
    AuthenticatedSecurity() || UndeclaredSecurity() => 'Secured.authenticated()',
    ScopedSecurity(:final scopes) => 'Secured.scopes(${this.scopes.literal(scopes)})',
  };

  String _securityDoc(SecurityIR security) => switch (security) {
    PublicSecurity() => ' · public',
    AuthenticatedSecurity() || UndeclaredSecurity() => ' · authenticated',
    ScopedSecurity(:final scopes) => ' · any of ${scopes.map((s) => '`$s`').join(', ')}',
  };
}

/// Renders `contract/backends.g.dart`: one [Endpoint] subclass per backend, so a backend's client
/// only accepts the operations of its contracts.
String renderBackends(List<BackendConfig> backends, Map<String, List<String>> contracts) {
  final b = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln('// Source: stx.yaml `backends` and `contracts`.')
    ..writeln()
    ..writeln("import 'package:stx_core/stx_core.dart';");
  for (final backend in backends) {
    final names = contracts[backend.name] ?? const [];
    b
      ..writeln()
      ..writeln(
        '/// An operation of backend `${backend.name}` (contracts: ${names.isEmpty ? 'none' : names.join(', ')}).',
      )
      ..writeln('final class ${backend.typePrefix}Endpoint<P, B, R> extends Endpoint<P, B, R> {')
      ..writeln('  const ${backend.typePrefix}Endpoint({')
      ..writeln('    required super.operationId,')
      ..writeln('    required super.method,')
      ..writeln('    required super.path,')
      ..writeln('    required super.security,')
      ..writeln('    required super.decode,')
      ..writeln('    super.idempotent,')
      ..writeln('    super.requestContentType,')
      ..writeln('    super.encodePath,')
      ..writeln('    super.encodeQuery,')
      ..writeln('    super.encodeHeaders,')
      ..writeln('    super.encodeBody,')
      ..writeln('  });')
      ..writeln('}');
  }
  return b.toString();
}

/// Renders `contract/scopes.g.dart`: one `Scope` enum over all contracts.
String renderScopes(ScopeRegistry registry) {
  final b = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln('// Source: the security scopes of every operation in stx.yaml `contracts`.')
    ..writeln()
    ..writeln("import 'package:stx_core/stx_core.dart';")
    ..writeln()
    ..writeln('/// Every scope the contracts declare.')
    ..writeln('enum Scope implements StxScope {');
  for (final claim in registry.claims) {
    b
      ..writeln('  /// Accepted by ${registry.usage[claim]!.join(', ')}.')
      ..writeln('  ${registry.dartName(claim)}(${Naming.stringLiteral(claim)}),');
  }
  b
    ..writeln(';')
    ..writeln()
    ..writeln('  const Scope(this.claim);')
    ..writeln()
    ..writeln('  @override')
    ..writeln('  final String claim;')
    ..writeln()
    ..writeln('  static Scope? fromClaim(String claim) => switch (claim) {');
  for (final claim in registry.claims) {
    b.writeln('    ${Naming.stringLiteral(claim)} => ${registry.dartName(claim)},');
  }
  b
    ..writeln('    _ => null,')
    ..writeln('  };')
    ..writeln()
    ..writeln('  /// The scopes of an access token; unknown claims are ignored.')
    ..writeln('  static Set<Scope> fromClaims(Iterable<String> claims) => {for (final c in claims) ?fromClaim(c)};')
    ..writeln('}');
  return b.toString();
}
