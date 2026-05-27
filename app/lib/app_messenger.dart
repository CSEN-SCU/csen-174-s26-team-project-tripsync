import 'package:flutter/material.dart';

/// Root [ScaffoldMessenger] so voice/fallback toasts show from any screen.
final GlobalKey<ScaffoldMessengerState> orbitMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showOrbitSnack(String message, {Duration? duration}) {
  orbitMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 5),
    ),
  );
}
