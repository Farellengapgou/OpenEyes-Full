import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'ble_service.dart';
import 'simple_expert.dart';
import 'audio_guidance.dart';
import 'sensor_data.dart';
import 'route_manager.dart';
import '../../services/maps_service.dart'; // ✅ Remplace ApiService

/// CONTRÔLEUR PRINCIPAL (ORCHESTRATEUR)
/// Navigation entièrement locale : MapsService → Nominatim + OSRM directs.
/// Plus aucune dépendance au backend Python.
class NavigationController {
  // --- DÉPENDANCES ---
  final BleService _bleService;
  final AudioGuidance _audioGuidance;
  final SimpleExpert _expert;
  final RouteManager _routeManager;
  final MapsService _mapsService; // ✅ Remplace ApiService

  // --- ÉTAT ---
  bool isNavigating = false;
  StreamSubscription? _bleSubscription;
  StreamSubscription? _gpsSubscription;
  Timer? _watchdog;

  // Position locale pour le fallback
  Position? _lastPhonePosition;

  // Stream pour mettre à jour l'UI avec instructions
  final StreamController<String> _instructionController =
      StreamController<String>.broadcast();
  Stream<String> get instructionStream => _instructionController.stream;

  // Stream pour le debug
  final StreamController<Map<String, dynamic>> _debugController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get debugStream => _debugController.stream;

  /// Constructeur avec injection de dépendances.
  NavigationController({
    BleService? bleService,
    AudioGuidance? audioGuidance,
    SimpleExpert? expert,
    RouteManager? routeManager,
    MapsService? mapsService,
  })  : _bleService = bleService ?? BleService(),
        _audioGuidance = audioGuidance ?? AudioGuidance(),
        _expert = expert ?? SimpleExpert(),
        _routeManager = routeManager ?? RouteManager(),
        _mapsService = mapsService ?? MapsService();

  // ─────────────────────────────────────────────
  // API PUBLIQUE
  // ─────────────────────────────────────────────

