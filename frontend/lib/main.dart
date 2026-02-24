import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:audioplayers/audioplayers.dart';

import 'services/api_service.dart';
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
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _beepPlayer = AudioPlayer();

  late final ApiService _apiService;
  late final NavigationController _navigationController;

  bool _isRecording = false;
  bool _isNavigating = false;
  String? _destination;

  int _volumeClickCount = 0;
  Timer? _clickTimer;

  @override
  void initState() {
    super.initState();

    const baseUrl = 'http://10.2.6.181:8000';
    _apiService = ApiService(baseUrl: baseUrl);
    _navigationController = NavigationController(apiService: _apiService);

    _initTts();
    _requestPermissions();
    _initVolumeListener();
  }

  @override
  void dispose() {
    _clickTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _initVolumeListener() {
    VolumeController().listener((volume) {
      _handleVolumeClick();
    });
  }

  void _handleVolumeClick() {
    _volumeClickCount++;

    _clickTimer?.cancel();
    _clickTimer = Timer(const Duration(milliseconds: 800), () async {
      if (_volumeClickCount == 3 && !_isNavigating) {
        await _startVoiceNavigation();
      } else if (_volumeClickCount == 4 && _isNavigating) {
        _stopNavigation();
      }
      _volumeClickCount = 0;
    });
  }

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

  Future<void> _speak(String text) async {
    await _tts.speak(text);
    await Future.delayed(Duration(milliseconds: (text.length * 50) + 800));
  }

  Future<void> _playBeep() async {
    await _beepPlayer.play(AssetSource('beep.mp3'));
  }

  Future<String?> _recordAudio() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        _isRecording = true;

        await _playBeep(); // 🔔 début enregistrement

        final Directory appDir =
            await getApplicationDocumentsDirectory();
        final String filePath =
            '${appDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: filePath,
        );

        await Future.delayed(const Duration(seconds: 5));
        await _audioRecorder.stop();

        await _playBeep(); // 🔔 fin enregistrement

        _isRecording = false;
        return filePath;
      }
    } catch (e) {
      await _speak('Erreur lors de l\'enregistrement');
    }
    return null;
  }

  Future<void> _startVoiceNavigation() async {
    try {
      await _speak('Dites votre destination après le bip');
      final audioPath = await _recordAudio();
      if (audioPath == null) return;

      await _speak('Je traite votre demande');

      final response = await _apiService.transcribeAudio(audioPath);

      if (response['success'] != true) {
        await _speak('Erreur de transcription');
        return;
      }

      final destination = response['destination'];
      if (destination == null || destination.isEmpty) {
        await _speak('Destination non comprise');
        return;
      }

      _destination = destination;
      await _speak(response['confirmation_text']);
      await _confirmDestination();
    } catch (e) {
      await _speak('Erreur système');
    }
  }

  Future<void> _confirmDestination() async {
    await _speak('Dites oui pour confirmer ou non pour annuler');
    final audioPath = await _recordAudio();
    if (audioPath == null) return;

    final response = await _apiService.confirmDestination(audioPath);

    if (response['needs_retry'] == true) {
      await _speak('Je n\'ai pas compris. Répétez.');
      await _confirmDestination();
    } else if (response['confirmed'] == true) {
      await _speak('Navigation démarrée');
      await _startNavigation();
    } else {
      await _speak('Annulé. Donnez une nouvelle destination');
      _destination = null;
      await _startVoiceNavigation();
    }
  }

  Future<void> _startNavigation() async {
    if (_destination == null) return;

    _isNavigating = true;
    _navigationController.startNavigation(_destination!);
  }

  void _stopNavigation() {
    _navigationController.stopNavigation();
    _isNavigating = false;
    _destination = null;
    _speak('Navigation arrêtée');
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(),
    );
  }
}