import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Modèles de données
class Location {
  final double lat;
  final double lng;
  const Location({required this.lat, required this.lng});
}

class RouteStep {
  final String instruction;
  final String distance;
  final String duration;
  final Location startLocation;
  final Location endLocation;

  const RouteStep({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.startLocation,
    required this.endLocation,
  });
}

class NavigationRoute {
  final String summary;
  final String totalDistance;
  final String totalDuration;
  final List<RouteStep> steps;
  final Location destinationCoords;
  final String formattedAddress;

  const NavigationRoute({
    required this.summary,
    required this.totalDistance,
    required this.totalDuration,
    required this.steps,
    required this.destinationCoords,
    required this.formattedAddress,
  });
}

/// Service de cartographie – appelle directement Nominatim + OSRM.
/// Port Dart de maps_service.py. Le backend Python n'est plus nécessaire.
class MapsService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org';
  static const String _osrmUrl = 'https://router.project-osrm.org';

  // Seuils de proximité (mètres)
  static const double stepCompletionThreshold = 30.0;
  static const double arrivalThreshold = 20.0;

  final http.Client _client;
  final Map<String, String> _headers;

  MapsService({http.Client? client})
      : _client = client ?? http.Client(),
        _headers = {
          'User-Agent': 'BlindNavigationApp/1.0 (student_project@univ.cm)',
          'Accept': 'application/json',
          'Accept-Language': 'fr',
        };

  // ─────────────────────────────────────────────
  // GÉOCODAGE (Nominatim)
  // ─────────────────────────────────────────────

  /// Géocode une destination textuelle. Ajoute Yaoundé + Cameroun si absent.
  /// Inclut une logique de retry pour pallier aux timeouts Nominatim.
  Future<Map<String, dynamic>?> geocodeDestination(
    String destination, {
    String cityContext = 'Yaoundé',
    int maxRetries = 3,
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      attempts++;
      try {
        var query = destination.trim();

        if (!query.toLowerCase().contains(cityContext.toLowerCase())) {
          query += ', $cityContext';
        }
        if (!query.toLowerCase().contains('cameroun')) {
          query += ', Cameroun';
        }

        final uri = Uri.parse('$_nominatimUrl/search').replace(
          queryParameters: {
            'q': query,
            'format': 'json',
            'limit': '1',
            'countrycodes': 'cm',
            'addressdetails': '1',
            'accept-language': 'fr',
          },
        );

        print('MapsService: Geocoding attempt $attempts for "$query"...');
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) {
          print('MapsService: Geocoding error ${response.statusCode}');
          if (attempts < maxRetries) continue;
          return null;
        }

        final List<dynamic> results = json.decode(response.body);
        if (results.isEmpty) {
          print('MapsService: No results for "$query"');
          return null;
        }

        final loc = results.first as Map<String, dynamic>;
        return {
          'lat': double.parse(loc['lat'].toString()),
          'lng': double.parse(loc['lon'].toString()),
          'formatted_address': loc['display_name'] ?? destination,
          'source': 'nominatim',
        };
      } catch (e) {
        print('MapsService: Attempt $attempts failed: $e');
        if (attempts >= maxRetries) break;
        // Petit délai avant le prochain essai
        await Future.delayed(Duration(milliseconds: 500 * attempts));
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // ROUTING (OSRM)
  // ─────────────────────────────────────────────

  /// Calcule un itinéraire piéton entre deux points via OSRM.
  Future<NavigationRoute?> getDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String formattedAddress,
  }) async {
    try {
      final coords = '$originLng,$originLat;$destLng,$destLat';
      final uri = Uri.parse('$_osrmUrl/route/v1/foot/$coords').replace(
        queryParameters: {
          'overview': 'full',
          'steps': 'true',
          'geometries': 'geojson',
          'alternatives': 'false',
        },
      );

      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return _createFallbackRoute(
          originLat, originLng, destLat, destLng, formattedAddress,
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['code'] != 'Ok' ||
          (data['routes'] as List?)?.isEmpty == true) {
        return _createFallbackRoute(
          originLat, originLng, destLat, destLng, formattedAddress,
        );
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final osrmSteps = leg['steps'] as List;

      final steps = <RouteStep>[];

      for (var i = 0; i < osrmSteps.length; i++) {
        final step = osrmSteps[i] as Map<String, dynamic>;
        final instruction = _translateInstruction(step);

        final startCoords =
            (step['maneuver'] as Map)['location'] as List;

        List endCoords;
        if (i < osrmSteps.length - 1) {
          endCoords =
              ((osrmSteps[i + 1] as Map)['maneuver'] as Map)['location'] as List;
        } else {
          endCoords = [destLng, destLat];
        }

        final dist = (step['distance'] as num).toDouble();
        // OSRM foot duration is often too fast or inaccurate. Estimate 1.4 m/s (5 km/h) walking speed.
        final durSeconds = dist / 1.4;

        steps.add(RouteStep(
          instruction: instruction,
          distance: '${dist.toStringAsFixed(0)} m',
          duration: '${(durSeconds / 60).toStringAsFixed(1)} min',
          startLocation: Location(
            lat: (startCoords[1] as num).toDouble(),
            lng: (startCoords[0] as num).toDouble(),
          ),
          endLocation: Location(
            lat: (endCoords[1] as num).toDouble(),
            lng: (endCoords[0] as num).toDouble(),
          ),
        ));
      }

      final totalDist = (route['distance'] as num).toDouble();
      final totalDurSeconds = totalDist / 1.4; // Calcul fiable de durée piéton

      return NavigationRoute(
        summary: (leg['summary'] as String?) ?? 'Itinéraire piéton',
        totalDistance: totalDist > 1000
            ? '${(totalDist / 1000).toStringAsFixed(2)} km'
            : '${totalDist.toStringAsFixed(0)} m',
        totalDuration: '${(totalDurSeconds / 60).toStringAsFixed(0)} min',
        steps: steps,
        destinationCoords: Location(lat: destLat, lng: destLng),
        formattedAddress: formattedAddress,
      );
    } catch (e) {
      print('Erreur OSRM: $e');
      return _createFallbackRoute(
        originLat, originLng, destLat, destLng, formattedAddress,
      );
    }
  }

  /// Calcule en une seule opération : géocode + route.
  /// Inclut un fallback sur la phrase complète si l'extraction NLP échoue.
  Future<NavigationRoute?> getRouteFromText({
    required String destination,
    required String rawInput, // Nouvelle paramètre pour le fallback
    required double originLat,
    required double originLng,
    String cityContext = 'Yaoundé',
  }) async {
    // 1. Essayer avec la destination extraite par le NLP
    var coords = await geocodeDestination(destination, cityContext: cityContext);

    // 2. Fallback : si échec, essayer avec la phrase brute complète
    if (coords == null && rawInput != destination) {
      print("MapsService: Geocoding fallback on raw input: '$rawInput'");
      coords = await geocodeDestination(rawInput, cityContext: cityContext);
    }

    if (coords == null) return null;

    return getDirections(
      originLat: originLat,
      originLng: originLng,
      destLat: coords['lat'] as double,
      destLng: coords['lng'] as double,
      formattedAddress: coords['formatted_address'] as String,
    );
  }

  // ─────────────────────────────────────────────
  // NAVIGATION TEMPS RÉEL (Haversine)
  // ─────────────────────────────────────────────

  /// Calcule la distance en mètres entre deux points (formule Haversine).
  double calculateDistance(
    double lat1, double lng1, double lat2, double lng2,
  ) {
    const R = 6371000.0;
    final phi1 = lat1 * pi / 180;
    final phi2 = lat2 * pi / 180;
    final dPhi = (lat2 - lat1) * pi / 180;
    final dLambda = (lng2 - lng1) * pi / 180;

    final a = sin(dPhi / 2) * sin(dPhi / 2) +
        cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  /// Vérifie si la destination est atteinte.
  bool hasArrived(double currentLat, double currentLng,
      double destLat, double destLng) {
    return calculateDistance(currentLat, currentLng, destLat, destLng) <
        arrivalThreshold;
  }

  /// Génère un message vocal d'introduction pour un itinéraire.
  String generateVoiceIntro(NavigationRoute route) {
    final first = route.steps.isNotEmpty ? route.steps.first.instruction : '';
    return 'Itinéraire trouvé. Distance totale : ${route.totalDistance}. '
        'Durée estimée : ${route.totalDuration}. '
        '${first.isNotEmpty ? "Première instruction : $first." : ""} '
        "Bonne route !";
  }

  // ─────────────────────────────────────────────
  // PRIVÉ
  // ─────────────────────────────────────────────

  NavigationRoute _createFallbackRoute(
    double originLat, double originLng,
    double destLat, double destLng,
    String formattedAddress,
  ) {
    final distance = calculateDistance(originLat, originLng, destLat, destLng);
    final distStr = distance < 1000
        ? '${distance.toStringAsFixed(0)} m'
        : '${(distance / 1000).toStringAsFixed(2)} km';
    final durStr = '${(distance / 80).toStringAsFixed(0)} min';

    return NavigationRoute(
      summary: 'Itinéraire direct',
      totalDistance: distStr,
      totalDuration: durStr,
      steps: [
        RouteStep(
          instruction: 'Marchez en ligne droite vers la destination',
          distance: distStr,
          duration: durStr,
          startLocation: Location(lat: originLat, lng: originLng),
          endLocation: Location(lat: destLat, lng: destLng),
        ),
      ],
      destinationCoords: Location(lat: destLat, lng: destLng),
      formattedAddress: formattedAddress,
    );
  }

  /// Traduit une manœuvre OSRM en français.
  String _translateInstruction(Map<String, dynamic> step) {
    final m = step['maneuver'] as Map<String, dynamic>;
    final type = m['type'] as String? ?? '';
    final modifier = m['modifier'] as String? ?? '';

    switch (type) {
      case 'depart':
        return 'Commencez à marcher';
      case 'arrive':
        return 'Vous êtes arrivé à destination';
      case 'turn':
        switch (modifier) {
          case 'left':       return 'Tournez à gauche';
          case 'right':      return 'Tournez à droite';
          case 'straight':   return 'Continuez tout droit';
          case 'sharp left': return 'Tournez fortement à gauche';
          case 'sharp right':return 'Tournez fortement à droite';
          case 'slight left':return 'Tournez légèrement à gauche';
          case 'slight right':return 'Tournez légèrement à droite';
        }
        return 'Tournez';
      case 'roundabout':
        return 'Prenez le rond-point';
      case 'continue':
        return 'Continuez sur cette voie';
      default:
        return 'Continuez à marcher';
    }
  }

  void dispose() => _client.close();
}
