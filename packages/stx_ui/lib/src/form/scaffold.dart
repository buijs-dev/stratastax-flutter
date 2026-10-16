import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../primitives/button.dart';
import '../primitives/layout.dart';
import 'controller.dart';
import 'field.dart';

/// The page body of a generated form: title, problem banner, fields and the submit button.
class StxFormScaffold<C, B, R> extends StatelessWidget {
  const StxFormScaffold({
    super.key,
    required this.title,
    required this.form,
    required this.client,
    required this.children,
    this.description,
    this.submitLabel = StxKeys.actionSave,
    this.onSuccess,
  });

  final Msg title;
  final Msg? description;
  final StxFormController<C, B, R> form;
  final StxClient client;
  final List<Widget> children;
  final Msg submitLabel;
  final void Function(R response)? onSuccess;

  Future<void> _submit() async {
    final result = await form.submit(client);
    if (result case Ok(:final value)) onSuccess?.call(value);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: StxBox(
          padding: const StxInsets.all(SpaceToken.lg),
          child: FocusTraversalGroup(
            child: ListenableBuilder(
              listenable: form,
              builder: (context, _) => StxColumn(
                gap: SpaceToken.lg,
                mainAxisSize: MainAxisSize.min,
                children: [
                  StxText(title, style: TextToken.header1),
                  if (description != null) StxText(description!, color: ColorToken.muted),
                  if (form.status case FormFailed(:final problem)) _ProblemBanner(problem),
                  if (form.status is FormSucceeded)
                    const _Banner(
                      message: StxKeys.savedMessage,
                      background: ColorToken.success,
                      foreground: ColorToken.onSuccess,
                    ),
                  ...children,
                  Align(
                    alignment: Alignment.centerRight,
                    child: StxButton(submitLabel, busy: form.submitting, onPressed: _submit),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner(this.problem);

  final Problem problem;

  @override
  Widget build(BuildContext context) =>
      _Banner(message: problemMsg(problem), background: ColorToken.danger, foreground: ColorToken.onDanger);
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.background, required this.foreground});

  final Msg message;
  final ColorToken background;
  final ColorToken foreground;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: StxBox(
      padding: const StxInsets.all(SpaceToken.md),
      background: background,
      radius: RadiusToken.md,
      child: StxText(message, color: foreground),
    ),
  );
}
