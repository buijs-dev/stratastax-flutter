import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../diagnostics.dart';
import 'ui_ir.dart';

/// Diagnostic codes of the UI stage (docs/ARCHITECTURE.md §12).
abstract final class UiCodes {
  static const unmappedRequired = 'STX-U001';
  static const unmappedField = 'STX-U002';
  static const typeMismatch = 'STX-U003';
  static const loosened = 'STX-U004';
  static const widgetType = 'STX-U005';
  static const route = 'STX-U006';
  static const dataSource = 'STX-U007';
  static const order = 'STX-U008';

  /// An annotation could not be evaluated (unresolved reference) or is used wrongly.
  static const annotation = 'STX-U009';
}

/// Reads the annotated classes of the app (`lib/`, except the generated output) with the analyzer,
/// fully resolved: annotation arguments are evaluated constants, so `submit: MatchesApiV1.createMatch`
/// is the generated endpoint constant itself, and field types are real types.
final class AnnotationFrontend {
  AnnotationFrontend(this.projectDir, this.outputDir, this.diagnostics);

  final String projectDir;
  final String outputDir;
  final Diagnostics diagnostics;

  final _forms = <FormIR>[];
  final _entities = <String, EntityIR>{};
  final _dataSources = <String, DataSourceIR>{};
  final _fieldWidgets = <String, FieldWidgetIR>{};

  Future<UiIR> parse() async {
    final lib = p.normalize(p.absolute(projectDir, 'lib'));
    final output = p.normalize(p.absolute(outputDir));
    final collection = AnalysisContextCollection(includedPaths: [lib], excludedPaths: [output]);
    final files = <String>[];
    for (final context in collection.contexts) {
      files.addAll(context.contextRoot.analyzedFiles().where((f) => f.endsWith('.dart')));
    }
    files.sort();
    for (final file in files) {
      final result = await collection.contextFor(file).currentSession.getResolvedLibrary(file);
      if (result is ResolvedLibraryResult) _library(result.element);
    }
    _forms.sort((a, b) => a.name.compareTo(b.name));
    return UiIR(
      package: _packageName(),
      forms: _forms,
      entities: _entities,
      dataSources: _dataSources,
      fieldWidgets: _fieldWidgets,
    );
  }

  String _packageName() {
    final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
    final yaml = pubspec.existsSync() ? loadYaml(pubspec.readAsStringSync()) : null;
    return yaml is YamlMap ? yaml['name'].toString() : p.basename(projectDir);
  }

  void _library(LibraryElement library) {
    for (final element in [...library.classes, ...library.extensionTypes]) {
      final annotations = _stx(element);
      if (annotations.isEmpty) continue;
      if (annotations['UiForm'] case final form?) {
        _form(element as ClassElement, form, annotations);
      } else if (annotations.containsKey('DomainEntity') && element is ClassElement) {
        _entities[element.name!] = EntityIR(
          name: element.name!,
          library: library.uri.toString(),
          location: _location(element),
          fields: _fields(element),
        );
      }
      if (annotations['UiDataSource'] case final source?) _dataSource(element, source);
      if (annotations['UiFieldWidget'] != null && element is ClassElement) _fieldWidget(element);
    }
  }

