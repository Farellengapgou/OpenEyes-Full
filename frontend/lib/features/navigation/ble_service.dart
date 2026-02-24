import 'dart:convert'; // Nécessaire pour décoder le JSON (utf8, jsonDecode)
import 'dart:async';   // Nécessaire pour les Streams et Futures
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // Librairie BLE officielle (plus updated que flutter_blue)
import 'sensor_data.dart'; // Notre modèle de données

/// Service gérant toute la communication Bluetooth Low Energy (BLE).
/// Son rôle est de trouver la canne, s'y connecter et transformer les octets reçus en objets [SensorData].
class BleService {
  // --- CONSTANTES ---

  /// Nom exact du périphérique BLE broadcasté par l'ESP32.
  /// Le scan filtrera les appareils pour ne trouver que celui-ci.
  static const String TARGET_DEVICE_NAME = "OPEN EYES";
  
  /// UUID du service BLE personnalisé pour OPEN-EYES.
  /// ⚠️ IMPORTANT : Ce UUID doit être EXACTEMENT le même dans le firmware ESP32.
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  
  /// UUIDs des 4 caractéristiques (une par type de capteur).
  /// Cette architecture modulaire permet de recevoir les données indépendamment.
  static const String GPS_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String WATER_SENSOR_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
  static const String OBSTACLE_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26aa";
  static const String IMU_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26ab";
  
  // --- PROPRIÉTÉS ---

  /// L'appareil Bluetooth connecté (l'ESP32). Null si pas connecté.
  BluetoothDevice? _connectedDevice;
  
  /// Contrôleur de flux (StreamController) pour diffuser les données des capteurs à toute l'app.
  /// .broadcast() permet à plusieurs parties de l'app d'écouter les données en même temps si besoin.
  final StreamController<SensorData> _sensorDataController = StreamController<SensorData>.broadcast();

  /// Getter public pour accéder au flux de données (en lecture seule).
  Stream<SensorData> get sensorStream => _sensorDataController.stream;
  
  /// Helper pour savoir si on est actuellement connecté.
  bool get isConnected => _connectedDevice != null;
  
  // --- ÉTAT INTERNE POUR FUSION DES DONNÉES ---
  // Comme les 4 caractéristiques envoient leurs données indépendamment,
  // on les accumule ici avant de créer un SensorData complet.
  
  double _latestLat = 0.0;
  double _latestLon = 0.0;
  double _latestHeading = 0.0;
  
  // Distances par secteur (pour l'évitement)
  double _latestDistLeft = 99.9;
  double _latestDistCenter = 99.9;
  double _latestDistRight = 99.9;
  
  double _latestObstacleUp = 99.9;
  bool _latestWater = false;

  // --- MÉTHODES ---

