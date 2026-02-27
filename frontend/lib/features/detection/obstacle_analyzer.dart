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
  static const double CRITICAL_DISTANCE_FRONT = 0.4; 

  /// Méthode principale d'analyse.
  static Map<String, dynamic> analyze({
    required double front,
    required double waterRaw,
    required bool waterDetected
  }) {
    
    // 1. VÉRIFICATION PRIORITAIRE : OBSTACLE FRONTAL
    if (front < CRITICAL_DISTANCE_FRONT && front > 0.0) {
      int distCm = (front * 100).toInt();
      return {
        'status': SafetyStatus.stopObstacle,
        'message': "Obstacle à environ $distCm centimètres.",
        'isWater': false,
      };
    } else if (front < CRITICAL_DISTANCE_FRONT) {
      return {
        'status': SafetyStatus.stopObstacle,
        'message': "Obstacle détecté.",
        'isWater': false,
      };
    }

    // 2. VÉRIFICATION SECONDAIRE : EAU AU SOL
    // - 0-1000: Négligeable.
    // - 1000-3000: Caution.
    // - > 3000: Critique (Arrêt).
    
    if (waterRaw > 3000) {
      return {
        'status': SafetyStatus.stopObstacle,
        'message': "Niveau d'eau critique.",
        'isWater': true,
      };
    } else if (waterRaw > 1000) {
      return {
        'status': SafetyStatus.cautionWater,
        'message': "Attention, eau au sol.",
        'isWater': true,
      };
    }

    return {
      'status': SafetyStatus.safe,
      'message': null,
      'isWater': false,
    };
  }
}
