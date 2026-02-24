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
    Duration listenDuration = const Duration(seconds: 8),
    String localeId = 'fr_FR',
  }) async {
    // Toujours réinitialiser si nécessaire
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    // On ne bloque plus sur hasPermission (requis séparément via permission_handler)
    final completer = Completer<String?>();

    // Petit délai réduit pour s'assurer que le TTS a fini (le délai principal est géré dans main.dart)
    await Future.delayed(const Duration(milliseconds: 100));

    print("STT: Starting to listen... (locale: $localeId)");
    
    // Définir un statusListener temporaire pour ce call
    _speech.statusListener = (status) {
      print("STT Runtime Status: $status");
      if ((status == 'done' || status == 'notListening') && !completer.isCompleted) {
        // Si le moteur s'arrête sans avoir envoyé de résultat final
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!completer.isCompleted) completer.complete(null);
        });
      }
    };
    _speech.listen(
      onResult: (val) {
        print("STT Result: ${val.recognizedWords} (final: ${val.finalResult})");
        if (val.finalResult && !completer.isCompleted) {
          completer.complete(val.recognizedWords);
        }
      },
      listenFor: listenDuration,
      pauseFor: const Duration(seconds: 4), // 4s de silence avant d'arrêter
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true, // permet de recevoir des résultats partiels
      ),
    );

    // Attendre la fin d'écoute (résultat final ou timeout)
    final result = await completer.future.timeout(
      listenDuration + const Duration(seconds: 5),
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
