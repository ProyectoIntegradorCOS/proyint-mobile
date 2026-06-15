import 'package:flutter/foundation.dart';

void logDebug(String message, {Object? details}) {
  if (!kDebugMode) return;
  final buffer = StringBuffer('[DEBUG] $message');
  if (details != null) {
    buffer.write(' | details: $details');
  }
  // ignore: avoid_print
  print(buffer.toString());
}

void logInfo(String message, {Object? details}) {
  if (!kDebugMode) return;
  final buffer = StringBuffer('[INFO] $message');
  if (details != null) {
    buffer.write(' | details: $details');
  }
  // ignore: avoid_print
  print(buffer.toString());
}

void logWarn(String message, {Object? details}) {
  if (!kDebugMode) return;
  final buffer = StringBuffer('[WARN] $message');
  if (details != null) {
    buffer.write(' | details: $details');
  }
  // ignore: avoid_print
  print(buffer.toString());
}

void logError(String message, {Object? error, StackTrace? stackTrace}) {
  final buffer = StringBuffer('[ERROR] $message');
  if (error != null) {
    buffer.write(' | error: $error');
  }
  if (stackTrace != null) {
    buffer.write('\n$stackTrace');
  }
  // ignore: avoid_print
  print(buffer.toString());
}
