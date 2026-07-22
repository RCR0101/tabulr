import 'package:flutter/material.dart';

/// Asks to leave the current route, running [onLeft] only if it actually goes.
///
/// A `PopScope` guard — the editor's unsaved-changes prompt, for one — can
/// refuse the pop, and [Navigator.maybePop] reports only that *something
/// handled* the request, not whether the route went away. Waiting on the
/// route's own `popped` future is what tells the truth: it completes on a real
/// pop and never completes if the user backs out.
///
/// Use this whenever an action has to happen "after we leave here" and leaving
/// might be declined. Doing the work up front instead leaves the app in a state
/// the user never asked for when they cancel.
void popThen(BuildContext context, VoidCallback onLeft) {
  final route = ModalRoute.of(context);
  if (route == null) return;
  route.popped.then((_) => onLeft());
  Navigator.maybePop(context);
}
