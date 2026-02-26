/// Ce fichier définit le modèle de données reçu de la canne via Bluetooth.
/// Il est crucial pour transformer le JSON brut en objets Dart utilisables.

/// Classe représentant les données des capteurs de la canne.
class SensorData {
  /// Latitude GPS (ex: 3.8654).
  final double lat;

  /// Longitude GPS (ex: 11.5032).
  final double lon;

  /// Orientation magnétique en degrés (0 = Nord, 90 = Est, etc.).
  final double heading;

  /// Distance à l'obstacle frontal "Centre" en mètres.
  final double frontDistance;

  /// Distance à l'obstacle "Gauche" en mètres.
  final double leftDistance;

  /// Distance à l'obstacle "Droite" en mètres.
  final double rightDistance;

  /// Distance à l'obstacle en hauteur en mètres (ex: 1.6).
  final double obstacleUp;

  /// Valeur brute du capteur d'eau (0-4095).
  final double waterRawData;

  /// Indique si de l'eau a été détectée au sol (true = eau, false = sec).
  final bool water;

  /// Constructeur constant pour créer une instance immuable de SensorData.
  SensorData({
    required this.lat,
    required this.lon,
    required this.heading,
    required this.frontDistance,
    this.leftDistance = 99.9,  // Par défaut infini (pas d'obstacle)
    this.rightDistance = 99.9, // Par défaut infini
    required this.obstacleUp,
    required this.water,
    this.waterRawData = 0.0,
  });

  /// Factory constructor pour créer une instance depuis un Map JSON.
  /// C'est ici que la conversion JSON -> Objet opère.
  factory SensorData.fromJson(Map<String, dynamic> json) {
    return SensorData(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
      
      // Adaptation pour supporter simplement le JSON si pas de sectorisation faite en amont
      frontDistance: (json['obstacle_front'] as num?)?.toDouble() ?? 99.9,
      
      obstacleUp: (json['obstacle_up'] as num?)?.toDouble() ?? 99.9,
      water: json['water'] as bool? ?? false,
      waterRawData: (json['water_raw'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Méthode utilitaire pour afficher les données de manière lisible dans les logs/console.
  @override
  String toString() {
    return 'SensorData(L:$leftDistance C:$frontDistance R:$rightDistance, Up:$obstacleUp, WaterRaw:$waterRawData)';
  }
}
