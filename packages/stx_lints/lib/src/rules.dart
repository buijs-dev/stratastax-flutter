import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

/// Every stx rule: keep apps token-only, string-free and on flutter/widgets.
final allRules = <AnalysisRule>[NoMaterialImport(), NoRawColor(), NoRawInsets(), NoStringInUi(), NoGeneratedTokens()];

/// Base of the stx rules.
abstract class _StxRule extends AnalysisRule {
  _StxRule({required super.name, required super.description});
}

/// The rules cover app UI code: files under `lib/`, except generated code (`lib/gen/`), which may
/// use raw values by design, and the stx framework packages themselves, which implement the tokens.
/// Tests, tools and scripts may use literals.
bool _exempt(AstNode node) {
  final source = (node.root as CompilationUnit).declaredFragment?.source;
  final path = (source?.fullName ?? '').replaceAll(r'\', '/');
  final uri = source?.uri.toString() ?? '';
  return !path.contains('/lib/') || path.contains('/lib/gen/') || uri.startsWith('package:stx_');
}

bool _from(Element? element, String library) => element?.library?.uri.toString().startsWith(library) ?? false;

/// `package:flutter/material.dart` / `cupertino.dart`: the stx widgets are the design system.
final class NoMaterialImport extends _StxRule {
  NoMaterialImport() : super(name: 'stx_no_material_import', description: 'Do not import material or cupertino.');

  static const code = LintCode(
    'stx_no_material_import',
    "Don't import '{0}': stx apps use flutter/widgets and stx_ui.",
    correctionMessage: "Use stx_ui widgets and 'package:flutter/widgets.dart'.",
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) =>
      registry.addImportDirective(this, _Imports(this));
}

final class _Imports extends SimpleAstVisitor<void> {
  _Imports(this.rule);

  final NoMaterialImport rule;

  @override
  void visitImportDirective(ImportDirective node) {
    if (_exempt(node)) return;
    final uri = node.uri.stringValue;
    if (uri == 'package:flutter/material.dart' || uri == 'package:flutter/cupertino.dart') {
      rule.reportAtNode(node.uri, arguments: [uri!]);
    }
  }
}

/// Instance creations in app code, matched by class and library.
abstract class _CreationRule extends _StxRule {
  _CreationRule({required super.name, required super.description});

  bool matches(InstanceCreationExpression node);

  void report(InstanceCreationExpression node) => reportAtNode(node.constructorName);

  @override
  void registerNodeProcessors(RuleVisitorRegistry registry, RuleContext context) =>
      registry.addInstanceCreationExpression(this, _Creations(this));
}

final class _Creations extends SimpleAstVisitor<void> {
  _Creations(this.rule);

  final _CreationRule rule;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_exempt(node) && rule.matches(node)) rule.report(node);
  }
}

/// `Color(…)`: colors come from `ColorToken`s (stx.tokens.yaml).
final class NoRawColor extends _CreationRule {
  NoRawColor() : super(name: 'stx_no_raw_color', description: 'Use ColorTokens instead of Color values.');

  static const code = LintCode(
    'stx_no_raw_color',
    'Raw colors bypass the design tokens.',
    correctionMessage: 'Use a ColorToken (or add one under color.extend in stx.tokens.yaml).',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool matches(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    return type?.name == 'Color' && _from(type, 'dart:ui');
  }
}

/// `EdgeInsets…(…)`: spacing comes from `SpaceToken`s (`StxInsets`, `gap:`).
final class NoRawInsets extends _CreationRule {
  NoRawInsets() : super(name: 'stx_no_raw_insets', description: 'Use SpaceTokens instead of EdgeInsets.');

  static const code = LintCode(
    'stx_no_raw_insets',
    'Raw insets bypass the spacing scale.',
    correctionMessage: 'Use StxInsets with SpaceTokens, a gap on StxRow/StxColumn, or Pad/Gaps from lib/gen/style.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool matches(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    return (type?.name == 'EdgeInsets' || type?.name == 'EdgeInsetsDirectional') && _from(type, 'package:flutter/');
  }
}

/// `Msg.data('…')` or `Text('…')` with a literal: UI copy belongs in i18n/*.yaml.
final class NoStringInUi extends _CreationRule {
  NoStringInUi() : super(name: 'stx_no_string_in_ui', description: 'UI text comes from translation keys.');

  static const code = LintCode(
    'stx_no_string_in_ui',
    'UI text is a string literal.',
    correctionMessage: 'Add a key to i18n/<locale>.yaml and use its Msg constant; Msg.data is for user data only.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool matches(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    final isMsgData =
        type?.name == 'Msg' && node.constructorName.name?.name == 'data' && _from(type, 'package:stx_i18n/');
    final isText = type?.name == 'Text' && node.constructorName.name == null && _from(type, 'package:flutter/');
    if (!isMsgData && !isText) return false;
    final first = node.argumentList.arguments.firstOrNull;
    return first is StringLiteral && first is! StringInterpolation;
  }

  @override
  void report(InstanceCreationExpression node) => reportAtNode(node.argumentList.arguments.first);
}

/// `ColorToken.generated(…)` / `ButtonVariant.generated(…)` outside lib/gen: ids are assigned by
/// the compiler.
final class NoGeneratedTokens extends _CreationRule {
  NoGeneratedTokens() : super(name: 'stx_no_generated_tokens', description: 'Token ids are assigned by stx_compiler.');

  static const code = LintCode(
    'stx_no_generated_tokens',
    "'{0}.generated' is for generated code.",
    correctionMessage: 'Declare the token under `extend` in stx.tokens.yaml and use AppColor / AppButton.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  bool matches(InstanceCreationExpression node) {
    final type = node.constructorName.type.element;
    return (type?.name == 'ColorToken' || type?.name == 'ButtonVariant') &&
        node.constructorName.name?.name == 'generated' &&
        _from(type, 'package:stx_style/');
  }

  @override
  void report(InstanceCreationExpression node) =>
      reportAtNode(node.constructorName, arguments: [node.constructorName.type.element!.name!]);
}
