import 'package:flutter/material.dart';

/// Root [ScaffoldMessenger] so voice/fallback toasts show from any screen.
final GlobalKey<ScaffoldMessengerState> tripSyncMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showTripSyncSnack(String message, {Duration? duration}) {
  tripSyncMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 5),
    ),
  );
}
