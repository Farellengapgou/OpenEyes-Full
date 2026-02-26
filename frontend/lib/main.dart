import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // ─────────────────────────────────────────────
  // SERVICES
  // ─────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  final SpeechService _speechService = SpeechService();
  final NlpService _nlpService = NlpService();
  final MapsService _mapsService = MapsService();
  late final NavigationController _navigationController;

  // ─────────────────────────────────────────────
  // ÉTAT
  // ─────────────────────────────────────────────
  bool _isNavigating = false;
  String? _destination;

  // ─────────────────────────────────────────────
  // BOUTON VOLUME (TRIPLE PRESSION)
  // ─────────────────────────────────────────────
  int _volumeClickCount = 0;
  Timer? _clickTimer;

  @override
  void initState() {
    super.initState();
    _navigationController = NavigationController();
    _initTts();
    _requestPermissions();
    _initVolumeListener();
    _speechService.initialize(); // préchauffage STT
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
  // TTS – SYNCHRONISÉ
  // ─────────────────────────────────────────────

  Future<void> _speak(
    String text, {
    Duration postDelay = const Duration(milliseconds: 300),
  }) async {
    final completer = Completer<void>();

    _tts.setCompletionHandler(() {
      if (!completer.isCompleted) completer.complete();
    });

    await _tts.speak(text);

    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );

    // 🔥 indispensable avant le STT
    await Future.delayed(postDelay);
  }

  // ─────────────────────────────────────────────
  // FLUX VOCAL PRINCIPAL
  // ─────────────────────────────────────────────

  Future<void> _startVoiceNavigation() async {
    try {
      await _speak(
        'Dites votre destination apres la vibration',
        postDelay: const Duration(milliseconds: 300),
      );

      String? rawText;
      int retryCount = 0;
      
      while (retryCount < 3) {
        rawText = await _speechService.listen(
          listenDuration: const Duration(seconds: 10),
          localeId: 'fr_FR',
        );

        if (rawText != null && rawText.isNotEmpty) break;
        
        retryCount++;
        if (retryCount < 3) {
          await _speak('Je n\'ai rien entendu. Dites votre destination après la vibration.');
        }
      }

      if (rawText == null || rawText.isEmpty) {
        await _speak('Désolé, je ne vous entends pas bien. Abandon de la recherche.');
        return;
      }

      final destination = _nlpService.extractDestination(rawText);
      if (destination == null || destination.isEmpty) {
        await _speak('Je n\'ai pas compris la destination.');
        return;
      }

      _destination = _nlpService.normalize(destination);

      // Validation rapide
      final geo = await _mapsService.geocodeDestination(_destination!);
      if (geo == null) {
        await _speak('Lieu introuvable. Réessayez.');
        _destination = null;
        return;
      }

      await _speak(
        _nlpService.confirmationText(_destination!),
      );

      await _confirmDestination(rawText: rawText);
    } catch (e) {
      print("Voice navigation error: $e");
      await _speak('Erreur système.');
    }
  }

  Future<void> _confirmDestination({
    int retryCount = 0,
    String? rawText,
  }) async {
    if (retryCount >= 3) {
      await _speak('Trop de tentatives.');
      _destination = null;
      return;
    }

    final result = await _speechService.listenConfirmation();

    switch (result) {
      case ConfirmationResult.yes:
        await _speak('Parfait. Lancement de la navigation.');
        await _startNavigation(rawTranscription: rawText);
        break;

      case ConfirmationResult.no:
        await _speak('Annulé. Nouvelle destination.');
        _destination = null;
        await _startVoiceNavigation();
        break;

      case ConfirmationResult.unclear:
        await _speak('Dites simplement oui ou non.');
        await _confirmDestination(
          retryCount: retryCount + 1,
          rawText: rawText,
        );
        break;
    }
  }

  // ─────────────────────────────────────────────
  // NAVIGATION
  // ─────────────────────────────────────────────

  Future<void> _startNavigation({String? rawTranscription}) async {
    if (_destination == null) return;

    setState(() => _isNavigating = true);

    await _navigationController.startNavigation(
      _destination!,
      rawTranscription: rawTranscription,
    );
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
  // UI – ÉCRAN MINIMALISTE
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleVolumeClick, // triple tap écran
        child: const SizedBox.expand(),
      ),
    );
  }
}