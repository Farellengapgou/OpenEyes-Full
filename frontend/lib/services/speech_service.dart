import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Service de reconnaissance vocale locale.
/// Utilise le moteur STT natif du téléphone (iOS: Siri offline, Android: Google STT).
/// Remplace entièrement le backend Whisper Python.
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  String _lastRecognized = ""; // Stocke les résultats partiels

  /// Initialise le moteur STT. À appeler une seule fois au démarrage.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    _isInitialized = await _speech.initialize(
      onError: (error) => print('STT Error: ${error.errorMsg}'),
      onStatus: (status) => print('STT Status: $status'),
      debugLogging: false,
    );
    return _isInitialized;
  }

  /// Lance une écoute et retourne le texte transcrit.
  Future<String?> listen({
    Duration listenDuration = const Duration(seconds: 8),
    String localeId = 'fr_FR',
  }) async {
    // 1. Initialisation
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    // 2. Tentative avec retry interne
    String? result = await _listenInternal(listenDuration, localeId);
    
    // Si échec immédiat (null et moins de 1s écoulée), on réessaye une fois après une pause
    if (result == null) {
      print("STT: First attempt failed, retrying in 800ms...");
      await Future.delayed(const Duration(milliseconds: 800));
      result = await _listenInternal(listenDuration, localeId);
    }

    return result;
  }

  /// Logique interne d'écoute avec gestion des arrêts prématurés.
  Future<String?> _listenInternal(Duration listenDuration, String localeId) async {
    final completer = Completer<String?>();
    _lastRecognized = "";
    final startTime = DateTime.now();

    // Délai de sécurité pour le hardware
    await Future.delayed(const Duration(milliseconds: 150));

    print("STT: Listening internal start...");

    _speech.statusListener = (status) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print("STT Status ($elapsed ms): $status");

      if ((status == 'done' || status == 'notListening')) {
        // Si arrêt trop rapide (<700ms) et rien capté, on considère que c'est un bug hardware/focus
        if (elapsed < 700 && _lastRecognized.isEmpty) {
          print("STT: Premature stop detected, ignoring for now.");
          return;
        }

        if (!completer.isCompleted) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!completer.isCompleted) {
              completer.complete(_lastRecognized.isNotEmpty ? _lastRecognized : null);
            }
          });
        }
      }
    };

    try {
      await _speech.listen(
        onResult: (val) {
          _lastRecognized = val.recognizedWords;
          if (val.finalResult && !completer.isCompleted) {
            completer.complete(_lastRecognized);
          }
        },
        listenFor: listenDuration,
        pauseFor: const Duration(seconds: 4),
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          onDevice: true,
        ),
      );
    } catch (e) {
      print("STT: listen() error: $e");
      return null;
    }

    return await completer.future.timeout(
      listenDuration + const Duration(seconds: 2),
      onTimeout: () {
        _speech.stop();
        return _lastRecognized.isNotEmpty ? _lastRecognized : null;
      },
    );
  }

  /// Écoute une confirmation Oui/Non.
  /// Retourne [ConfirmationResult.yes], [ConfirmationResult.no] ou [ConfirmationResult.unclear].
  Future<ConfirmationResult> listenConfirmation() async {
    final text = await listen(listenDuration: const Duration(seconds: 5));
    if (text == null || text.trim().isEmpty) return ConfirmationResult.unclear;

    final lower = text.toLowerCase().trim();

    const yesKeywords = [
      'oui', 'yes', 'ok', "d'accord", 'daccord', 'exactement',
      'correct', 'parfait', 'vas-y', 'vas y', 'allons-y', 'allons y', 'go',
    ];
    const noKeywords = [
      'non', 'no', 'pas ça', 'pas ca', 'pas correct', 'mauvais',
      'annuler', 'stop', 'arrête', 'arreter',
    ];

    if (yesKeywords.any((k) => lower.contains(k))) return ConfirmationResult.yes;
    if (noKeywords.any((k) => lower.contains(k))) return ConfirmationResult.no;
    return ConfirmationResult.unclear;
  }

  void stop() => _speech.stop();

  void dispose() => _speech.cancel();
}

enum ConfirmationResult { yes, no, unclear }
