import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutterclaw/app.dart';
import 'package:flutterclaw/firebase_options.dart';
import 'package:flutterclaw/services/audio_player_service.dart';
import 'package:flutterclaw/services/background_service.dart';
import 'package:flutterclaw/services/live_activity_service.dart';
import 'package:logging/logging.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global Flutter error handler — catch widget-level crashes so they don't
  // kill the app silently. Logged to console for debugging.
  FlutterError.onError = (FlutterErrorDetails details) {
    // ignore: avoid_print
    print('[HERMES-FLUTTER-ERROR] ${details.exception}');
    if (details.stack != null) {
      // ignore: avoid_print
      print('[HERMES-FLUTTER-ERROR] Stack: ${details.stack}');
    }
  };

  // Also catch async errors not handled by Flutter
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    // ignore: avoid_print
    print('[HERMES-ASYNC-ERROR] $error');
    return true; // Don't kill the app
  };

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  // ignore: avoid_print
  print('ℹ️ Live Activities: deferred initialization (physical devices only)');

  // Initialize Firebase — wrapped in try-catch so a failure doesn't kill the app
  // Also add a 5-second timeout because Firebase can hang on the platform channel
  // when Google Play Services is unresponsive (common after killing and reopening).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    // ignore: avoid_print
    print('✅ Firebase initialized');
  } on TimeoutException {
    // ignore: avoid_print
    print('⚠️ Firebase init timed out (app will continue without Firebase)');
  } catch (e) {
    // ignore: avoid_print
    print('⚠️ Firebase init failed (app will continue without Firebase): $e');
  }

  // Initialize audio service on iOS only. On Android the gateway runs in a
  // foreground service so we don't need audio for keep-alive; media_play
  // / media_control will report "not initialized" on Android unless we add it here.
  if (Platform.isIOS) {
    try {
      await initAudioService();
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ audio_service init failed (background audio unavailable): $e');
    }
    // End any stale Live Activities left over from a previous session (force-close,
    // crash, etc.). The iOS gateway runs in-process, so if the app was killed the
    // gateway is definitely not running — it's always safe to clear here.
    try {
      await LiveActivityService.endAllActivities();
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ LiveActivityService cleanup failed: $e');
    }
  }

  // Only initialize flutter_foreground_task on Android
  // iOS uses a different approach with background audio
  if (Platform.isAndroid) {
    try {
      FlutterForegroundTask.initCommunicationPort();
      await BackgroundService.initializeService().timeout(const Duration(seconds: 5));
      // ignore: avoid_print
      print('✅ BackgroundService initialized');
    } on TimeoutException {
      // ignore: avoid_print
      print('⚠️ BackgroundService init timed out (app will continue)');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ BackgroundService init failed (app will continue): $e');
    }
  }

  // Always run the app, even if initialization failed
  runApp(const FlutterClawApp());
}
