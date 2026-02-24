import 'dart:async'; // Ajout StreamController
import 'package:geolocator/geolocator.dart'; 
import 'ble_service.dart'; 
import 'simple_expert.dart'; 
import 'audio_guidance.dart'; 
import 'sensor_data.dart'; 
import 'route_manager.dart'; // Gestion des waypoints
import '../../services/api_service.dart'; // Connexion Backend

/// CONTRÔLEUR PRINCIPAL (ORCHESTRATEUR)
/// FUSION : Backend Route + Données Canne
class NavigationController {
  // --- DÉPENDANCES ---
  final BleService _bleService; // Injection possible si besoin
  final AudioGuidance _audioGuidance;
  final SimpleExpert _expert;
  final RouteManager _routeManager;
  final ApiService _apiService; // ✅ Injection ApiService

  // --- ÉTAT ---
  bool isNavigating = false;
  bool _mockMode = true; // Pour la démo sans backend

  // Stream pour mettre à jour l'UI (texte affiché)
  final StreamController<String> _instructionController = StreamController<String>.broadcast();
  Stream<String> get instructionStream => _instructionController.stream;
  
  // Constructeur avec Injection de Dépendance
  NavigationController({
    BleService? bleService,
    AudioGuidance? audioGuidance,
    SimpleExpert? expert,
    RouteManager? routeManager,
    ApiService? apiService,
  }) : 
    _bleService = bleService ?? BleService(),
    _audioGuidance = audioGuidance ?? AudioGuidance(),
    _expert = expert ?? SimpleExpert(),
    _routeManager = routeManager ?? RouteManager(),
    _apiService = apiService ?? ApiService(baseUrl: ApiService.baseUrl); // Fallback temporaire pour compatibilité

  // --- MÉTHODES PUBLIQUES ---

  /// Démarre la session de navigation.
  /// [destinationText] : "Boulangerie", "Gare", etc.
  void startNavigation(String destinationText) async {
    isNavigating = true;
    await _audioGuidance.speak("Calcul de l'itinéraire vers $destinationText...");

    // 1. APPEL BACKEND (RÉEL)
    try {
      // Position actuelle pour l'itinéraire
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final response = await _apiService.getRoute(
        destination: destinationText,
        originLat: position.latitude,
        originLng: position.longitude
      );
      
      // Note: _processResponse throw déjà une exception si != 200, donc ici on a forcément un succès ou Json
      // Mais on vérifie quand même les champs métier

      // Parsing des Waypoints
      if (response['route'] != null && response['route']['steps'] != null) {
        List<dynamic> steps = response['route']['steps'];

        List<Waypoint> route = steps.map((step) {
          return Waypoint(
            lat: (step['start_location']['lat'] as num).toDouble(),
            lon: (step['start_location']['lng'] as num).toDouble(),
            instruction: step['instruction'] ?? "",
          );
        }).toList();

        // Ajouter le dernier point (destination)
        if (steps.isNotEmpty) {
          var last = steps.last['end_location'];
          route.add(Waypoint(
            lat: (last['lat'] as num).toDouble(),
            lon: (last['lng'] as num).toDouble(),
            instruction: "Vous êtes arrivé à destination",
          ));
        }

        _routeManager.setRoute(route);
        await _audioGuidance.speak(
            "Itinéraire chargé avec ${route.length} points.");
        } else {
          await _audioGuidance.speak(
              "Itinéraire reçu mais sans étapes exploitables.");
        }


    } catch (e) {
      print("Erreur Backend: $e");
      String errorMsg = "Erreur de connexion.";
      if (e is ApiException) {
         errorMsg = e.message;
      }
      await _audioGuidance.speak("$errorMsg Navigation impossible.");
      isNavigating = false;
      return;
    }
 

    await _audioGuidance.speak("Connexion à la canne en cours...");
    await Future.delayed(const Duration(milliseconds: 800));
 
    // 2. Connexion au Bluetooth (Cane)
    if (!_bleService.isConnected) {
         
        await _bleService.connect();
    }
    
    // 3. Inscription au flux de données
    _bleService.sensorStream.listen((sensorData) {
      if (!isNavigating) return;
      _processSensorData(sensorData);
    });
  }

  /// Arrête la navigation.
  void stopNavigation() {
    isNavigating = false;
    _bleService.dispose(); 
    _audioGuidance.stop();
  }

  // --- LOGIQUE METIER (CŒUR DU SYSTÈME) ---

  /// Boucle principale de navigation (1Hz - 10Hz selon capteurs).
  void _processSensorData(SensorData data) {
    if (_routeManager.isFinished) return; // Sécurité

    // 1. Mise à jour de la progression sur l'itinéraire
    // On utilise le GPS DE LA CANNE (data.lat/lon)
    bool waypointChanged = _routeManager.updateProgress(data.lat, data.lon);
    
    if (waypointChanged) {
       // Feedback sonore simple pour dire "point validé"
       // _audioGuidance.playDing(); // TODO: Ajouter son
       print("Point de passage validé.");
    }

    // 2. Récupération de la cible immédiate (Prochain Waypoint)
    double distance = _routeManager.getDistanceToNext(data.lat, data.lon);
    double bearing = _routeManager.getBearingToNext(data.lat, data.lon);

    // 3. Appel au Système Expert
    // Il gère la fusion : Obstacles (Ultrasons) + Cap (IMU) + Consigne GPS (Distance/Bearing)
    ExpertAction action = _expert.evaluate(
      sensor: data, 
      distToDestination: distance, 
      bearingToDestination: bearing
    );

    // 4. Feedback Vocal
    if (action.instruction.isNotEmpty) {
      // On prononce l'instruction.
      // force=true si c'est une urgence (ex: obstacle).
      _audioGuidance.speak(action.instruction, force: action.isPriority);
      _instructionController.add(action.instruction); // Mise à jour UI
    }
    
    // 5. Gestion de l'arrivée finale
    if (_routeManager.isFinished) {
      String msg = "Vous êtes arrivé à destination. Félicitations !";
      _audioGuidance.speak(msg);
      _instructionController.add(msg);
      stopNavigation();
    }
  }
}
