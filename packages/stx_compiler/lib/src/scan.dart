import 'config.dart';
import 'contract/ir.dart';
import 'naming.dart';
import 'pipeline.dart';
import 'ui/app_plan.dart';

/// What `stx scan` prints (like `stratastaxScan`): the merged app IR in full (forms with their
/// fields, the contract property each maps to, merged rules, keys and required scopes), plus a
/// summary of the contract, style and i18n IR. [contracts] adds the full contract IR.
Map<String, Object?> scanReport(BuildResult result, StxConfig config, {bool contracts = false}) {
  final app = result.app;
  return {
    'backends': {
      for (final b in config.backends)
        b.name: {
          'baseUrl': b.baseUrl,
          'env': b.envName,
          'auth': b.auth.name,
          'contracts': [
            for (final c in config.contracts)
              if (c.backend == b.name) c.name,
          ],
        },
    },
    if (config.security case final security?)
      'security': {
        'issuer': security.issuer,
        'clientId': security.clientId,
        if (security.social.isNotEmpty) 'social': security.social.keys.toList(),
      },
    'contracts': {
      for (final c in result.contracts)
        c.name: {
          'source': c.source,
          'backend': config.backendOf(c.name).name,
          'schemas': c.schemas.length,
          'operations': c.operations.length,
          'scopes': c.scopes.toSet().length,
        },
    },
    if (app != null)
      'app': {
        'package': app.package,
        'forms': [for (final f in app.forms) _form(f, config)],
        if (app.sources.isNotEmpty)
          'dataSources': [
            for (final s in app.sources)
              {
                'name': s.source.name,
                'location': s.source.location,
                'operation': _operation(s.operation, s.source.endpoint.contractDir, config),
                'value': '${s.valueProperty} → ${s.valueType}',
                'label': s.labelProperty,
                'query': ?s.queryParam,
                'service': 'AppServices.${s.serviceName}',
              },
          ],
        if (app.mappers.isNotEmpty)
          'mappers': [
            for (final m in app.mappers)
              {'entity': m.entity.name, 'schema': m.schema.key, 'location': m.entity.location},
          ],
      },
    if (result.style case final style?)
      'style': {
        'source': style.source,
        'modes': style.modes,
        'colors': style.colors.length,
        if (style.colorExtensions.isNotEmpty) 'colorExtensions': style.colorExtensions,
        'buttons': style.buttons.keys.toList(),
        'breakpoints': style.breakpoints,
      },
    if (result.i18n case final i18n?)
      'i18n': {
        'base': i18n.base,
        'locales': i18n.locales,
        'frameworkKeys': i18n.messages.where((m) => m.isFramework).length,
        'appKeys': i18n.messages.where((m) => !m.isFramework).length,
        'withPlaceholders': i18n.messages.where((m) => m.arguments.isNotEmpty).length,
      },
    if (contracts) 'contractIR': [for (final c in result.contracts) c.toJson()],
  };
}

Map<String, Object?> _form(FormPlan f, StxConfig config) => {
  'name': f.base,
  'location': f.form.location,
  if (f.form.route case final route?) 'route': {'path': route.path, 'nav': route.nav},
  'submit': {
    ..._operation(f.operation, f.form.submit.contractDir, config),
    'body': f.bodyType,
    'response': f.responseType,
  },
  'onSuccess': f.form.onSuccess,
  'title': f.title,
  'requires': [
    for (final group in f.requires)
      if (group.isNotEmpty) group.join(' | '),
  ],
  'generated': {'controller': f.controller, 'page': f.page, if (f.form.route != null) 'route': f.route},
  'fields': [
    for (final field in f.fields)
      {
        'name': field.field.name,
        'type': field.type.code,
        'kind': field.kind.name,
        if (field.property case final p?)
          'property': '${p.wireName} (${_type(p.type)}${p.required ? ', required' : ''})',
        if (!field.rules.isEmpty) 'rules': _rules(field.rules),
        'label': field.label,
        'hint': ?field.hint,
        'help': ?field.help,
        if (field.source case final s?) 'source': s.source.name,
        if (field.widget case final w?) 'widget': w.name,
      },
  ],
};

Map<String, Object?> _operation(OperationIR o, String contractDir, StxConfig config) {
  final contract = config.contracts.where((c) => Naming.snake(c.name) == contractDir).firstOrNull;
  return {
    'operation': o.operationId,
    'http': '${o.method.name.toUpperCase()} ${o.path}',
    if (contract != null) 'contract': contract.name,
    if (contract != null) 'backend': contract.backend,
    'security': switch (o.security) {
      PublicSecurity() => 'public',
      AuthenticatedSecurity() || UndeclaredSecurity() => 'authenticated',
      ScopedSecurity(:final scopes) => 'any of ${scopes.join(', ')}',
    },
  };
}

String _type(TypeIR type) => switch (type.toJson()) {
  {'primitive': final kind} => '$kind',
  {'ref': final schema} => '$schema',
  {'list': _} => 'list',
  _ => 'map',
};

Map<String, Object?> _rules(Rules r) => {
  if (r.required) 'required': true,
  'minLength': ?r.minLength,
  'maxLength': ?r.maxLength,
  'minItems': ?r.minItems,
  'maxItems': ?r.maxItems,
  'minimum': ?r.minimum,
  'maximum': ?r.maximum,
  'pattern': ?r.pattern,
  'format': ?r.format,
};
