import '../config.dart';
import '../contract/scope_registry.dart';
import '../naming.dart';
import '../output.dart';
import 'app_plan.dart';
import 'ui_ir.dart';

/// Renders `lib/gen/app/**` from an [AppPlan].
final class AppRenderer {
  AppRenderer(
    this.plan,
    this.scopes, {
    this.security,
    this.backends = const [BackendConfig(name: BackendConfig.defaultName)],
    this.contractBackends = const {},
  });

  final AppPlan plan;
  final ScopeRegistry scopes;

  /// One typed client per backend in `AppServices`.
  final List<BackendConfig> backends;

  /// Contract output directory (`platform_v1`) → backend name.
  final Map<String, String> contractBackends;

  /// The member of `AppServices` whose client sends [endpoint].
  String _backendOf(EndpointRef endpoint) => contractBackends[endpoint.contractDir] ?? backends.first.name;

  /// Null when the app has no login: `AppConfig.access` is then required.
  final SecurityConfig? security;

  String get _gen => 'package:${plan.package}/gen';

  List<GeneratedFile> render() {
    final files = <GeneratedFile>[];
    for (final form in plan.forms) {
      files
        ..add(GeneratedFile('app/forms/${Naming.snake(form.base)}.form.g.dart', _form(form)))
        ..add(GeneratedFile('app/pages/${Naming.snake(form.base)}.page.g.dart', _page(form)));
    }
    if (plan.mappers.isNotEmpty) files.add(GeneratedFile('app/mappers.g.dart', _mappers()));
    files
      ..add(GeneratedFile('app/config.g.dart', _config()))
      ..add(GeneratedFile('app/services.g.dart', _services()));
    if (plan.forms.any((f) => f.form.route != null)) {
      files
        ..add(GeneratedFile('app/routes.g.dart', _routes()))
        ..add(GeneratedFile('app/app.g.dart', _app()));
    }
    return files;
  }

  String _file(String source, Set<String> imports, String body) {
    // Contract types come in through the contract barrel.
    imports = {
      for (final i in imports)
        if (!i.contains('/gen/contract/') ||
            i.endsWith('scopes.g.dart') ||
            i.endsWith('backends.g.dart') ||
            RegExp(r'/gen/contract/([^/]+)/\1\.g\.dart$').hasMatch(i))
          i,
    };
    if (RegExp(r'\bScope\.').hasMatch(body)) imports.add('$_gen/contract/scopes.g.dart');
    final dart = imports.where((i) => i.startsWith('dart:')).toList()..sort();
    final packages = imports.where((i) => !i.startsWith('dart:')).toList()..sort();
    final b = StringBuffer()
      ..writeln(generatedHeader)
      ..writeln('// Source: $source')
      ..writeln();
    for (final i in dart) {
      b.writeln("import '$i';");
    }
    if (dart.isNotEmpty) b.writeln();
    for (final i in packages) {
      b.writeln("import '$i';");
    }
    b
      ..writeln()
      ..write(body);
    return b.toString();
  }

  String _keysImport(String expr) =>
      expr.startsWith('StxKeys.') ? 'package:stx_i18n/stx_i18n.dart' : '$_gen/i18n/keys.g.dart';

  // ---------------------------------------------------------------------------------------------
  // Form controller

