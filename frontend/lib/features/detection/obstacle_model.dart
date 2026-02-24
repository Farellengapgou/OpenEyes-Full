/// Ce fichier définit un modèle pour stocker les seuils et l'état des obstacles.
/// Il sert de structure intermédiaire pour le système de détection.

class ObstacleModel {
  /// Distance limite pour l'obstacle frontal en mètres.
  /// En dessous de cette valeur, on considère qu'il y a danger immédiat.
  final double limitFront; 

  /// Distance limite pour l'obstacle en hauteur (tête) en mètres.
  final double limitUp;    

  /// Indique si de l'eau est détectée actuellement.
  final bool waterDetected;

  /// Constructeur standard.
  ObstacleModel({
    required this.limitFront,
    required this.limitUp,
    required this.waterDetected,
  });

  /// Factory constructor pour créer un modèle "vide" ou "sûr" par défaut.
  /// Utile pour l'initialisation avant la première réception de données.
  factory ObstacleModel.empty() {
    return ObstacleModel(
      // On initialise avec une grande distance (99.9m) signifiant "pas d'obstacle".
      limitFront: 99.9, 
      
      // Idem pour la hauteur.
      limitUp: 99.9,
      
      // Pas d'eau par défaut.
      waterDetected: false,
    );
  }

  /// Représentation textuelle pour le débogage.
  @override
  String toString() => 'ObstacleModel(front: $limitFront, up: $limitUp, water: $waterDetected)';
}
