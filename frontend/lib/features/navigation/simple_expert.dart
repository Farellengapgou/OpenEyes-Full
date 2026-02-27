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

  // État pour l'eau (cooldown)
  int _waterWarningCount = 0;
  double _peakWaterLevel = 0.0;
  DateTime _waterCooldownUntil = DateTime(2000);

  // État Client-side Yaw Fallback
  double _lastKnownGoodHeading = 0.0;

  // --- MÉTHODE PRINCIPALE ---

  /// Évalue la situation globale et retourne une [ExpertAction].
  ExpertAction evaluate({
    required SensorData sensor,
    required double distToDestination, 
    required double bearingToDestination, 
  }) {
    // --- FALLBACK YAW (Si le heading de la canne est nul ou bloqué) ---
    // Note: this is a rudimentary fallback assuming the phone/app keeps track of last good heading
    // To truly use pitch/roll to get yaw without a magnetometer is mathematically impossible (pitch/roll are relative to gravity, yaw is relative to magnetic north), 
    // but we can freeze the last good heading so the app doesn't spin wildly.
    double currentHeading = sensor.heading;
    if (currentHeading == 0.0 || currentHeading.isNaN) {
       currentHeading = _lastKnownGoodHeading;
    } else {
       _lastKnownGoodHeading = currentHeading;
    }


    // --- EVALUATION CAPTEURS ---
    var obstacleStatus = ObstacleAnalyzer.analyze(
      front: sensor.frontDistance,
      waterRaw: sensor.waterRawData,
      waterDetected: sensor.water
    );

    bool isWater = obstacleStatus['isWater'] == true;

    // --- COOLDOWN EAU ---
    if (DateTime.now().isBefore(_waterCooldownUntil)) {
      if (isWater) { // On ignore l'eau pendant le cooldown
        obstacleStatus = {
          'status': SafetyStatus.safe,
          'message': null,
          'isWater': false,
        };
      }
    } else {
      if (isWater) {
        if (sensor.waterRawData > _peakWaterLevel) {
          _peakWaterLevel = sensor.waterRawData;
        } else if (_peakWaterLevel > 2000 && sensor.waterRawData < 1500 && _waterWarningCount >= 1) {
          // S'il y a eu une grosse chute d'eau détectée après un pic = cooldown
          _waterCooldownUntil = DateTime.now().add(const Duration(seconds: 15));
          _waterWarningCount = 0;
          _peakWaterLevel = 0;
          obstacleStatus = {
            'status': SafetyStatus.safe,
            'message': null,
            'isWater': false,
          };
        }
      } else {
        _peakWaterLevel = 0;
      }
    }

    // --- RÈGLE 1 : OBSTACLE FRONTAL (Priorité ABSOLUE) ---
    if (obstacleStatus['status'] == SafetyStatus.stopObstacle) {
      if (isWater) {
        if (_shouldSpeak("EAU_CRITIQUE", 5)) {
          _waterWarningCount++;
          return ExpertAction.priority(
            obstacleStatus['message'],
            shouldStop: true,
          );
        }
        return ExpertAction.none();
      }

      // Cas d'un obstacle physique (pas l'eau)
      if (!_isAvoidingObstacle) {
        _isAvoidingObstacle = true;
        _initialObstacleHeading = currentHeading;
        _suggestedAvoidanceTurn = "droite"; 
      }

      if (_suggestedAvoidanceTurn != null) {
        double headingDiff = (currentHeading - _initialObstacleHeading!);
        if (headingDiff > 180) headingDiff -= 360;
        if (headingDiff < -180) headingDiff += 360;

        if (headingDiff.abs() > 40) {
          // Il a tourné, mais l'obstacle est TOUJOURS LÀ.
          if (_shouldSpeak("OBSTACLE_AVOID", 4)) {
            _suggestedAvoidanceTurn = _suggestedAvoidanceTurn == "droite" ? "gauche" : "droite";
            return ExpertAction.priority(
              "Pas libre, essayez de prendre à $_suggestedAvoidanceTurn.",
              shouldStop: true,
            );
          }
        } else {
          // Il n'a pas encore (suffisamment) tourné
          if (_shouldSpeak("OBSTACLE_AVOID_INIT", 4)) {
            return ExpertAction.priority(
              "${obstacleStatus['message']} Essayez de prendre à $_suggestedAvoidanceTurn.",
              shouldStop: true,
            );
          }
        }
        return ExpertAction.none();
      }
    }

    // Si plus d'obstacle physique, on reset l'état d'évitement
    if (_isAvoidingObstacle && !isWater && obstacleStatus['status'] == SafetyStatus.safe) {
      _isAvoidingObstacle = false;
      String dir = _suggestedAvoidanceTurn ?? "droite";
      _initialObstacleHeading = null;
      _suggestedAvoidanceTurn = null;
      return ExpertAction.priority("$dir libre, c'est okay. On continue.");
    }

    // --- RÈGLE 2 : EAU AU SOL (CAUTION) ---
    if (obstacleStatus['status'] == SafetyStatus.cautionWater) {
      if (_shouldSpeak("EAU_CAUTION", 5)) {
        _waterWarningCount++;
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
    bool hasMoved = true;
    if (_lastMovLat != null && _lastMovLon != null) {
      double dist = _calculateDistance(_lastMovLat!, _lastMovLon!, sensor.lat, sensor.lon);
      if (dist < 2.0) {
        hasMoved = false; // Ne s'est pas assez déplacé
      }
    }

    if (hasMoved) {
      _lastMovLat = sensor.lat;
      _lastMovLon = sensor.lon;
    }

    double diff = (bearingToDestination - currentHeading);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    // Seuil de correction à 40°
    double turnThreshold = 40.0;
    
    if (diff.abs() > turnThreshold && hasMoved) {
      // Ignorer si on est en train de contourner un obstacle
      if (!_isAvoidingObstacle && _shouldSpeak("TURN", 8)) {
        String direction = diff > 0 ? "droite" : "gauche";
        return ExpertAction(
          instruction: "Tournez légèrement à $direction.",
        );
      }
    } else if (hasMoved && !_isAvoidingObstacle) {
      // RÈGLE 5 : CONFIRMATION DEVANT (Intervalle allongé à 60s pour la continuité)
      if (diff.abs() <= 20 && _shouldSpeak("GOOD", 60)) {
         return ExpertAction(instruction: "Parfait, continuez tout droit.");
      }
    }

    return ExpertAction.none();
  }

  // --- HELPER MÉTHODES ---

  /// Vérifie s'il faut parler ou se taire pour éviter le spam.
  bool _shouldSpeak(String key, int intervalSeconds) {
    final now = DateTime.now();
    
    if (_lastInstruction == key && _lastInstructionTime != null) {
      if (now.difference(_lastInstructionTime!).inSeconds < intervalSeconds) {
        return false;
      }
    }
    
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
