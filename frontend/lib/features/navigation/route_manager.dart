import 'package:geolocator/geolocator.dart';

/// Un point de passage sur l'itinéraire.
class Waypoint {
  final double lat;
  final double lon;
  final String instruction; // Ex: "Tournez à droite" (si fourni par le backend)

  Waypoint({required this.lat, required this.lon, this.instruction = ""});
}

/// Gère l'itinéraire global (liste de points) et le suivi de progression.
class RouteManager {
  List<Waypoint> _route = [];
  int _currentIndex = 0;
  
  /// Rayon en mètres pour valider le passage d'un waypoint.
  static const double WAYPOINT_REACH_RADIUS = 15.0; // Augmenté de 10 à 15 pour le Cameroun
  
  /// Rayon pour l'arrivée finale (plus précis).
  static const double FINAL_DESTINATION_RADIUS = 5.0;

  bool get hasRoute => _route.isNotEmpty;
  bool get isFinished => _currentIndex >= _route.length;
  
  /// Le point actuel que l'utilisateur doit viser.
  Waypoint? get currentWaypoint {
    if (!hasRoute || isFinished) return null;
    return _route[_currentIndex];
  }

  /// Initialise une nouvelle route.
  void setRoute(List<Waypoint> newRoute) {
    _route = newRoute;
    _currentIndex = 0;
  }

  /// Met à jour la progression sur la route en fonction de la position actuelle.
  /// Retourne true si on vient de changer de waypoint (feedback possible).
  bool updateProgress(double currentLat, double currentLon) {
    if (!hasRoute || isFinished) return false;

    Waypoint target = _route[_currentIndex];
    
    // Calcul distance au point actuel
    double dist = Geolocator.distanceBetween(
      currentLat, currentLon, 
      target.lat, target.lon
    );
    
    // Est-ce le dernier point ?
    bool isLast = _currentIndex == _route.length - 1;
    double radius = isLast ? FINAL_DESTINATION_RADIUS : WAYPOINT_REACH_RADIUS;

    if (dist < radius) {
      if (!isLast) {
        _currentIndex++; // On passe au suivant
        print("✅ Waypoint $_currentIndex atteint! Suivant: ${_route[_currentIndex].instruction}");
        return true; // Changement de point
      } else {
        // Arrivée finale gérée par le contrôleur
      }
    }
    
    return false;
  }
  
  /// Retourne la distance restante vers le prochain point.
  double getDistanceToNext(double lat, double lon) {
    if (currentWaypoint == null) return 0.0;
    return Geolocator.distanceBetween(lat, lon, currentWaypoint!.lat, currentWaypoint!.lon);
  }

  /// Retourne le cap à suivre pour le prochain point.
  double getBearingToNext(double lat, double lon) {
    if (currentWaypoint == null) return 0.0;
    return Geolocator.bearingBetween(lat, lon, currentWaypoint!.lat, currentWaypoint!.lon);
  }
}