  /// The stx annotations on [element], by annotation class name.
  Map<String, DartObject> _stx(Element element) {
    final result = <String, DartObject>{};
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      final library = type?.element?.library?.uri.toString() ?? '';
      if (value == null) {
        final source = annotation.toSource();
        if (source.startsWith('@Ui') || source.startsWith('@Domain') || source.startsWith('@Build')) {
          diagnostics.error(
            UiCodes.annotation,
            'cannot evaluate $source: ${(annotation.constantEvaluationErrors ?? const []).map((e) => e.message).join('; ')}',
            location: _location(element),
            hint: 'run `stx build` once so the generated constants it refers to exist',
          );
        }
        continue;
      }
      if (library.startsWith('package:stx_annotations/')) result[type!.element!.name!] = value;
    }
    return result;
  }

  void _form(ClassElement element, DartObject form, Map<String, DartObject> annotations) {
    final submit = _endpoint(form.getField('submit'), element, 'UiForm.submit');
    if (submit == null) return;
    final route = annotations['UiRoute'];
    final requires = annotations['UiRequires']?.getField('scopes')?.toListValue() ?? const [];
    _forms.add(
      FormIR(
        name: element.name!,
        library: element.library.uri.toString(),
        location: _location(element),
        submit: submit,
        onSuccess: _enumName(form.getField('onSuccess')) ?? 'back',
        fields: _fields(element),
        route: route == null
            ? null
            : RouteIR(
                path: route.getField('path')?.toStringValue() ?? '/',
                nav: _enumName(route.getField('nav')) ?? 'none',
              ),
        requires: [for (final scope in requires) ?scope.getField('claim')?.toStringValue()],
      ),
    );
  }

  List<FieldIR> _fields(ClassElement element) {
    final constructor = element.unnamedConstructor;
    final params = {for (final p in constructor?.formalParameters ?? const <FormalParameterElement>[]) p.name: p};
    return [
      for (final field in element.fields)
        if (!field.isStatic && field.isOriginDeclaration) _field(field, params[field.name]),
    ];
  }

  FieldIR _field(FieldElement field, FormalParameterElement? param) {
    final a = _stx(field);
    final validate = a['UiFieldValidate'];
    int? intField(String name) => validate?.getField(name)?.toIntValue();
    num? numField(String name) => validate?.getField(name)?.toIntValue() ?? validate?.getField(name)?.toDoubleValue();
    return FieldIR(
      name: field.name!,
      type: _type(field.type),
      location: _location(field),
      order: a['UiFormOrder']?.getField('order')?.toIntValue(),
      kind: _enumName(a['UiFieldType']?.getField('kind')),
      labelKeyId: a['UiFieldLabel']?.getField('key')?.getField('id')?.toIntValue(),
      hint: a.containsKey('UiFieldHint'),
      help: a.containsKey('UiFieldHelp'),
      dataSource: a['UiFieldDataSource']?.getField('source')?.toTypeValue()?.element?.name,
      widget: a['UiFieldWidget']?.getField('widget')?.toTypeValue()?.element?.name,
      contractProperty: a['ContractProperty']?.getField('name')?.toStringValue(),
      ignore: a.containsKey('UiIgnore'),
      validate: UiValidateIR(
        required: validate?.getField('required')?.toBoolValue(),
        minLength: intField('minLength'),
        maxLength: intField('maxLength'),
        minItems: intField('minItems'),
        maxItems: intField('maxItems'),
        minimum: numField('minimum'),
        maximum: numField('maximum'),
        pattern: validate?.getField('pattern')?.toStringValue(),
      ),
      hasDefault: param?.hasDefaultValue ?? false,
    );
  }

  void _dataSource(Element element, DartObject source) {
    final endpoint = _endpoint(source.getField('endpoint'), element, 'UiDataSource.endpoint');
    if (endpoint == null) return;
    _dataSources[element.name!] = DataSourceIR(
      name: element.name!,
      library: element.library!.uri.toString(),
      location: _location(element),
      endpoint: endpoint,
      query: source.getField('query')?.toStringValue(),
      value: source.getField('value')?.toStringValue() ?? 'id',
      label: source.getField('label')?.toStringValue() ?? 'displayName',
    );
  }

  void _fieldWidget(ClassElement element) {
    final supertype = element.allSupertypes.where((t) => t.element.name == 'StxFieldWidget').firstOrNull;
    if (supertype == null) {
      diagnostics.error(
        UiCodes.widgetType,
        '${element.name} is annotated with @UiFieldWidget but does not extend StxFieldWidget<T>',
        location: _location(element),
      );
    }
    _fieldWidgets[element.name!] = FieldWidgetIR(
      name: element.name!,
      library: element.library.uri.toString(),
      location: _location(element),
      valueType: supertype == null ? null : _type(supertype.typeArguments.single),
    );
  }

  EndpointRef? _endpoint(DartObject? value, Element owner, String what) {
    // Generated endpoints subclass Endpoint per backend: the field sits in the `(super)` part.
    DartObject? field(DartObject? object, String name) =>
        object == null ? null : object.getField(name) ?? field(object.getField('(super)'), name);
    final operationId = field(value, 'operationId')?.toStringValue();
    final variable = value?.variable;
    final api = variable?.enclosingElement;
    if (operationId == null || variable == null || api == null) {
      diagnostics.error(
        UiCodes.annotation,
        '$what must be a generated endpoint constant, e.g. MatchesApiV1.createMatch',
        location: _location(owner),
      );
      return null;
    }
    return EndpointRef(
      operationId: operationId,
      apiClass: api.name!,
      member: variable.name!,
      library: variable.library!.uri.toString(),
    );
  }

  String? _enumName(DartObject? value) => value?.variable?.name;

  DartTypeRef _type(DartType type) {
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
    if (type is! InterfaceType) {
      return DartTypeRef(name: type.getDisplayString(), kind: TypeKind.other, nullable: nullable);
    }
    final element = type.element;
    final name = element.name!;
    final library = element.library.uri.toString();
    final args = [for (final a in type.typeArguments) _type(a)];
    TypeKind kind;
    DartTypeRef? target;
    String? representation;
    var values = const <String>[];

    final converter = element.metadata.annotations
        .map((a) => a.computeConstantValue())
        .where((v) => v?.type?.element?.name == 'BuildTypeConverter')
        .firstOrNull;
    if (library == 'dart:core') {
      kind = switch (name) {
        'String' => TypeKind.string,
        'int' => TypeKind.int,
        'double' => TypeKind.double,
        'bool' => TypeKind.bool,
        'DateTime' => TypeKind.dateTime,
        'List' => TypeKind.list,
        _ => TypeKind.other,
      };
    } else if (library.startsWith('package:stx_core/')) {
      kind = switch (name) {
        'Uuid' => TypeKind.uuid,
        'Email' => TypeKind.email,
        'LocalDate' => TypeKind.localDate,
        _ => TypeKind.other,
      };
    } else if (converter != null) {
      // The wrapped field's own type: constant evaluation erases extension types, so the
      // annotation's `target` would report `String` for `Uuid`.
      kind = TypeKind.converter;
      final field = element is ExtensionTypeElement
          ? element.representation
          : element.fields.where((f) => !f.isStatic && f.isOriginDeclaration).firstOrNull;
      representation = field?.name;
      target = field == null ? null : _type(field.type);
    } else if (element is EnumElement) {
      kind = TypeKind.enumType;
      values = [for (final c in element.constants) c.name!];
    } else if (library.contains('/gen/contract/')) {
      kind = TypeKind.contractModel;
    } else if (element.metadata.annotations.any(
      (a) => a.computeConstantValue()?.type?.element?.name == 'DomainEntity',
    )) {
      kind = TypeKind.entity;
    } else {
      kind = TypeKind.other;
    }
    return DartTypeRef(
      name: name,
      kind: kind,
      library: library,
      args: args,
      nullable: nullable,
      converterTarget: target,
      representation: representation,
      enumValues: values,
    );
  }

  String _location(Element element) {
    final fragment = element.firstFragment;
    final library = fragment.libraryFragment;
    final path = library?.source.fullName;
    if (path == null) return element.name ?? '?';
    final offset = fragment.nameOffset ?? 0;
    final line = library!.lineInfo.getLocation(offset).lineNumber;
    return '${p.relative(path, from: projectDir)}:$line';
  }
}
