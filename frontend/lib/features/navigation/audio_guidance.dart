import 'dart:collection';
import 'package:flutter_tts/flutter_tts.dart';

/// Service responsable de la sortie audio (Text-to-Speech).
/// Il permet à l'application de "parler" à l'utilisateur aveugle.
class AudioGuidance {
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;
  final Queue<String> _queue = Queue<String>();

  AudioGuidance() {
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("fr-FR");
    await flutterTts.awaitSpeakCompletion(true);
    await flutterTts.setSpeechRate(0.5); 
    await flutterTts.setVolume(1.0);
    
    flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _processQueue();
    });
  }

  Future<void> speak(String text, {bool force = false}) async {
    if (text.isEmpty) return;

    if (force) {
      _queue.clear();
      await flutterTts.stop();
      _isSpeaking = false;
      
      _isSpeaking = true;
      await flutterTts.speak(text);
      return;
    }

    if (_queue.isEmpty || _queue.last != text) {
      _queue.add(text);
    }
    
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isSpeaking || _queue.isEmpty) return;

    _isSpeaking = true;
    String nextText = _queue.removeFirst();
    await flutterTts.speak(nextText);
  }

  Future<void> stop() async {
    _queue.clear();
    await flutterTts.stop();
    _isSpeaking = false;
  }
}

