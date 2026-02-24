import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/speech_service.dart';
import 'services/nlp_service.dart';
import 'services/maps_service.dart';
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
  final MapsService _mapsService = MapsService();
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
      await _speak('Dites votre destination maintenant', postDelay: const Duration(milliseconds: 1000));

      print("DEBUG: Preparing STT (ZTE 2s delay)...");
      // ⏳ Délai crucial validé par l'utilisateur pour le ZTE
      await Future.delayed(const Duration(seconds: 2));

      print("DEBUG: Opening STT...");
      final rawText = await _speechService.listen(
        listenDuration: const Duration(seconds: 12),
        localeId: 'fr_FR',
      );
      print("DEBUG: STT result: '$rawText'");

      if (rawText == null || rawText.isEmpty) {
        await _speak('Je n\'ai rien entendu. Réessayez.');
        await _startVoiceNavigation(); // RECURSIVE
        return;
      }

      // Extraction NLP
      final destination = _nlpService.extractDestination(rawText);
      if (destination == null || destination.isEmpty) {
        await _speak('Je n\'ai pas compris la destination. Réessayez.');
        await _startVoiceNavigation(); // RECURSIVE
        return;
      }

      _destination = _nlpService.normalize(destination);

      // 🔍 VALIDATION IMMEDIATE (Évite le blocage Picasso)
      print("DEBUG: Pre-validating destination: '$_destination'");
      try {
        final geocode = await _mapsService.geocodeDestination(_destination!);
        
        if (geocode == null) {
          await _speak('Je n\'ai pas trouvé ce lieu au Cameroun. Pouvez-vous répéter ?');
          _destination = null;
          await _startVoiceNavigation(); // RECURSION : On recommence
          return;
        }
      } catch (e) {
        if (e.toString().contains('SocketException') || e.toString().contains('host lookup')) {
          await _speak('Erreur de connexion internet. Vérifiez votre réseau puis réessayez.');
        } else {
          await _speak('Erreur de recherche. Réessayez.');
        }
        return;
      }

      // Si trouvé, on demande confirmation
      final confirmText = _nlpService.confirmationText(_destination!);
      await _speak(confirmText);

      // Étape 2 : confirmation Oui/Non
      await _confirmDestination(rawText: rawText);
    } catch (e) {
      print("ERROR in _startVoiceNavigation: $e");
      await _speak('Erreur système.');
    }
  }

  /// Étape 2 : écoute la confirmation Oui/Non.
  Future<void> _confirmDestination({int retryCount = 0, String? rawText}) async {
    if (retryCount >= 3) {
      await _speak('Trop de tentatives. Réessayez plus tard.');
      _destination = null;
      return;
    }

    // Pause de sécurité avant d'écouter la confirmation
    await Future.delayed(const Duration(milliseconds: 1500));

    final result = await _speechService.listenConfirmation();

    switch (result) {
      case ConfirmationResult.yes:
        await _speak('Parfait. Lancement de la navigation.');
        await _startNavigation(rawTranscription: rawText);
        break;

      case ConfirmationResult.no:
        await _speak('Annulé. Nouvelle destination ?');
        _destination = null;
        await _startVoiceNavigation();
        break;

      case ConfirmationResult.unclear:
        await _speak('Je n\'ai pas compris. Dites simplement oui ou non.');
        await _confirmDestination(retryCount: retryCount + 1, rawText: rawText);
        break;
    }
  }

  /// Étape 3 : démarre la navigation (géocodage Nominatim + routing OSRM).
  Future<void> _startNavigation({String? rawTranscription}) async {
    if (_destination == null) return;
    setState(() => _isNavigating = true);
    await _navigationController.startNavigation(_destination!, rawTranscription: rawTranscription);
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