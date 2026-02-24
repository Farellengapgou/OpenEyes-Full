import 'package:flutter_tts/flutter_tts.dart'; // Le moteur de synthèse vocale

/// Service responsable de la sortie audio (Text-to-Speech).
/// Il permet à l'application de "parler" à l'utilisateur aveugle.
class AudioGuidance {
  /// Instance du moteur TTS (Text-to-Speech).
  final FlutterTts flutterTts = FlutterTts();
  
  /// État interne pour savoir si le moteur est en train de parler.
  bool _isSpeaking = false;

  /// Constructeur : initialise la configuration TTS.
  AudioGuidance() {
    _initTts();
  }

  /// Configuration initiale du moteur vocal.
  Future<void> _initTts() async {
    // Définit la langue en Français.
    await flutterTts.setLanguage("fr-FR");
    await flutterTts.awaitSpeakCompletion(true);
    
    // Définit la vitesse de parole (0.5 est une vitesse moyenne, claire et compréhensible).
    await flutterTts.setSpeechRate(0.5); 
    
    // Volume maximal (1.0).
    await flutterTts.setVolume(1.0);
    
    // Callback appelé quand une phrase est terminée.
    flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  /// Méthode principale pour faire parler l'application.
  /// [text] : Le texte à prononcer.
  /// [force] : Si true, interrompt la phrase en cours (ex: pour un STOP urgent).
  Future<void> speak(String text, {bool force = false}) async {
    // Protection : on ne parle pas pour rien dire.
    if (text.isEmpty) return;

    // Si le moteur parle déjà...
    if (_isSpeaking && !force) {
      // ... et que ce n'est pas une urgence (force=false), 
      // on ignore cette nouvelle phrase pour ne pas saturer l'utilisateur.
      return;
    }

    // Si c'est urgent (force=true), on coupe la parole actuelle immédiatement.
    if (force) {
      await flutterTts.stop();
    }

    // On marque l'état comme "en train de parler".
    _isSpeaking = true;
    
    // On envoie le texte au moteur.
    await flutterTts.speak(text);
  }

  /// Arrête immédiatement toute vocalisation en cours.
  Future<void> stop() async {
    await flutterTts.stop();
    _isSpeaking = false;
  }
}
