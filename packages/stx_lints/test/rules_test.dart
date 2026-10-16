// test_reflective_loader runs methods named test_*.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/utilities/package_config_file_builder.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:stx_lints/stx_lints.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NoMaterialImportTest);
    defineReflectiveTests(NoRawColorTest);
    defineReflectiveTests(NoRawInsetsTest);
    defineReflectiveTests(NoStringInUiTest);
    defineReflectiveTests(NoGeneratedTokensTest);
  });
}

/// Flutter plus minimal stand-ins for stx_i18n and stx_style.
abstract class _StxRuleTest extends AnalysisRuleTest {
  @override
  bool get addFlutterPackageDep => true;

  @override
  void writeTestPackageConfig(PackageConfigFileBuilder config) {
    newFile('/packages/stx_i18n/lib/stx_i18n.dart', '''
sealed class Msg {
  const Msg();
  const factory Msg.data(String text) = MsgData;
}
final class MsgData extends Msg {
  const MsgData(this.text);
  final String text;
}
''');
    newFile('/packages/stx_style/lib/stx_style.dart', '''
extension type const ColorToken._(int id) implements Object {
  static const primary = ColorToken._(0);
  const ColorToken.generated(int id) : this._(id);
}
''');
    config.add(name: 'stx_i18n', rootPath: convertPath('/packages/stx_i18n'));
    config.add(name: 'stx_style', rootPath: convertPath('/packages/stx_style'));
    super.writeTestPackageConfig(config);
  }
}

@reflectiveTest
class NoMaterialImportTest extends _StxRuleTest {
  @override
  void setUp() {
    rule = NoMaterialImport();
    super.setUp();
  }

  Future<void> test_material() async {
    await assertDiagnostics(
      r'''
// ignore: unused_import
import 'package:flutter/material.dart';
''',
      [lint(32, 31)],
    );
  }

  Future<void> test_widgets() async {
    await assertNoDiagnostics(r'''
// ignore: unused_import
import 'package:flutter/widgets.dart';
''');
  }
}

@reflectiveTest
class NoRawColorTest extends _StxRuleTest {
  @override
  void setUp() {
    rule = NoRawColor();
    super.setUp();
  }

  Future<void> test_color() async {
    await assertDiagnostics(
      r'''
import 'dart:ui';
final c = Color(0xFF000000);
''',
      [lint(28, 5)],
    );
  }

  Future<void> test_generatedCodeIsExempt() async {
    newFile('$testPackageLibPath/gen/style/tokens.g.dart', r'''
import 'dart:ui';
final c = Color(0xFF000000);
''');
    await assertNoDiagnosticsInFile('$testPackageLibPath/gen/style/tokens.g.dart');
  }
}

@reflectiveTest
class NoRawInsetsTest extends _StxRuleTest {
  @override
  void setUp() {
    rule = NoRawInsets();
    super.setUp();
  }

  Future<void> test_edgeInsets() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final p = EdgeInsets.all(8);
''',
      [lint(49, 14)],
    );
  }
}

@reflectiveTest
class NoStringInUiTest extends _StxRuleTest {
  @override
  void setUp() {
    rule = NoStringInUi();
    super.setUp();
  }

  Future<void> test_msgDataLiteral() async {
    await assertDiagnostics(
      r'''
import 'package:stx_i18n/stx_i18n.dart';
const m = Msg.data('Save');
''',
      [lint(60, 6)],
    );
  }

  Future<void> test_msgDataVariable() async {
    await assertNoDiagnostics(r'''
import 'package:stx_i18n/stx_i18n.dart';
Msg name(String player) => Msg.data(player);
''');
  }

  Future<void> test_textLiteral() async {
    await assertDiagnostics(
      r'''
import 'package:flutter/widgets.dart';
final t = Text('Hello');
''',
      [lint(54, 7)],
    );
  }

  Future<void> test_textInterpolationIsData() async {
    await assertNoDiagnostics(r'''
import 'package:flutter/widgets.dart';
Widget score(int n) => Text('$n');
''');
  }
}

@reflectiveTest
class NoGeneratedTokensTest extends _StxRuleTest {
  @override
  void setUp() {
    rule = NoGeneratedTokens();
    super.setUp();
  }

  Future<void> test_generated() async {
    await assertDiagnostics(
      r'''
import 'package:stx_style/stx_style.dart';
const c = ColorToken.generated(40);
''',
      [lint(53, 20)],
    );
  }

  Future<void> test_slot() async {
    await assertNoDiagnostics(r'''
import 'package:stx_style/stx_style.dart';
const c = ColorToken.primary;
''');
  }
}
