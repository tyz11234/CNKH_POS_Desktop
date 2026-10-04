import 'package:flutter/material.dart';

/// Wait for the dialog's exit animation and widget removal before callers
/// dispose controllers used by its fields.
Future<T?> showCompletedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    barrierColor:
        DialogTheme.of(context).barrierColor ??
        Theme.of(context).dialogTheme.barrierColor ??
        Colors.black54,
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}
