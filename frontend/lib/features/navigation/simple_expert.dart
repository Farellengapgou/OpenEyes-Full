import 'dart:math' as Math;
import '../../features/detection/obstacle_analyzer.dart'; // Notre logique de détection
import 'sensor_data.dart'; // Les données capteurs

/// Classe représentant une action décidée par l'expert.
/// C'est le résultat de l'évaluation de la situation.
class ExpertAction {
  /// Le texte que l'application doit prononcer.
  final String instruction; 
  
  /// Si true, l'application doit signaler vocalement l'urgence (arrêt).
  final bool shouldStop;    
  
  /// Si true, cette instruction est prioritaire et coupe la parole actuelle.
  final bool isPriority;    

  ExpertAction({
    required this.instruction,
    this.shouldStop = false,
    this.isPriority = false,
  });

  /// Factory pour une action vide (ne rien faire).
  static ExpertAction none() => ExpertAction(instruction: "");
  
  /// Factory pour une action prioritaire.
  static ExpertAction priority(String instruction, {bool shouldStop = false}) => 
    ExpertAction(instruction: instruction, isPriority: true, shouldStop: shouldStop);
}

/// LE CERVEAU LOCAL (Système Expert Simplifié).
/// Cette classe contient les règles métier qui transforment les données brutes en instructions.
class SimpleExpert {
  // --- ÉTAT INTERNE ---
  DateTime? _lastInstructionTime;
  String? _lastInstruction;
  
  // Pour éviter les corrections immobiles
  double? _lastMovLat;
  double? _lastMovLon;

  // État pour l'évitement d'obstacles dynamique
  bool _isAvoidingObstacle = false;
  double? _initialObstacleHeading;
  String? _suggestedAvoidanceTurn; // "droite" ou "gauche"

  // --- MÉTHODE PRINCIPALE ---