  String _form(FormPlan f) {
    final imports = {
      'package:stx_core/stx_core.dart',
      'package:stx_ui/stx_ui.dart',
      ...f.imports,
      if (f.assignments.values.any((v) => v.contains('Mapper.'))) '$_gen/app/mappers.g.dart',
    };
    final b = StringBuffer()
      ..writeln(
        '/// The form state of [${f.base}]; submits to `${f.operation.method.name.toUpperCase()} ${f.operation.path}`.',
      )
      ..writeln('final class ${f.controller} extends StxFormController<${f.base}, ${f.bodyType}, ${f.responseType}> {');
    for (final field in f.fields) {
      b.writeln('  final ${field.field.name} = StxField<${field.stateType}>(${field.initial});');
    }
    b.writeln();
    for (final field in f.fields) {
      b.writeln('  static const ${field.field.name}Validation = ${_validation(field.rules)};');
    }
    for (final field in f.fields.where((x) => x.rules.pattern != null)) {
      b.writeln('  static final _${field.field.name}Pattern = RegExp(${Naming.stringLiteral(field.rules.pattern!)});');
    }
    b
      ..writeln()
      ..writeln('  @override')
      ..writeln('  List<StxField<Object?>> get fields => [${f.fields.map((x) => x.field.name).join(', ')}];')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Map<String, StxField<Object?>> get contractFields => {')
      ..writeAll([for (final x in f.fields) "    ${Naming.stringLiteral(x.property!.wireName)}: ${x.field.name},\n"])
      ..writeln('  };')
      ..writeln()
      ..writeln('  @override')
      ..writeln(
        '  Endpoint<NoParams, ${f.bodyType}, ${f.responseType}> get endpoint => ${f.form.submit.apiClass}.${f.form.submit.member};',
      )
      ..writeln()
      ..writeln('  /// Straight-line validation: one static validator per field, no metadata at runtime.')
      ..writeln('  @override')
      ..writeln('  bool validate() {')
      ..writeln('    var ok = true;');
    for (final field in f.fields.where((x) => _hasValidator(x))) {
      final name = field.field.name;
      b.writeln('    ok &= $name.check(_validate${Naming.pascal(name)}($name.value));');
    }
    b
      ..writeln('    return ok;')
      ..writeln('  }')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  ${f.base} toCommand() => ${f.base}(');
    for (final field in f.fields) {
      b.writeln('    ${field.field.name}: ${field.commandValue('${field.field.name}.value')},');
    }
    b
      ..writeln('  );')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  void resetFields() {');
    for (final field in f.fields) {
      b.writeln('    ${field.field.name}.reset(${field.initial});');
    }
    b
      ..writeln('  }')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  ${f.bodyType} toContract(${f.base} c) => ${f.bodyType}(');
    for (final e in f.assignments.entries) {
      b.writeln('    ${e.key}: ${e.value},');
    }
    b.writeln('  );');
    for (final field in f.fields.where((x) => _hasValidator(x))) {
      b
        ..writeln()
        ..write(_validator(field));
    }
    b.writeln('}');
    return _file(f.form.location, imports, b.toString());
  }

  bool _hasValidator(FieldPlan field) => !field.rules.isEmpty;

  String _validation(Rules r) {
    final args = [
      if (r.required) 'required: true',
      if (r.minLength != null) 'minLength: ${r.minLength}',
      if (r.maxLength != null) 'maxLength: ${r.maxLength}',
      if (r.minItems != null) 'minItems: ${r.minItems}',
      if (r.maxItems != null) 'maxItems: ${r.maxItems}',
      if (r.minimum != null) 'minimum: ${r.minimum}',
      if (r.maximum != null) 'maximum: ${r.maximum}',
      if (r.pattern != null) 'pattern: ${Naming.stringLiteral(r.pattern!)}',
      if (r.format != null) 'format: UiFormat.${r.format}',
    ];
    return args.isEmpty ? 'UiFieldValidation.none' : 'UiFieldValidation(${args.join(', ')})';
  }

  String _validator(FieldPlan field) {
    final r = field.rules;
    final name = field.field.name;
    final type = field.type.nonNull;
    final b = StringBuffer()..writeln('  static FieldError? _validate${Naming.pascal(name)}(${field.stateType} v) {');
    if (!field.isList) {
      final empty = type.kind == TypeKind.string ? 'v == null || v.isEmpty' : 'v == null';
      b.writeln('    if ($empty) return ${r.required ? 'const FieldError.required()' : 'null'};');
    }
    switch (type.kind) {
      case TypeKind.string:
        if (r.minLength != null || r.maxLength != null) b.writeln('    final length = v.runes.length;');
        if (r.minLength case final min?) b.writeln('    if (length < $min) return const FieldError.minLength($min);');
        if (r.maxLength case final max?) b.writeln('    if (length > $max) return const FieldError.maxLength($max);');
        if (r.format case final format?) {
          b.writeln('    if (!UiFormat.$format.matches(v)) return const FieldError.format(UiFormat.$format);');
        }
        if (r.pattern case final pattern?) {
          b.writeln(
            '    if (!_${name}Pattern.hasMatch(v)) return const FieldError.pattern(${Naming.stringLiteral(pattern)});',
          );
        }
      case TypeKind.int || TypeKind.double:
        if (r.minimum case final min?) b.writeln('    if (v < $min) return const FieldError.minimum($min);');
        if (r.maximum case final max?) b.writeln('    if (v > $max) return const FieldError.maximum($max);');
      case TypeKind.list:
        if (r.minItems case final min?) {
          b.writeln('    if (${min == 1 ? 'v.isEmpty' : 'v.length < $min'}) return const FieldError.minItems($min);');
        }
        if (r.maxItems case final max?) b.writeln('    if (v.length > $max) return const FieldError.maxItems($max);');
      default:
        break;
    }
    b
      ..writeln('    return null;')
      ..writeln('  }');
    return b.toString();
  }

  // ---------------------------------------------------------------------------------------------
  // Page

  String _page(FormPlan f) {
    final imports = <String>{
      'package:flutter/widgets.dart',
      'package:stx_core/stx_core.dart',
      'package:stx_ui/stx_ui.dart',
      f.form.library,
      '$_gen/app/forms/${Naming.snake(f.base)}.form.g.dart',
      '$_gen/app/services.g.dart',
      _keysImport(f.title),
    };
    final sources = <String>[];
    final helpers = StringBuffer();
    final children = <String>[];

    for (final field in f.fields) {
      final name = field.field.name;
      final common = ['field: _form.$name', 'label: ${field.label}'];
      imports.add(_keysImport(field.label));
      for (final msg in [?field.hint, ?field.help]) {
        imports.add(_keysImport(msg));
      }
      final validation = '${f.controller}.${name}Validation';
      final type = field.type.nonNull;
      imports.addAll(field.type.libraries);
      String widget;
      switch (field.kind) {
        case FieldKind.text || FieldKind.textArea || FieldKind.password:
          widget =
              'StxFormText(${[...common, if (field.hint != null) 'hint: ${field.hint}', if (field.help != null) 'help: ${field.help}', 'validation: $validation', if (field.kind == FieldKind.textArea) 'multiline: true', if (field.kind == FieldKind.password) 'obscure: true'].join(', ')})';
        case FieldKind.number:
          widget =
              'StxFormNumber<${type.name}>(${[...common, if (field.hint != null) 'hint: ${field.hint}', if (field.help != null) 'help: ${field.help}', 'validation: $validation'].join(', ')})';
        case FieldKind.checkbox:
          widget = 'StxFormCheckbox(${[...common, if (field.help != null) 'help: ${field.help}'].join(', ')})';
        case FieldKind.dateTime:
          widget =
              'StxFormDateTime(${[...common, if (field.help != null) 'help: ${field.help}', 'validation: $validation'].join(', ')})';
        case FieldKind.date:
          widget =
              'StxFormDate(${[...common, if (field.help != null) 'help: ${field.help}', 'validation: $validation'].join(', ')})';
        case FieldKind.select:
          final labelFn = '_${name}Label';
          imports.add('package:stx_i18n/stx_i18n.dart');
          for (final msg in field.enumLabels.values) {
            imports.add(_keysImport(msg));
          }
          helpers
            ..writeln()
            ..writeln('  static Msg $labelFn(${type.name} value) => switch (value) {');
          for (final e in field.enumLabels.entries) {
            helpers.writeln('    ${type.name}.${e.key} => ${e.value},');
          }
          helpers.writeln('  };');
          widget =
              'StxFormSelect<${type.name}>(${[...common, 'options: ${type.name}.values', 'optionLabel: $labelFn', if (field.help != null) 'help: ${field.help}', 'validation: $validation'].join(', ')})';
        case FieldKind.autocomplete:
          final source = field.source!;
          final sourceVar = '_${name}Source';
          final serviceSource = 'AppServices.of(context).${source.serviceName}';
          sources.add(
            type.kind == TypeKind.converter
                ? '  late final $sourceVar = $serviceSource.map(${type.name}.new);'
                : '  late final $sourceVar = $serviceSource;',
          );
          widget =
              'StxAutocomplete<${type.name}>(${[...common, 'source: $sourceVar', if (field.hint != null) 'hint: ${field.hint}', if (field.help != null) 'help: ${field.help}', 'validation: $validation'].join(', ')})';
        case FieldKind.custom:
          imports.add(field.widget!.library);
          widget = '${field.widget!.name}(${[...common, 'validation: $validation'].join(', ')})';
      }
      children.add(widget);
    }

    final back = f.form.onSuccess == 'back';
    if (back) imports.add('$_gen/app/routes.g.dart');
    final onSuccess = switch (f.form.onSuccess) {
      // Back to the previous page; opened directly (no previous page): empty the form for the next entry.
      'back' =>
        '(_) {\n        final router = StxRouter.of<AppRoute>(context);\n        router.canBack ? router.back() : _form.reset();\n      }',
      'reset' => '(_) => _form.reset()',
      _ => null,
    };
    final b = StringBuffer()
      ..writeln('/// The page of [${f.base}]. Shown only to users with the scopes of the operations it uses.')
      ..writeln('final class ${f.page} extends StatefulWidget {')
      ..writeln('  const ${f.page}({super.key});')
      ..writeln()
      ..writeln('  ${_requiresDoc(f)}')
      ..writeln('  static const requires = ${_requirement(f.requires)};')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  State<${f.page}> createState() => _${f.page}State();')
      ..writeln('}')
      ..writeln()
      ..writeln('final class _${f.page}State extends State<${f.page}> {')
      ..writeln('  final _form = ${f.controller}();');
    for (final s in sources) {
      b.writeln(s);
    }
    b
      ..writeln()
      ..writeln('  @override')
      ..writeln('  void dispose() {')
      ..writeln('    _form.dispose();')
      ..writeln('    super.dispose();')
      ..writeln('  }')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Widget build(BuildContext context) => StxGuard(')
      ..writeln('    requires: ${f.page}.requires,')
      ..writeln('    child: StxFormScaffold<${f.base}, ${f.bodyType}, ${f.responseType}>(')
      ..writeln('      title: ${f.title},')
      ..writeln('      form: _form,')
      ..writeln('      client: AppServices.of(context).${_backendOf(f.form.submit)}.http,');
    if (onSuccess != null) b.writeln('      onSuccess: $onSuccess,');
    b.writeln('      children: [');
    for (final child in children) {
      b.writeln('        $child,');
    }
    b
      ..writeln('      ],')
      ..writeln('    ),')
      ..writeln('  );')
      ..write(helpers)
      ..writeln('}');
    // Contract types appear in the scaffold's type arguments and enum selects.
    imports.add(
      'package:${plan.package}/gen/contract/${f.form.submit.contractDir}/${f.form.submit.contractDir}.g.dart',
    );
    return _file(f.form.location, imports, b.toString());
  }

  String _requiresDoc(FormPlan f) {
    final groups = [
      for (final g in f.requires)
        if (g.isNotEmpty) g.length == 1 ? g.single : '(${g.join(' | ')})',
    ];
    return groups.isEmpty ? '/// No scopes needed (authenticated only).' : '/// ${groups.join(' & ')}';
  }

  String _requirement(List<List<String>> groups) {
    final nonEmpty = [
      for (final g in groups)
        if (g.isNotEmpty) g,
    ];
    if (nonEmpty.isEmpty) return 'ScopeRequirement.none';
    return 'ScopeRequirement([${nonEmpty.map(scopes.literal).join(', ')}])';
  }

  // ---------------------------------------------------------------------------------------------

  String _mappers() {
    final imports = <String>{};
    final b = StringBuffer();
    for (final m in plan.mappers) {
      imports.add(m.entity.library);
      if (m.assignments.values.any((v) => v.contains('Patch.'))) imports.add('package:stx_core/stx_core.dart');
      imports.add('$_gen/contract/${_contractDirOf(m)}/${_contractDirOf(m)}.g.dart');
      b
        ..writeln('/// Maps [${m.entity.name}] to the contract schema `${m.schema.key}`.')
        ..writeln('abstract final class ${m.entity.name}Mapper {')
        ..writeln('  static ${m.schema.dartName} toContract(${m.entity.name} v) => ${m.schema.dartName}(');
      for (final e in m.assignments.entries) {
        b.writeln('    ${e.key}: ${e.value},');
      }
      b
        ..writeln('  );')
        ..writeln('}')
        ..writeln();
    }
    return _file('@DomainEntity classes used in forms', imports, b.toString());
  }

  String _contractDirOf(MapperPlan m) {
    for (final form in plan.forms) {
      if (form.contract.schemas.containsValue(m.schema)) return form.form.submit.contractDir;
    }
    return '';
  }

  String _config() {
    final sec = security;
    final imports = {
      'package:stx_http/stx_http.dart',
      'package:stx_i18n/stx_i18n.dart',
      'package:stx_ui/stx_ui.dart',
      if (sec != null) 'package:stx_security/stx_security.dart',
    };
    final b = StringBuffer()
      ..writeln('/// Runtime configuration of the app: per backend its base URL and extra interceptors.')
      ..writeln('final class AppConfig {')
      ..writeln('  const AppConfig({');
    for (final backend in backends) {
      b.writeln('    required this.${backend.name},');
    }
    b
      ..writeln(sec == null ? '    required this.access,' : '    this.access,')
      ..writeln(sec == null ? '' : '    this.oidc,\n    this.secureStore,\n    this.browser,')
      ..writeln('    this.transport,')
      ..writeln('    this.localeStore,')
      ..writeln('    this.log,')
      ..writeln('  });')
      ..writeln()
      ..writeln('  /// Base URLs from `--dart-define`:');
    for (final backend in backends) {
      b.writeln('  /// - `${backend.envName}` (default `${backend.baseUrl}`)');
    }
    b.writeln(
      sec == null
          ? '  factory AppConfig.fromEnvironment({required StxAccess access, void Function(String line)? log}) => AppConfig('
          : '  factory AppConfig.fromEnvironment({StxAccess? access, void Function(String line)? log}) => AppConfig(',
    );
    for (final backend in backends) {
      b.writeln(
        "    ${backend.name}: StxBackend(baseUrl: Uri.parse(const String.fromEnvironment('${backend.envName}', defaultValue: ${Naming.stringLiteral(backend.baseUrl)}))),",
      );
    }
    b
      ..writeln('    access: access,')
      ..writeln('    log: log,')
      ..writeln('  );');
    for (final backend in backends) {
      b
        ..writeln()
        ..writeln('  /// Backend `${backend.name}`${backend.oidc ? '; calls carry the session\'s bearer token' : ''}.')
        ..writeln('  final StxBackend ${backend.name};');
    }
    b.writeln();
    if (sec == null) {
      b
        ..writeln('  /// Who is signed in (the app has no `security:` in stx.yaml).')
        ..writeln('  final StxAccess access;');
    } else {
      b
        ..writeln(
          '  /// Overrides the OIDC session, e.g. `StaticAccess` in tests and previews; null signs in with OIDC.',
        )
        ..writeln('  final StxAccess? access;')
        ..writeln()
        ..writeln('  /// Null: [defaultOidc].')
        ..writeln('  final OidcConfig? oidc;')
        ..writeln()
        ..writeln('  /// Where the refresh token lives; null: sessionStorage on the web.')
        ..writeln('  final SecureStore? secureStore;')
        ..writeln('  final AuthBrowser? browser;');
    }
    b
      ..writeln()
      ..writeln('  /// Shared by every backend client and the token endpoint; null: the platform default.')
      ..writeln('  final StxTransport? transport;')
      ..writeln('  final LocaleStore? localeStore;')
      ..writeln('  final void Function(String line)? log;');
    if (sec != null) {
      final scopeList = sec.scopes.map(Naming.stringLiteral).join(', ');
      b
        ..writeln()
        ..writeln(
          '  /// From stx.yaml `security.oidc`. The issuer can be overridden with `--dart-define=STX_OIDC_ISSUER=…`;',
        )
        ..writeln('  /// the app returns to its own origin after login.')
        ..writeln('  static OidcConfig defaultOidc() {')
        ..writeln(
          '    final origin = Uri(scheme: Uri.base.scheme, host: Uri.base.host, port: Uri.base.port, path: \'/\');',
        )
        ..writeln('    return OidcConfig(')
        ..writeln(
          "      issuer: Uri.parse(const String.fromEnvironment('STX_OIDC_ISSUER', defaultValue: ${Naming.stringLiteral(sec.issuer)})),",
        )
        ..writeln('      clientId: ${Naming.stringLiteral(sec.clientId)},')
        ..writeln('      redirectUri: origin,')
        ..writeln('      scopes: const [$scopeList],');
      if (sec.roleClaims case final claims?) {
        b.writeln('      roleClaims: const [${claims.map(Naming.stringLiteral).join(', ')}],');
      }
      b
        ..writeln('    );')
        ..writeln('  }');
    }
    b.writeln('}');
    return _file('stx.yaml', imports, b.toString());
  }

  String _services() {
    final imports = {
      'package:flutter/widgets.dart',
      'package:stx_core/stx_core.dart',
      'package:stx_http/stx_http.dart',
      'package:stx_ui/stx_ui.dart',
      '$_gen/contract/backends.g.dart',
      'config.g.dart',
      for (final s in plan.sources) ...s.imports,
    };
    final b = StringBuffer()
      ..writeln('/// What the app is built from: one typed client per backend, the session and the data sources.')
      ..writeln('/// Created once by `runStxApp` from [AppConfig]; widgets get it with `AppServices.of(context)`.')
      ..writeln('/// Every dependency is a plain field: no service locator, a missing one does not compile.')
      ..writeln('final class AppServices {');
    final sec = security;
    final clientArgs = backends.map(
      (x) =>
          '${x.name}: ${x.typePrefix}Client(_client(config, config.${x.name}${sec != null && x.oidc ? ', tokens' : ''}))',
    );
    if (sec == null) {
      b
        ..writeln('  AppServices(this.config)')
        ..writeln(
          '    : ${[for (final x in backends) '${x.name} = ${x.typePrefix}Client(_client(config, config.${x.name}))'].join(',\n      ')};',
        )
        ..writeln()
        ..writeln('  final AppConfig config;')
        ..writeln()
        ..writeln('  StxAccess get access => config.access;')
        ..writeln()
        ..writeln('  /// Nothing to restore: the app has no login.')
        ..writeln('  Future<void> start() async {}');
    } else {
      imports
        ..add('package:stx_security/stx_security.dart')
        ..add('package:stx_i18n/stx_i18n.dart');
      if (scopes.claims.isNotEmpty) imports.add('$_gen/contract/scopes.g.dart');
      final scopesOf = scopes.claims.isEmpty ? '(_) => const {}' : 'Scope.fromClaims';
      b
        ..writeln('  factory AppServices(AppConfig config) {')
        ..writeln('    final session = Session(')
        ..writeln('      config: config.oidc ?? AppConfig.defaultOidc(),')
        ..writeln('      scopesOf: $scopesOf,')
        ..writeln('      transport: config.transport,')
        ..writeln('      store: config.secureStore,')
        ..writeln('      browser: config.browser,')
        ..writeln('      log: config.log,')
        ..writeln('    );')
        ..writeln('    // An overriding access (tests, previews) has no tokens to send.')
        ..writeln('    final tokens = config.access == null ? session : null;')
        ..writeln('    return AppServices._(')
        ..writeln('      config,')
        ..writeln('      session,')
        ..writeln('      config.access ?? SessionAccess(session, options: loginOptions),')
        ..writeln('      ${clientArgs.join(',\n      ')},')
        ..writeln('    );')
        ..writeln('  }')
        ..writeln()
        ..writeln(
          '  AppServices._(this.config, this.session, this.access, {${backends.map((x) => 'required this.${x.name}').join(', ')}});',
        )
        ..writeln()
        ..writeln('  final AppConfig config;')
        ..writeln()
        ..writeln('  /// The OIDC session; its tokens authenticate the clients of `auth: oidc` backends.')
        ..writeln('  final Session session;')
        ..writeln('  final StxAccess access;')
        ..writeln()
        ..writeln('  /// From stx.yaml `security.social`: the provider page first, then one button per provider.')
        ..writeln('  static final loginOptions = [')
        ..writeln('    const StxLoginOption(label: StxKeys.accessSignIn),');
      for (final e in sec.social.entries) {
        b.writeln(
          '    StxLoginOption(label: StxKeys.sessionSignInWith(${Naming.stringLiteral(e.value)}), idpHint: ${Naming.stringLiteral(e.key)}),',
        );
      }
      b
        ..writeln('  ];')
        ..writeln()
        ..writeln('  /// Completes a login callback or restores the session (unless [AppConfig.access] overrides it).')
        ..writeln('  Future<void> start() async {')
        ..writeln('    if (config.access == null) await session.start();')
        ..writeln('  }');
    }
    for (final backend in backends) {
      final contracts = [
        for (final e in contractBackends.entries)
          if (e.value == backend.name) e.key,
      ];
      b
        ..writeln()
        ..writeln(
          '  /// Backend `${backend.name}`${contracts.isEmpty ? '' : ' (${contracts.map((c) => '`$c`').join(', ')})'}.',
        )
        ..writeln('  final ${backend.typePrefix}Client ${backend.name};');
    }
    for (final s in plan.sources) {
      final params = s.paramsClass == 'NoParams'
          ? '(_) => ()'
          : s.queryParam == null
          ? '(_) => const ${s.paramsClass}()'
          : '(query) => ${s.paramsClass}(${s.queryParam}: query)';
      b
        ..writeln()
        ..writeln('  /// `@UiDataSource` ${s.source.name}: ${s.operation.operationId}.')
        ..writeln('  late final StxDataSource<${s.valueType}> ${s.serviceName} =')
        ..writeln('      StxEndpointSource<${s.valueType}, ${s.paramsClass}, ${s.responseType}, ${s.itemType}>(')
        ..writeln('        client: ${_backendOf(s.source.endpoint)}.http,')
        ..writeln('        endpoint: ${s.source.endpoint.apiClass}.${s.source.endpoint.member},')
        ..writeln('        params: $params,')
        ..writeln('        items: (response) => ${s.itemsExpr},')
        ..writeln('        value: (item) => item.${s.valueProperty},')
        ..writeln('        label: (item) => item.${s.labelProperty},')
        ..writeln('      );');
    }
    b
      ..writeln()
      ..writeln('  static StxClient _client(AppConfig config, StxBackend backend, [TokenSource? tokens]) => StxClient(')
      ..writeln('    baseUrl: backend.baseUrl,')
      ..writeln('    transport: config.transport,')
      ..writeln('    interceptors: [')
      ..writeln('      if (config.log case final log?) LoggingInterceptor(log: log),')
      ..writeln('      ...backend.interceptors,')
      ..writeln('      if (tokens != null) BearerAuthInterceptor(tokens),')
      ..writeln('      IdempotencyKeyInterceptor(),')
      ..writeln('      RetryInterceptor(),')
      ..writeln('    ],')
      ..writeln('  );')
      ..writeln()
      ..writeln('  static AppServices of(BuildContext context) => StxServices.of<AppServices>(context);')
      ..writeln('}');
    for (final backend in backends) {
      final e = '${backend.typePrefix}Endpoint';
      b
        ..writeln()
        ..writeln('/// The client of backend `${backend.name}`: accepts only [$e]s, so an operation cannot be sent')
        ..writeln('/// to a backend that does not serve it. [http] is the untyped client underneath.')
        ..writeln('extension type const ${backend.typePrefix}Client(StxClient http) {')
        ..writeln(
          '  Future<Result<R, Problem>> send<P, B, R>($e<P, B, R> endpoint, {required P params, required B body}) =>',
        )
        ..writeln('      http.send(endpoint, params: params, body: body);')
        ..writeln()
        ..writeln('  /// Like [send], but keeps status and headers (e.g. `ETag`).')
        ..writeln(
          '  Future<Result<StxReply<R>, Problem>> exchange<P, B, R>($e<P, B, R> endpoint, {required P params, required B body}) =>',
        )
        ..writeln('      http.exchange(endpoint, params: params, body: body);')
        ..writeln()
        ..writeln(
          '  Future<Result<R, Problem>> fetch<P, R>($e<P, NoBody, R> endpoint, P params) => http.fetch(endpoint, params);',
        )
        ..writeln()
        ..writeln(
          '  Future<Result<R, Problem>> submit<B, R>($e<NoParams, B, R> endpoint, B body) => http.submit(endpoint, body);',
        )
        ..writeln('}');
    }
    return _file('stx.yaml and @UiDataSource classes', imports, b.toString());
  }

  // ---------------------------------------------------------------------------------------------

  List<FormPlan> get _routed => [
    for (final f in plan.forms)
      if (f.form.route != null) f,
  ]..sort((a, b) => a.form.route!.path.compareTo(b.form.route!.path));

  FormPlan get _home =>
      _routed.where((f) => f.form.route!.path == '/').firstOrNull ??
      _routed.where((f) => f.form.route!.nav == 'primary').firstOrNull ??
      _routed.first;

  List<String> _segments(String path) => path.split('/').where((s) => s.isNotEmpty).toList();

  String _routes() {
    final routed = _routed;
    final imports = <String>{
      'package:flutter/widgets.dart',
      'package:stx_core/stx_core.dart',
      'package:stx_ui/stx_ui.dart',
      for (final f in routed) '$_gen/app/pages/${Naming.snake(f.base)}.page.g.dart',
      for (final f in routed)
        if (f.form.route!.nav != 'none') _keysImport(f.title),
    };
    final b = StringBuffer()
      ..writeln('/// Every page of the app, from `@UiRoute`.')
      ..writeln('sealed class AppRoute {')
      ..writeln('  const AppRoute();')
      ..writeln('}')
      ..writeln();
    for (final f in routed) {
      b
        ..writeln('/// `${f.form.route!.path}`')
        ..writeln('final class ${f.route} extends AppRoute {')
        ..writeln('  const ${f.route}();')
        ..writeln('}')
        ..writeln();
    }
    String literal(List<String> segments) => '[${segments.map(Naming.stringLiteral).join(', ')}]';
    b
      ..writeln('/// Pattern matching on path segments: no regex, no route table.')
      ..writeln('AppRoute? parseRoute(List<String> segments) => switch (segments) {');
    for (final f in routed) {
      b.writeln('  ${literal(_segments(f.form.route!.path))} => const ${f.route}(),');
    }
    b
      ..writeln('  _ => null,')
      ..writeln('};')
      ..writeln()
      ..writeln('List<String> routeSegments(AppRoute route) => switch (route) {');
    for (final f in routed) {
      b.writeln('  ${f.route}() => const ${literal(_segments(f.form.route!.path))},');
    }
    b
      ..writeln('};')
      ..writeln()
      ..writeln('Widget buildRoute(AppRoute route) => switch (route) {');
    for (final f in routed) {
      b.writeln('  ${f.route}() => const ${f.page}(),');
    }
    b
      ..writeln('};')
      ..writeln()
      ..writeln('/// Exhaustive: a new route without requirements does not compile.')
      ..writeln('ScopeRequirement requiredScopes(AppRoute route) => switch (route) {');
    for (final f in routed) {
      b.writeln('  ${f.route}() => ${f.page}.requires,');
    }
    b
      ..writeln('};')
      ..writeln()
      ..writeln('/// Navigation entries; [StxAppShell] hides those the user has no scopes for.')
      ..writeln('const navItems = <NavItem<AppRoute>>[');
    for (final f in routed.where((f) => f.form.route!.nav != 'none')) {
      b.writeln(
        '  NavItem(route: ${f.route}(), title: ${f.title}, requires: ${f.page}.requires'
        '${f.form.route!.nav == 'secondary' ? ', secondary: true' : ''}),',
      );
    }
    b
      ..writeln('];')
      ..writeln()
      ..writeln('const appRoutes = StxRoutes<AppRoute>(')
      ..writeln('  parse: parseRoute,')
      ..writeln('  segments: routeSegments,')
      ..writeln('  build: buildRoute,')
      ..writeln('  requires: requiredScopes,')
      ..writeln('  home: ${_home.route}(),')
      ..writeln('  nav: navItems,')
      ..writeln(');');
    return _file('@UiRoute classes', imports, b.toString());
  }

  String _app() {
    final imports = {
      'package:flutter/widgets.dart',
      'package:stx_ui/stx_ui.dart',
      '$_gen/i18n/locales.g.dart',
      '$_gen/style/tokens.g.dart',
      'config.g.dart',
      'services.g.dart',
      'routes.g.dart',
      if (plan.appTitle != null) '$_gen/i18n/keys.g.dart',
    };
    return _file('stx.yaml', imports, '''
export 'config.g.dart' show AppConfig;
export 'services.g.dart' show AppServices;

/// Starts the app: completes a login callback or restores the session, then runs.
/// `void main() => runStxApp(AppConfig.fromEnvironment());`
Future<void> runStxApp(AppConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = AppServices(config);
  await services.start();
  runApp(AppRoot(services: services));
}

/// The root widget: services, tokens, translations, access and router. No MaterialApp.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.services, this.initialLocation, this.initialLocale});

  final AppServices services;

  /// Start location, e.g. in tests; defaults to the platform's initial route.
  final String? initialLocation;
  final Locale? initialLocale;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  late final _router = StxRouter.config<AppRoute>(
    appRoutes,
    initialLocation: widget.initialLocation,
    shell: (context, navigator, pages) =>
        StxAppShell<AppRoute>(navigator: navigator, items: navItems, ${plan.appTitle == null ? '' : 'title: ${plan.appTitle}, '}child: pages),
  );

  @override
  Widget build(BuildContext context) => StxServices<AppServices>(
    value: widget.services,
    child: StxApp(
      light: stxTokensLight,
      dark: stxTokensDark,
      locales: supportedLocales,
      messages: loadMessages,
      localeStore: widget.services.config.localeStore,
      initialLocale: widget.initialLocale,
      router: _router,
      access: widget.services.access,
    ),
  );
}
''');
  }
}
