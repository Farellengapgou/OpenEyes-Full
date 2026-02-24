import 'dart:async';
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
    // Écoute les événements volume via le canal de plateforme ou VolumeController
    // Triple pression → démarrer navigation
    // Quadruple pression → stopper navigation
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

  Future<void> _speak(String text) async {
    await _tts.speak(text);
    await Future.delayed(Duration(milliseconds: (text.length * 50) + 800));
  }

  /// Étape 1 : écoute la destination depuis le STT natif.
  Future<void> _startVoiceNavigation() async {
    try {
      await _speak('Dites votre destination après le signal');

      // Écoute STT locale (moteur natif du téléphone)
      final rawText = await _speechService.listen(
        listenDuration: const Duration(seconds: 6),
        localeId: 'fr_FR',
      );

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