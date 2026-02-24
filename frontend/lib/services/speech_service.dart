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
    Duration listenDuration = const Duration(seconds: 10),
    String localeId = 'fr_FR',
  }) async {
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    // 1ère tentative
    print("STT: Attempt 1...");
    String? result = await _listenInternal(listenDuration, localeId);
    
    // Si échec (null ou vide), on retente une fois après une pause plus longue
    if (result == null || result.trim().isEmpty) {
      print("STT: First attempt failed, retrying in 1200ms...");
      await Future.delayed(const Duration(milliseconds: 1200));
      result = await _listenInternal(listenDuration, localeId);
    }

    return (result != null && result.trim().isNotEmpty) ? result.trim() : null;
  }

  /// Logique d'écoute protégée contre les arrêts prématurés et conflits client
  Future<String?> _listenInternal(Duration listenDuration, String localeId) async {
    // SECURITE : On arrête tout avant de commencer pour éviter "error_client"
    try {
      await _speech.stop();
      await _speech.cancel();
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      print("STT Cleanup error (ignored): $e");
    }

    final completer = Completer<String?>();
    _lastRecognized = "";
    final start = DateTime.now();

    print("STT: _listenInternal start...");

    _speech.statusListener = (status) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      print("STT Status ($elapsed ms): $status");

      if (status == 'done' || status == 'notListening') {
        if (elapsed < 700 && _lastRecognized.isEmpty) {
          print("STT: Ignoring lightning stop.");
          return;
        }

        if (!completer.isCompleted) {
          Future.delayed(const Duration(milliseconds: 400), () {
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
      print("STT: Error in internal listen: $e");
      if (!completer.isCompleted) completer.complete(null);
    }

    return await completer.future.timeout(
      listenDuration + const Duration(seconds: 3),
      onTimeout: () {
        _speech.stop();
        return _lastRecognized.isNotEmpty ? _lastRecognized : null;
      },
    ).catchError((e) {
      print("STT Timeout/Error catch: $e");
      return _lastRecognized.isNotEmpty ? _lastRecognized : null;
    });
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
