import 'package:flutter_test/flutter_test.dart';
import 'package:blind_navigation/features/navigation/simple_expert.dart';
import 'package:blind_navigation/features/navigation/sensor_data.dart';

void main() {
  group('Navigation Logic Simulation', () {
    late SimpleExpert expert;

    setUp(() {
      expert = SimpleExpert();
    });

    test('Scenario 1: Obstacle Frontal -> Advice to Avoid (Even with GPS 0,0)', () {
      final sensor = SensorData(
        lat: 0.0, lon: 0.0, heading: 0,
        frontDistance: 0.3, 
        leftDistance: 2.0,  
        rightDistance: 0.5,
        obstacleUp: 2.0,
        water: false,
        waterRawData: 0.0,
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0, 
      );

      print("Scenario 1 Output: ${action.instruction}");
      expect(action.shouldStop, true);
      expect(action.instruction, contains("Obstacle devant"));
      expect(action.instruction, contains("Tournez à droite"));
    });
    
    test('Scenario 2: GPS is 0,0 -> Navigation instructions are ignored', () {
      final sensor = SensorData(
        lat: 0.0, lon: 0.0, heading: 45, // Cap faussé
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: false,
        waterRawData: 0.0,
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0, 
      );

      expect(action.instruction, isEmpty, reason: "Aucune instruction si GPS est 0.0");
    });

    test('Scenario 3: Bad Heading -> Correction Right (with valid GPS)', () {
      final sensor = SensorData(
        lat: 4.0, lon: 9.0, // Valid coord
        heading: 300, // 60 degs off
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: false,
        waterRawData: 0.0,
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0,
      );

      print("Scenario 3 Output: ${action.instruction}");
      expect(action.instruction, contains("droite"));
    });

    test('Scenario 4: Stationary Filtering -> No repeated instructions', () {
      // 1er appel : Correction
      expert.evaluate(
        sensor: SensorData(lat: 4.0, lon: 9.0, heading: 320, frontDistance: 2.0, obstacleUp: 2.0, water: false, waterRawData: 0.0),
        distToDestination: 50.0,
        bearingToDestination: 0.0,
      );

      // 2ème appel : Toujours au même endroit, le heading a empiré mais on n'a pas bougé
      final action = expert.evaluate(
        sensor: SensorData(lat: 4.0, lon: 9.0, heading: 310, frontDistance: 2.0, obstacleUp: 2.0, water: false, waterRawData: 0.0),
        distToDestination: 50.0,
        bearingToDestination: 0.0,
      );

      expect(action.instruction, isEmpty, reason: "Pas d'instruction si on n'a pas bougé de 2.0m");
    });

    test('Scenario 5: Arrival', () {
      final sensor = SensorData(
        lat: 4.0, lon: 9.0, heading: 0,
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: false,
        waterRawData: 0.0,
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 2.5, // < 3.0m
        bearingToDestination: 0.0,
      );

      expect(action.instruction, contains("arrivé"));
      expect(action.shouldStop, true);
    });
  });
}
