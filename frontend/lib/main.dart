import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/speech_service.dart';
import 'services/nlp_service.dart';
import 'features/navigation/navigation_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: NavigationScreen(),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  // ── Services locaux (plus de backend) ──────────────────────────────
  final FlutterTts _tts = FlutterTts();
  final SpeechService _speechService = SpeechService();
  final NlpService _nlpService = NlpService();
  late final NavigationController _navigationController;

  // ── État ──────────────────────────────────────────────────────────
  bool _isNavigating = false;
  String? _destination;

  // ── Écoute du bouton volume (triple pression) ─────────────────────
  int _volumeClickCount = 0;
  Timer? _clickTimer;

  @override
  void initState() {
    super.initState();
    _navigationController = NavigationController();
    _initTts();
    _requestPermissions();
    _initVolumeListener();
    // Pré-initialiser le STT pour éviter le délai à la première utilisation
    _speechService.initialize();
  }

  @override
  void dispose() {
    _clickTimer?.cancel();
    _speechService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // INITIALISATION
  // ─────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.location.request();
  }

  void _initVolumeListener() {
    // Écoute les pressions sur les boutons volume (haut ET bas) via EventChannel Android
    const EventChannel volumeChannel = EventChannel('com.openeyes/volume');
    volumeChannel.receiveBroadcastStream().listen((event) {
      if (event == 'volume_press') {
        _handleVolumeClick();
      }
    });
  }

  // ─────────────────────────────────────────────
  // GESTION BOUTON VOLUME
  // ─────────────────────────────────────────────

  void _handleVolumeClick() {
    _volumeClickCount++;
    _clickTimer?.cancel();
    _clickTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_volumeClickCount == 3 && !_isNavigating) {
        await _startVoiceNavigation();
      } else if (_volumeClickCount >= 4 && _isNavigating) {
        _stopNavigation();
      }
      _volumeClickCount = 0;
    });
  }

  // ─────────────────────────────────────────────
  // FLUX VOCAL PRINCIPAL – entièrement local
  // ─────────────────────────────────────────────

  /// Parle et attend VRAIMENT la fin de la parole avant de retourner.
  /// Utilise setCompletionHandler + Completer — plus fiable que awaitSpeakCompletion.
  Future<void> _speak(String text, {Duration postDelay = const Duration(milliseconds: 1000)}) async {
    print("TTS: Speaking '$text'...");
    final completer = Completer<void>();
    _tts.setCompletionHandler(() {
      print("TTS: Completion handler triggered for '$text'");
      if (!completer.isCompleted) completer.complete();
    });
    // Fallback : si le handler ne se déclenche jamais (bug TTS), on timeout après 15s
    await _tts.speak(text);
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
    // Pause pour laisser le son du haut-parleur se dissiper avant d'ouvrir le micro
    if (postDelay > Duration.zero) {
      await Future.delayed(postDelay);
    }
  }

  /// Étape 1 : écoute la destination depuis le STT natif.
  Future<void> _startVoiceNavigation() async {
    try {
      // Latence réduite entre l'instruction et le Bip
      await _speak('Dites votre destination après le signal', postDelay: const Duration(milliseconds: 100));
      
      // Signal sonore vocal pour qu'il sache QUAND parler
      await _speak('Bip', postDelay: const Duration(milliseconds: 800));

      print("DEBUG: Vocal prompt finished, opening STT...");
      // Le _speak() ci-dessus garantit déjà que le TTS est terminé + 1s de silence

      // Écoute STT locale (moteur natif du téléphone)
      final rawText = await _speechService.listen(
        listenDuration: const Duration(seconds: 8),
        localeId: 'fr_FR',
      );
      print("DEBUG: STT result received: '$rawText'");

      if (rawText == null || rawText.isEmpty) {
        await _speak('Je n\'ai rien entendu. Réessayez.');
        return;
      }

      // Parsing NLP local (regex Dart, port du backend nlp_parser.py)
      final destination = _nlpService.extractDestination(rawText);

      if (destination == null || destination.isEmpty) {
        final suggestions = _nlpService.getSuggestions(rawText);
        await _speak(
          'Destination non comprise. Essayez par exemple : $suggestions',
        );
        return;
      }

      _destination = _nlpService.normalize(destination);

      // Confirmation vocale
      final confirmText = _nlpService.confirmationText(_destination!);
      await _speak(confirmText);

      // Étape 2 : confirmation Oui/Non
      await _confirmDestination();
    } catch (e) {
      await _speak('Erreur système. Réessayez.');
    }
  }

  /// Étape 2 : écoute la confirmation Oui/Non.
  Future<void> _confirmDestination({int retryCount = 0}) async {
    if (retryCount >= 3) {
      await _speak('Trop de tentatives. Réessayez depuis le début.');
      _destination = null;
      return;
    }

    final result = await _speechService.listenConfirmation();

    switch (result) {
      case ConfirmationResult.yes:
        await _speak('Parfait. Lancement de la navigation.');
        await _startNavigation();
        break;

      case ConfirmationResult.no:
        await _speak('Annulé. Donnez une nouvelle destination.');
        _destination = null;
        await _startVoiceNavigation();
        break;

      case ConfirmationResult.unclear:
        await _speak('Je n\'ai pas compris. Dites simplement oui ou non.');
        await _confirmDestination(retryCount: retryCount + 1);
        break;
    }
  }

  /// Étape 3 : démarre la navigation (géocodage Nominatim + routing OSRM).
  Future<void> _startNavigation() async {
    if (_destination == null) return;
    setState(() => _isNavigating = true);
    // NavigationController appelle MapsService → Nominatim + OSRM directement
    await _navigationController.startNavigation(_destination!);
  }

  void _stopNavigation() {
    _navigationController.stopNavigation();
    setState(() {
      _isNavigating = false;
      _destination = null;
    });
    _speak('Navigation arrêtée.');
  }

  // ─────────────────────────────────────────────
  // UI – écran minimaliste (app pour aveugles)
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Triple tap sur l'écran comme alternative au bouton volume
        onTap: _handleVolumeClick,
        child: const SizedBox.expand(),
      ),
    );
  }
}