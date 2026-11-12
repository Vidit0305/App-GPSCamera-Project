import 'package:flutter/services.dart';

/// Vibration feedback for every button press in the app.
///
/// Uses the platform haptic engine (no extra permission). Android devices
/// with "Touch feedback" turned off in system settings won't vibrate.
abstract final class Haptics {
  /// Standard button press.
  static void tap() => HapticFeedback.mediumImpact();

  /// Small selection change (switches, chips, choices).
  static void select() => HapticFeedback.selectionClick();

  /// Important / destructive confirmation.
  static void heavy() => HapticFeedback.heavyImpact();
}

/// Wraps a button callback so it vibrates before running. Keeps `null`
/// (disabled buttons stay disabled).
VoidCallback? hx(VoidCallback? action) => action == null
    ? null
    : () {
        Haptics.tap();
        action();
      };

/// Same as [hx] for value callbacks (switches, chips, segmented buttons).
ValueChanged<T>? hxv<T>(ValueChanged<T>? action) => action == null
    ? null
    : (T v) {
        Haptics.select();
        action(v);
      };