  /// Lance le scan et tente de se connecter automatiquement au device cible.
  Future<void> connect() async {

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {

        final name = r.advertisementData.localName;
        if (name.isEmpty) continue;

        print("🔍 Trouvé : $name");

        if (name == TARGET_DEVICE_NAME) {
          print("✅ OPEN-EYES détecté !");
          await FlutterBluePlus.stopScan();
          await _connectToDevice(r.device);
          return;
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );
}


  /// Gère la connexion technique et la découverte des services UART/Custom.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      // 1. Connexion physique au device.
      await device.connect();
      _connectedDevice = device;
      
      // 2. Découverte des services (GATT) offerts par l'ESP32.
      // C'est nécessaire pour trouver la caractéristique d'envoi de données.
      List<BluetoothService> services = await device.discoverServices();
      
      // 3. Recherche du SERVICE spécifique par UUID.
      // On cherche notre service OPEN-EYES personnalisé.
      BluetoothService? targetService;
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          targetService = service;
          break;
        }
      }
      
      // Si le service n'est pas trouvé, on log une erreur et on arrête.
      if (targetService == null) {
        print("❌ ERREUR: Service UUID $SERVICE_UUID non trouvé sur l'ESP32.");
        print("Vérifiez que le firmware ESP32 utilise le même UUID.");
        return;
      }
      
      // 4. Souscription aux 4 caractéristiques.
      // On utilise une méthode helper pour chaque type de capteur.
      await _subscribeToCharacteristic(targetService, GPS_CHARACTERISTIC_UUID, _onGpsData);
      await _subscribeToCharacteristic(targetService, WATER_SENSOR_CHARACTERISTIC_UUID, _onWaterData);
      await _subscribeToCharacteristic(targetService, OBSTACLE_CHARACTERISTIC_UUID, _onObstacleData);
      await _subscribeToCharacteristic(targetService, IMU_CHARACTERISTIC_UUID, _onImuData);
      
      print("✅ Connecté au service OPEN-EYES. Réception des données...");
      
      
    } catch (e) {
      // Gestion d'erreur basique (logs).
      print("Erreur de connexion BLE: $e");
    }
  }

  
  /// Helper pour s'abonner à une caractéristique spécifique.
  /// [service] : Le service BLE contenant la caractéristique.
  /// [uuid] : L'UUID de la caractéristique à chercher.
  /// [callback] : La fonction à appeler quand des données arrivent.
  Future<void> _subscribeToCharacteristic(
    BluetoothService service, 
    String uuid, 
    Function(List<int>) callback
  ) async {
    // Recherche de la caractéristique par UUID.
    BluetoothCharacteristic? characteristic;
    for (BluetoothCharacteristic char in service.characteristics) {
      if (char.uuid.toString().toLowerCase() == uuid.toLowerCase()) {
        characteristic = char;
        break;
      }
    }
    
    if (characteristic == null) {
      print("⚠️ Caractéristique $uuid non trouvée.");
      return;
    }
    
    // Vérification que la notification est supportée.
    if (!characteristic.properties.notify) {
      print("⚠️ La caractéristique $uuid ne supporte pas les notifications.");
      return;
    }
    
    // Activation de la notification.
    await characteristic.setNotifyValue(true);
    
    // Écoute du flux de données.
    characteristic.lastValueStream.listen(callback);
  }
  
  /// Callback appelé quand des données GPS arrivent.
  /// Format ESP32 : {"latitude": 12.34, "longitude": 56.78, ...}
  void _onGpsData(List<int> bytes) {
    try {
      String jsonString = utf8.decode(bytes);
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      _latestLat = (json['latitude'] as num?)?.toDouble() ?? _latestLat;
      _latestLon = (json['longitude'] as num?)?.toDouble() ?? _latestLon;
      
      // Après chaque mise à jour, on émet les données fusionnées.
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing GPS: $e");
    }
  }
  
  /// Callback appelé quand des données du capteur d'eau arrivent.
  /// Format ESP32 : {"humidityLevel": 45.5, "rawData": 1024}
  void _onWaterData(List<int> bytes) {
    try {
      String jsonString = utf8.decode(bytes);
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      // Interprétation : si humidité > 30% (seuil arbitraire à ajuster), on considère qu'Il y a de l'eau
      double level = (json['humidityLevel'] as num?)?.toDouble() ?? 0.0;
      _latestWater = level > 30.0;
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing Water: $e");
    }
  }
  
  /// Callback appelé quand des données d'obstacles arrivent.
  /// Format ESP32 : {"upper": 120, "lower": 50, "servoAngle": 90}
  /// Note: Les capteurs renvoient des cm. On convertit en mètres.
  /// Callback appelé quand des données d'obstacles arrivent.
  /// Format ESP32 : {"upper": 120, "lower": 50, "servoAngle": 90}
  /// Note: Les capteurs renvoient des cm. On convertit en mètres.
  void _onObstacleData(List<int> bytes) {
    try {
      String jsonString = utf8.decode(bytes);
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      double lowerCm = (json['lower'] as num?)?.toDouble() ?? 9999.0;
      double upperCm = (json['upper'] as num?)?.toDouble() ?? 9999.0;
      double angle = (json['servoAngle'] as num?)?.toDouble() ?? 90.0;
      
      double distMeters = lowerCm / 100.0; // Conversion cm -> m
      _latestObstacleUp = upperCm / 100.0;
      
      // Catégorisation par secteur (mapping Servo)
      // < 60° : GAUCHE (selon ObstacleDetector.cpp : angleActuel < 60 ? "GAUCHE")
      // > 120° : DROITE (selon ObstacleDetector.cpp : angleActuel > 120 ? "DROITE")
      // Sinon : CENTRE
      
      if (angle < 60) {
        _latestDistLeft = distMeters;
      } else if (angle > 120) {
        _latestDistRight = distMeters;
      } else {
        _latestDistCenter = distMeters;
      }
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing Obstacle: $e");
    }
  }
  
  /// Callback appelé quand des données IMU arrivent.
  /// Format ESP32 : {"yaw": 10.5, "pitch": 5.0, "roll": 2.0}
  void _onImuData(List<int> bytes) {
    try {
      String jsonString = utf8.decode(bytes);
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      _latestHeading = (json['yaw'] as num?)?.toDouble() ?? _latestHeading;
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing IMU: $e");
    }
  }
  
  /// Émet un objet SensorData complet en fusionnant toutes les dernières valeurs.
  void _emitSensorData() {
    SensorData data = SensorData(
      lat: _latestLat,
      lon: _latestLon,
      heading: _latestHeading,
      frontDistance: _latestDistCenter, // Le "Centre" est considéré comme le front principal
      leftDistance: _latestDistLeft,
      rightDistance: _latestDistRight,
      obstacleUp: _latestObstacleUp,
      water: _latestWater,
    );
    
    _sensorDataController.add(data);
  }

  /// Nettoyage des ressources lors de la fermeture du service.
  void dispose() {
    // Déconnexion propre du device.
    _connectedDevice?.disconnect();
    _connectedDevice = null;


    
    // Fermeture du StreamController.
    _sensorDataController.close();
  }
}
