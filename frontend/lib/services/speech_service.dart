import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Service de reconnaissance vocale locale.
/// Utilise le moteur STT natif du téléphone (iOS: Siri offline, Android: Google STT).
/// Remplace entièrement le backend Whisper Python.
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

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
  /// Retourne null si rien n'est capturé ou si une erreur survient.
  Future<String?> listen({
    Duration listenDuration = const Duration(seconds: 6),
    String localeId = 'fr_FR',
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    if (!await _speech.hasPermission) return null;

    final completer = Completer<String?>();

    _speech.listen(
      onResult: (val) {
        if (val.finalResult && !completer.isCompleted) {
          completer.complete(val.recognizedWords);
        }
      },
      listenFor: listenDuration,
      pauseFor: const Duration(seconds: 2),
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: false,
      ),
    );

    // Attendre la fin d'écoute (résultat final ou timeout)
    final result = await completer.future.timeout(
      listenDuration + const Duration(seconds: 3),
      onTimeout: () {
        _speech.stop();
        return null;
      },
    );

    return (result != null && result.trim().isNotEmpty) ? result.trim() : null;
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
