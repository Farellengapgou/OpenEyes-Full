import 'dart:async';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Service de reconnaissance vocale locale.
/// STT natif Android / iOS
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  String _lastRecognized = "";

  /// Initialisation (à appeler au démarrage)
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    _isInitialized = await _speech.initialize(
      debugLogging: false,
      onError: (e) => print("STT Error: ${e.errorMsg}"),
      onStatus: (s) => print("STT Status: $s"),
    );
    return _isInitialized;
  }

  /// Écoute principale – minimum 6 secondes garanties
  Future<String?> listen({
    Duration listenDuration = const Duration(seconds: 20),
    String localeId = 'fr_FR',
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    return _listenInternal(listenDuration, localeId);
  }

  Future<String?> _listenInternal(Duration listenDuration, String localeId) async {
    final completer = Completer<String?>();
    _lastRecognized = "";

    bool hasStartedListening = false;
    DateTime? listeningStart;

    // ⚠️ Stop UNIQUEMENT si déjà en écoute (PAS de cancel)
    if (_speech.isListening) {
      await _speech.stop();
    }

    _speech.statusListener = (status) {
      print("STT Status: $status");

      // ✅ VIBRATION AU MOMENT EXACT OÙ LE MICRO S’OUVRE
      if (status == 'listening' && !hasStartedListening) {
        hasStartedListening = true;
        listeningStart = DateTime.now();
        HapticFeedback.heavyImpact();
      }

      if (status == 'done' || status == 'notListening') {
        if (!hasStartedListening || listeningStart == null) return;

        // On vibre deux fois à la fin pour bien marquer
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.lightImpact());

        if (!completer.isCompleted) {
          completer.complete(
            _lastRecognized.isNotEmpty ? _lastRecognized : null,
          );
        }
      }
    };

    try {
      await _speech.listen(
        localeId: localeId,
        listenFor: const Duration(seconds: 40),
        pauseFor: const Duration(seconds: 15),
        partialResults: true,
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          onDevice: true, // 🔥 réduit fortement la latence si supporté
        ),
        onResult: (result) {
          _lastRecognized = result.recognizedWords;

          if (result.finalResult && !completer.isCompleted) {
            completer.complete(_lastRecognized);
          }
        },
      );
    } catch (e) {
      print("STT listen error: $e");
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future.timeout(
      listenDuration + const Duration(seconds: 4),
      onTimeout: () {
        print("STT Timeout");
        _speech.stop();
        return _lastRecognized.isNotEmpty ? _lastRecognized : null;
      },
    );
  }

  /// Confirmation Oui / Non
  Future<ConfirmationResult> listenConfirmation() async {
    final text = await listen(
      listenDuration: const Duration(seconds: 15),
    );

    if (text == null || text.isEmpty) {
      return ConfirmationResult.unclear;
    }

    final lower = text.toLowerCase();

    const yes = [
      'oui',
      'yes',
      'ok',
      "d'accord",
      'vas-y',
      'go',
      'parfait',
    ];

    const no = [
      'non',
      'no',
      'annuler',
      'stop',
      'pas',
    ];

    if (yes.any(lower.contains)) return ConfirmationResult.yes;
    if (no.any(lower.contains)) return ConfirmationResult.no;

    return ConfirmationResult.unclear;
  }

  void stop() => _speech.stop();

  void dispose() => _speech.cancel();
}

enum ConfirmationResult { yes, no, unclear }