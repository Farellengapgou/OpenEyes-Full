import 'package:geolocator/geolocator.dart'; // Pour les calculs de distance si besoin
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
}

/// LE CERVEAU LOCAL (Système Expert Simplifié).
/// Cette classe contient les règles métier qui transforment les données brutes en instructions.
class SimpleExpert {
  // --- ÉTAT INTERNE ---
  // On garde en mémoire la dernière instruction et son heure pour éviter de répéter 
  // la même chose 10 fois par seconde (anti-spam vocal).
  
  DateTime? _lastInstructionTime;
  String? _lastInstruction;
  
  // --- MÉTHODE PRINCIPALE ---

  /// Évalue la situation globale et retourne une [ExpertAction].
  /// [sensor] : Les dernières données reçues de la canne.
  /// [distToDestination] : Distance restante vers le  point cible (calculée ailleurs).
  /// [bearingToDestination] : Cap théorique à suivre pour atteindre la cible (calculé ailleurs).
  ExpertAction evaluate({
    required SensorData sensor,
    required double distToDestination, 
    required double bearingToDestination, 
  }) {
    // --- RÈGLE 1 : OBSTACLE FRONTAL (Priorité ABSOLUE) ---
    // On utilise l'ObstacleAnalyzer pour vérifier les dangers physiques.
    
    var obstacleStatus = ObstacleAnalyzer.analyze(
      front: sensor.frontDistance,
      left: sensor.leftDistance,
      right: sensor.rightDistance,
      waterDetected: sensor.water
    );
    
    // Si l'analyseur dit STOP...
    if (obstacleStatus['status'] == SafetyStatus.stopObstacle) {
      // Pour les instructions d'évitement complexes, on veut éviter de couper
      // la fin de la phrase ("Contournez par la droite") si elle est longue.
      return ExpertAction(
        instruction: obstacleStatus['message'],
        shouldStop: true,
        isPriority: true, 
      );
    }

    // --- RÈGLE 2 : EAU AU SOL ---
    // Si l'analyseur détecte de l'eau...
    if (obstacleStatus['status'] == SafetyStatus.cautionWater) {
      // On vérifie si on a déjà parlé de l'eau récemment (anti-spam 5 secondes).
      if (_shouldSpeak("EAU", 5)) {
        return ExpertAction(
          instruction: obstacleStatus['message'], 
          isPriority: true
        );
      }
      // Sinon on ne dit rien pour l'instant.
    }

    // --- RÈGLE 3 : ARRIVÉE À DESTINATION ---
    // Si on est à moins de 3 mètres de la cible.
    if (distToDestination < 3.0 && distToDestination >= 0) {
       // Si on ne l'a pas déjà annoncé (état "ARRIVED").
       if (_lastInstruction != "ARRIVED") {
         _lastInstruction = "ARRIVED";
         return ExpertAction(
           instruction: "Vous êtes arrivé à destination.",
           shouldStop: true, // On suggère l'arrêt car arrivé.
           isPriority: true
         );
       }
       // Si déjà annoncé, on ne dit plus rien.
       return ExpertAction.none();
    }

    // --- RÈGLE 4 : CORRECTION D'ORIENTATION (Heading) ---
    // On compare où on regarde (sensor.heading) avec où on doit aller (bearingToDestination).
    
    // Calcul de la différence angulaire.
    double diff = (bearingToDestination - sensor.heading);
    
    // Normalisation de l'angle entre -180 et +180 degrés pour avoir le chemin le plus court.
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    
    // Si l'écart est significatif (> 15 degrés).
    if (diff.abs() > 15) {
      // On limite la fréquence des corrections de direction (toutes les 4 secondes).
      if (_shouldSpeak("TURN", 4)) {
        // Si diff positif -> on doit tourner à droite.
        // Si diff négatif -> on doit tourner à gauche.
        String direction = diff > 0 ? "droite" : "gauche";
        
        // Instruction humaine douce ("légèrement").
        return ExpertAction(
          instruction: "Corrigez légèrement à $direction.",
        );
      }
    } else {
      // --- RÈGLE 5 : CONFIRMATION DEVANT ---
      // Si on est dans la bonne direction (< 15° écart).
      // On rassure l'utilisateur de temps en temps (10 secondes).
      if (_shouldSpeak("GOOD", 10)) {
         return ExpertAction(instruction: "Continuez tout droit.");
      }
    }

    // Si aucune règle ne se déclenche, on ne fait rien.
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
}
