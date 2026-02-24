import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

class ApiService {
  final String baseUrl;
  final http.Client _client;
  final Duration timeout;

  ApiService({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// Helper pour gérer les réponses
  dynamic _processResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body);
    } else {
      throw ApiException('Erreur serveur', response.statusCode);
    }
  }

  /// Transcrit un fichier audio en texte et extrait la destination
  Future<Map<String, dynamic>> transcribeAudio(String audioPath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/speech/transcribe'),
      );
      
      // Ajouter le fichier audio
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio', 
          audioPath,
          contentType: MediaType('audio', 'wav'),
        ),
      );
      
      var streamedResponse = await _client.send(request).timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Pas de connexion internet');
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (Timeout)');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Erreur inattendue: $e');
    }
  }
  
  /// Confirme si l'utilisateur dit "Oui" ou "Non"
  Future<Map<String, dynamic>> confirmDestination(String audioPath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/speech/confirm'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio', 
          audioPath,
          contentType: MediaType('audio', 'wav'),
        ),
      );
      
      var streamedResponse = await _client.send(request).timeout(timeout);
      var response = await http.Response.fromStream(streamedResponse);
      
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Pas de connexion internet');
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (Timeout)');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Erreur inattendue: $e');
    }
  }
  
  /// Obtient l'itinéraire depuis une destination textuelle
  Future<Map<String, dynamic>> getRoute({
    required String destination,
    required double originLat,
    required double originLng,
  }) async {
    try {
      var response = await _client.post(
        Uri.parse('$baseUrl/navigation/get-route'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'destination': destination,
          'origin_lat': originLat,
          'origin_lng': originLng,
        }),
      ).timeout(timeout);
      
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Pas de connexion internet');
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (Timeout)');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Erreur inattendue: $e');
    }
  }
  
  /// Met à jour la position GPS en temps réel
  Future<Map<String, dynamic>> updatePosition({
    required double currentLat,
    required double currentLng,
    required String destination,
  }) async {
    try {
      var response = await _client.post(
        Uri.parse('$baseUrl/navigation/update-position'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'current_lat': currentLat,
          'current_lng': currentLng,
          'destination': destination,
        }),
      ).timeout(timeout);
      
      return _processResponse(response);
    } on SocketException {
      throw ApiException('Pas de connexion internet');
    } on TimeoutException {
      throw ApiException('Le serveur ne répond pas (Timeout)');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Erreur inattendue: $e');
    }
  }

  void dispose() {
    _client.close();
  }
}