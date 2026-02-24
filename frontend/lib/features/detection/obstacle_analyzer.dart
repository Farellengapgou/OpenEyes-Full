import 'obstacle_model.dart';
/// Ce fichier contient la logique pure d'analyse des obstacles.
/// Il ne dépend pas de Flutter, ce qui le rend facile à tester unitairement.

/// Enumération définissant les différents niveaux de sécurité/danger.
enum SafetyStatus {
  /// Aucune menace détectée, la voie est libre.
  safe,
  
  /// MENACE CRITIQUE : Obstacle immédiat devant. Arrêt nécessaire.
  stopObstacle,
  
  /// AVERTISSEMENT : Eau au sol. Prudence requise.
  cautionWater,  
}

/// Classe statique utilitaire pour analyser les données de capteurs.
class ObstacleAnalyzer {
  // --- CONSTANTES ---
  
  /// Seuil critique en mètres pour l'obstacle frontal.
  /// Si un objet est à moins de 1.0m, on déclenche l'arrêt.
  static const double CRITICAL_DISTANCE_FRONT = 1.0; 

  /// Méthode principale d'analyse.
  static Map<String, dynamic> analyze({
    required double front,
    required double left,
    required double right,
    required bool waterDetected
  }) {
    
    // 1. VÉRIFICATION PRIORITAIRE : OBSTACLE FRONTAL
    if (front < CRITICAL_DISTANCE_FRONT) {
      String advice = "Arrêtez-vous.";
      
      // Logique d'évitement
      // On considère une voie "libre" si > 1.0m
      bool leftFree = left > 1.0;
      bool rightFree = right > 1.0;
      
      if (leftFree && rightFree) {
        advice = "Obstacle devant. Contournez par la gauche ou la droite.";
      } else if (leftFree) {
        advice = "Obstacle devant. Contournez par la gauche.";
      } else if (rightFree) {
        advice = "Obstacle devant. Contournez par la droite.";
      } else {
        advice = "Zone bloquée. Reculez.";
      }

      return {
        'status': SafetyStatus.stopObstacle,
        'message': advice,
      };
    }

    // 2. VÉRIFICATION SECONDAIRE : EAU AU SOL
    if (waterDetected) {
      return {
        'status': SafetyStatus.cautionWater,
        'message': "Attention, eau au sol. Reculez d'un pas.",
      };
    }

    return {
      'status': SafetyStatus.safe,
      'message': null,
    };
  }
}