  /// Démarre la navigation vers [destinationText].
  Future<void> startNavigation(String destinationText, {String? rawTranscription}) async {
    isNavigating = true;
    await _audioGuidance.speak(
        "Calcul de l'itinéraire vers $destinationText.");

    // Démarrer l'écoute GPS du téléphone dès le début (utile pour le fallback même si la canne est là)
    _gpsSubscription?.cancel();
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2, 
      ),
    ).listen((Position position) {
      _lastPhonePosition = position;
      if (isNavigating && !_bleService.isConnected) {
        _processPhonePosition(position);
      }
    });

    try {
      // 1. Position actuelle
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _lastPhonePosition = position;

      // 2. Géocodage + Routing (Nominatim + OSRM) – directs depuis Flutter
      final route = await _mapsService.getRouteFromText(
        destination: destinationText,
        rawInput: rawTranscription ?? destinationText, // Utilise raw pour le fallback
        originLat: position.latitude,
        originLng: position.longitude,
      );

      if (route == null) {
        await _audioGuidance.speak(
            "Impossible de calculer l'itinéraire. Vérifiez votre connexion.");
        isNavigating = false;
        return;
      }

      // 3. Charger les waypoints
      if (route.steps.isNotEmpty) {
        final waypoints = route.steps.map((step) {
          return Waypoint(
            lat: step.startLocation.lat,
            lon: step.startLocation.lng,
            instruction: step.instruction,
          );
        }).toList();

        // Ajouter le dernier point (destination finale)
        final lastStep = route.steps.last;
        waypoints.add(Waypoint(
          lat: lastStep.endLocation.lat,
          lon: lastStep.endLocation.lng,
          instruction: "Vous êtes arrivé à destination",
        ));

        _routeManager.setRoute(waypoints);

        print("=== ITINÉRAIRE CHARGÉ === ");
        for (var idx = 0; idx < waypoints.length; idx++) {
           print("Etape ${idx + 1}: ${waypoints[idx].instruction} (Lat: ${waypoints[idx].lat}, Lon: ${waypoints[idx].lon})");
        }
        print("=========================");

        // Message vocal d'intro
        final intro = _mapsService.generateVoiceIntro(route);
        await _audioGuidance.speak(intro);
      } else {
        await _audioGuidance.speak("Itinéraire reçu sans étapes exploitables.");
      }
    } catch (e) {
      print("Erreur navigation: $e");
      await _audioGuidance.speak(
          "Erreur lors du calcul de l'itinéraire. Navigation impossible.");
      isNavigating = false;
      return;
    }

    // 4. Connexion Bluetooth (canne)
    bool bleConnected = false;
    try {
      if (!_bleService.isConnected) {
        await _audioGuidance.speak("Connexion à la canne...");
        // Timeout court pour ne pas bloquer si la canne est éteinte
        await _bleService.connect().timeout(const Duration(seconds: 8));
      }
      bleConnected = _bleService.isConnected;
    } catch (e) {
      print("BLE Connection failed: $e");
    }

    if (bleConnected) {
      await _audioGuidance.speak("Canne connectée.");
      
      // --- WATCHDOG : Fallback si la canne est muette ---
      bool dataReceived = false;
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 15), () async {
        if (!dataReceived && isNavigating) {
          await _audioGuidance.speak("La canne ne répond pas. Activation du mode simulation pour le test.");
          _bleService.startSimulation();
        }
      });

      _bleSubscription = _bleService.sensorStream.listen((sensorData) {
        if (!isNavigating) return;
        if (!dataReceived) {
          dataReceived = true;
          _watchdog?.cancel();
        }

        // --- FALLBACK GPS : Si la canne n'a pas de fix (0,0), on utilise le téléphone ---
        if (sensorData.lat == 0.0 && sensorData.lon == 0.0 && _lastPhonePosition != null) {
           final mergedData = SensorData(
             lat: _lastPhonePosition!.latitude,
             lon: _lastPhonePosition!.longitude,
             heading: sensorData.heading, // On garde le heading de la canne (IMU)
             frontDistance: sensorData.frontDistance,
             leftDistance: sensorData.leftDistance,
             rightDistance: sensorData.rightDistance,
             obstacleUp: sensorData.obstacleUp,
             water: sensorData.water,
             waterRawData: sensorData.waterRawData,
           );
           _processSensorData(mergedData, source: "PHONE + CANE IMU");
        } else {
          _processSensorData(sensorData, source: "CANE GPS");
        }
      });
    } else {
      await _audioGuidance.speak("Navigation par GPS téléphone uniquement.");
    }
  }

  /// Traite la position du téléphone (fallback sans canne).
  void _processPhonePosition(Position pos) {
    // Créer un SensorData minimaliste (juste GPS + Heading téléphone)
    final data = SensorData(
      lat: pos.latitude,
      lon: pos.longitude,
      heading: pos.heading,
      frontDistance: 99.9, // Pas d'obstacles
      leftDistance: 99.9,
      rightDistance: 99.9,
      obstacleUp: 99.9,
      water: false,
      waterRawData: 0.0,
    );
    _processSensorData(data, source: "PHONE ONLY");
  }

  /// Arrête la navigation.
  void stopNavigation() {
    isNavigating = false;
    _watchdog?.cancel();
    _bleSubscription?.cancel();
    _gpsSubscription?.cancel();
    _bleService.dispose();
    _audioGuidance.stop();
  }

  // ─────────────────────────────────────────────
  // TRAITEMENT CAPTEURS (cœur du système)
  // ─────────────────────────────────────────────

  /// Boucle principale de navigation (1Hz–10Hz selon données capteurs).
  void _processSensorData(SensorData data, {String source = "UNKNOWN"}) {
    if (_routeManager.isFinished) return;

    // 1. Mise à jour progression GPS
    final waypointChanged = _routeManager.updateProgress(data.lat, data.lon);

    if (waypointChanged) {
      print("Point de passage validé.");
    }

    // 2. Distances et cap vers prochain waypoint
    final distance = _routeManager.getDistanceToNext(data.lat, data.lon);
    final bearing = _routeManager.getBearingToNext(data.lat, data.lon);
    
    // Publish debug data
    _debugController.add({
      'lat': data.lat,
      'lon': data.lon,
      'heading': data.heading,
      'water': data.waterRawData,
      'front': data.frontDistance,
      'distToNext': distance,
      'bearingToNext': bearing,
      'source': source,
    });

    // 3. Système expert (fusion obstacles + IMU + GPS)
    final action = _expert.evaluate(
      sensor: data,
      distToDestination: distance,
      bearingToDestination: bearing,
    );

    // 4. Feedback vocal
    if (action.instruction.isNotEmpty) {
      _audioGuidance.speak(action.instruction, force: action.isPriority);
      _instructionController.add(action.instruction);
    }

    // 5. Détection arrivée
    if (_routeManager.isFinished) {
      const msg = "Vous êtes arrivé à destination. Félicitations !";
      _audioGuidance.speak(msg);
      _instructionController.add(msg);
      stopNavigation();
    }
  }
}
