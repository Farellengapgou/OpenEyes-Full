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
  bool get isConnected => _connectedDevice != null || isSimulating;
  bool isSimulating = false;
  Timer? _simulationTimer;

  // Dernières valeurs pour fusion
  double _latestLat = 0.0;
  double _latestLon = 0.0;
  double _latestHeading = 0.0;
  double _latestDistCenter = 99.9;
  double _latestDistLeft = 99.9;
  double _latestDistRight = 99.9;
  double _latestObstacleUp = 99.9;
  bool _latestWater = false;
  double _latestWaterRawData = 0.0;

  /// Démarre une simulation logicielle de la canne (pour tests sans hardware).
  void startSimulation() {
    print("🎭 DÉMARRAGE DU SIMULATEUR CANNE (Mode Fantôme)");
    isSimulating = true;
    int step = 0;

    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!isSimulating) {
        timer.cancel();
        return;
      }

      step++;
      // On simule une marche progressive (environ Yaoundé)
      _latestLat = 3.866 + (step * 0.00005); 
      _latestLon = 11.517 + (step * 0.00005);
      _latestHeading = 45.0; 

      // On simule des évènements périodiques
      if (step == 4) {
        print("🎭 SIM: Obstacle frontal détecté !");
        _latestDistCenter = 0.5;
      } else if (step == 8) {
        print("🎭 SIM: Eau détectée !");
        _latestDistCenter = 2.0;
        _latestWater = true;
      } else {
        _latestDistCenter = 99.9;
        _latestWater = false;
      }

      _emitSensorData();
    });
  }

  /// Arrête la simulation ou le BLE.
  /// Arrête la simulation ou le BLE et libère les ressources.
  void dispose() {
    isSimulating = false;
    _simulationTimer?.cancel();
    
    // Déconnexion propre du device.
    _connectedDevice?.disconnect();
    _connectedDevice = null;

    // Fermeture du StreamController.
    _sensorDataController.close();
  }
  
  // --- ÉTAT INTERNE POUR FUSION DES DONNÉES ---
  // Comme les 4 caractéristiques envoient leurs données indépendamment,
  // on les accumule ici avant de créer un SensorData complet.
  
  // Distances par secteur (pour l'évitement)
  
  // --- MÉTHODES ---

  /// Lance le scan et tente de se connecter automatiquement au device cible.
  /// Attends que la connexion soit établie ou qu'un timeout survienne.
  Future<void> connect() async {
    final Completer<void> completer = Completer<void>();
    StreamSubscription? scanSubscription;

    scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        final name = r.advertisementData.advName;
        if (name.isEmpty) continue;

        if (name == TARGET_DEVICE_NAME) {
          print("✅ OPEN-EYES détecté ! Arrêt du scan et connexion...");
          await FlutterBluePlus.stopScan();
          scanSubscription?.cancel();
          
          try {
            await _connectToDevice(r.device);
            if (!completer.isCompleted) completer.complete();
          } catch (e) {
            print("Erreur de connexion pendant le scan: $e");
            if (!completer.isCompleted) completer.completeError(e);
          }
          return;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
      
      // Si au bout de 15s (timeout du scan) on n'a rien trouvé, on libère le completer
      Future.delayed(const Duration(seconds: 16), () {
        if (!completer.isCompleted) {
          scanSubscription?.cancel();
          completer.complete(); 
        }
      });

      return completer.future;
    } catch (e) {
      scanSubscription?.cancel();
      print("Erreur au lancement du scan BLE: $e");
      rethrow;
    }
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
      print("🔍 Recherche du service: $SERVICE_UUID");
      BluetoothService? targetService;
      for (BluetoothService service in services) {
        print("  - Service trouvé: ${service.uuid.toString()}");
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

      print("✅ Service cible trouvé. Liste des caractéristiques:");
      for (var char in targetService.characteristics) {
        print("  - Caractéristique: ${char.uuid.toString()} [notify: ${char.properties.notify}, read: ${char.properties.read}, write: ${char.properties.write}]");
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
    
    // Écoute du flux de données (Notifications).
    // .onValueReceived est préférable pour les flux de données continus.
    characteristic.onValueReceived.listen((data) {
      // _printDebugInfo(uuid, data); // Trop bruyant
      callback(data);
    });
    print("📡 Écoute active sur la caractéristique $uuid");
  }

  /// Helper pour logger proprement la réception de données.
  void _printDebugInfo(String sensorName, List<int> bytes) {
    // Désactivé pour réduire le bruit
    /*
    if (bytes.isEmpty) { ... }
    */
  }
  
  /// Callback appelé quand des données GPS arrivent.
  /// Format ESP32 : {"latitude": 12.34, "longitude": 56.78, ...}
  void _onGpsData(List<int> bytes) {
    _printDebugInfo("GPS", bytes);
    try {
      String jsonString = utf8.decode(bytes).trim();
      if (jsonString.isEmpty || !jsonString.startsWith('{')) return;
      
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
    _printDebugInfo("EAU", bytes);
    try {
      String jsonString = utf8.decode(bytes).trim();
      if (jsonString.isEmpty || !jsonString.startsWith('{')) return;
      
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      // Interprétation par rawData (0-4095)
      _latestWaterRawData = (json['rawData'] as num?)?.toDouble() ?? 0.0;
      
      // Seuil de caution entre 1000 et 3000, critique au dessus
      // La variable _latestWater pourra servir pour la caution, le système expert gérera le critique
      _latestWater = _latestWaterRawData > 1000.0;
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing Water: $e");
    }
  }
  
  /// Callback appelé quand des données d'obstacles arrivent.
  /// Format ESP32 : {"upper": 120, "lower": 50, "servoAngle": 90}
  /// Note: Les capteurs renvoient des cm. On convertit en mètres.
  void _onObstacleData(List<int> bytes) {
    _printDebugInfo("OBSTACLE", bytes);
    try {
      String jsonString = utf8.decode(bytes).trim();
      if (jsonString.isEmpty || !jsonString.startsWith('{')) return;
      
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      // Upper est maintenant le capteur frontal principal
      double upperCm = (json['upper'] as num?)?.toDouble() ?? 9999.0;
      double lowerCm = (json['lower'] as num?)?.toDouble() ?? 9999.0;
      
      _latestDistCenter = upperCm / 100.0; // Conversion cm -> m
      _latestObstacleUp = lowerCm / 100.0; // On stocke lower ailleurs si besoin, mais center est la priorité
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing Obstacle: $e");
    }
  }
  
  /// Callback appelé quand des données IMU arrivent.
  /// Format ESP32 : {"yaw": 10.5, "pitch": 5.0, "roll": 2.0}
  void _onImuData(List<int> bytes) {
    _printDebugInfo("IMU", bytes);
    try {
      String jsonString = utf8.decode(bytes).trim();
      if (jsonString.isEmpty || !jsonString.startsWith('{')) return;
      
      Map<String, dynamic> json = jsonDecode(jsonString);
      
      _latestHeading = (json['yaw'] as num?)?.toDouble() ?? _latestHeading;
      
      _emitSensorData();
    } catch (e) {
      print("Erreur parsing IMU: $e");
    }
  }
  
  /// Émet un objet SensorData complet en fusionnant toutes les dernières valeurs.
  void _emitSensorData() {
    // On n'empêche plus l'émission si les coordonnées sont à 0,0,
    // car on veut au moins que les obstacles et l'IMU fonctionnent.
    if (_latestLat == 0.0 && _latestLon == 0.0) {
      print("⏳ Données canne reçues, mais en attente d'un fix GPS valide...");
    }

    SensorData data = SensorData(
      lat: _latestLat,
      lon: _latestLon,
      heading: _latestHeading,
      frontDistance: _latestDistCenter,
      leftDistance: _latestDistLeft,
      rightDistance: _latestDistRight,
      obstacleUp: _latestObstacleUp,
      water: _latestWater,
      waterRawData: _latestWaterRawData,
    );
    
    _sensorDataController.add(data);
  }

}