  /// Évalue la situation globale et retourne une [ExpertAction].
  ExpertAction evaluate({
    required SensorData sensor,
    required double distToDestination, 
    required double bearingToDestination, 
  }) {
    // --- RÈGLE 1 : OBSTACLE FRONTAL (Priorité ABSOLUE) ---
    
    var obstacleStatus = ObstacleAnalyzer.analyze(
      front: sensor.frontDistance,
      waterRaw: sensor.waterRawData,
      waterDetected: sensor.water
    );
    
    if (obstacleStatus['status'] == SafetyStatus.stopObstacle) {
      if (!_isAvoidingObstacle) {
        _isAvoidingObstacle = true;
        _initialObstacleHeading = sensor.heading;
        _suggestedAvoidanceTurn = "droite"; // On suggère arbitrairement la droite au début
      }

      // Si on est déjà en train d'éviter, on vérifie si l'utilisateur a tourné
      if (_suggestedAvoidanceTurn != null) {
        double headingDiff = (sensor.heading - _initialObstacleHeading!);
        if (headingDiff > 180) headingDiff -= 360;
        if (headingDiff < -180) headingDiff += 360;

        // Si l'utilisateur a tourné de plus de 45° dans la direction suggérée mais l'obstacle persiste
        // (Ou si on veut juste répéter l'instruction d'évitement)
        if (_shouldSpeak("OBSTACLE_AVOID", 2)) {
          return ExpertAction.priority(
            "${obstacleStatus['message']} Tournez à $_suggestedAvoidanceTurn.",
            shouldStop: true,
          );
        }
        return ExpertAction.none();
      }

      if (_shouldSpeak("OBSTACLE_STOP", 2)) {
        return ExpertAction.priority(
          obstacleStatus['message'],
          shouldStop: true,
        );
      }
      return ExpertAction.none();
    }

    // Si plus d'obstacle, on reset l'état d'évitement
    if (_isAvoidingObstacle && obstacleStatus['status'] == SafetyStatus.safe) {
      _isAvoidingObstacle = false;
      _initialObstacleHeading = null;
      _suggestedAvoidanceTurn = null;
    }

    // --- RÈGLE 2 : EAU AU SOL (CAUTION) ---
    if (obstacleStatus['status'] == SafetyStatus.cautionWater) {
      if (_shouldSpeak("EAU", 5)) {
        return ExpertAction(
          instruction: obstacleStatus['message'], 
          isPriority: true
        );
      }
    }

    // --- RÈGLE 0 : VALIDATION FIX GPS ---
    if (sensor.lat == 0.0 && sensor.lon == 0.0) {
      return ExpertAction.none();
    }

    // --- RÈGLE 3 : ARRIVÉE À DESTINATION ---
    if (distToDestination < 3.0 && distToDestination >= 0) {
       if (_lastInstruction != "ARRIVED") {
         _lastInstruction = "ARRIVED";
         return ExpertAction(
           instruction: "Vous êtes arrivé à destination.",
           shouldStop: true,
           isPriority: true
         );
       }
       return ExpertAction.none();
    }

    // --- RÈGLE 4 : CORRECTION D'ORIENTATION (Heading) ---
    // Réduction de la sensibilité : On passe à 45° et on vérifie le mouvement.
    
    bool hasMoved = true;
    if (_lastMovLat != null && _lastMovLon != null) {
      double dist = _calculateDistance(_lastMovLat!, _lastMovLon!, sensor.lat, sensor.lon);
      // Augmenter la distance de mouvement requise pour stabiliser
      if (dist < 2.0) {
        hasMoved = false;
      }
    }

    if (hasMoved) {
      _lastMovLat = sensor.lat;
      _lastMovLon = sensor.lon;
    }

    double diff = (bearingToDestination - sensor.heading);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    // Seuil de correction augmenté à 40° pour plus de stabilité
    double turnThreshold = 40.0;
    
    if (diff.abs() > turnThreshold && hasMoved) {
      if (_shouldSpeak("TURN", 8)) { // Intervalle augmenté à 8s
        String direction = diff > 0 ? "droite" : "gauche";
        return ExpertAction(
          instruction: "Tournez légèrement à $direction.",
        );
      }
    } else if (hasMoved) {
      // RÈGLE 5 : CONFIRMATION DEVANT
      if (diff.abs() <= 20 && _shouldSpeak("GOOD", 20)) {
         return ExpertAction(instruction: "Continuez tout droit.");
      }
      
      // RÈGLE 6 : ÉCART DE CHEMIN (Simplifié)
      // Si on est à plus de 15m du prochain waypoint et que le bearing change trop par rapport à la position
      // Cette logique est normalement gérée par le bearing qui change, mais on peut ajouter un message explicite
      // si on détecte une dérive latérale importante (implémentation plus complexe requise pour être précis)
    }

    return ExpertAction.none();
  }

  // --- HELPER MÉTHODES ---

  /// Vérifie s'il faut parler ou se taire pour éviter le spam.
  /// [key] : Identifiant du type de message (ex: "TURN", "EAU").
  /// [intervalSeconds] : Temps minimum entre deux messages identiques.
  bool _shouldSpeak(String key, int intervalSeconds) {
    final now = DateTime.now();
    
    // Si c'est le même message qu'avant...
    if (_lastInstruction == key && _lastInstructionTime != null) {
      // ... et que le temps écoulé est inférieur à l'intervalle...
      if (now.difference(_lastInstructionTime!).inSeconds < intervalSeconds) {
        return false; // On ne parle pas.
      }
    }
    
    // Sinon, on met à jour l'historique et on autorise la parole.
    _lastInstruction = key;
    _lastInstructionTime = now;
    return true;
  }

  /// Calcul de distance simplifié (Haversine) pour petites distances.
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - 
        Math.cos((lat2 - lat1) * p) / 2 + 
        Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * 1000 * Math.asin(Math.sqrt(a));
  }
}
