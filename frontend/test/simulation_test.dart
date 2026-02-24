import 'package:flutter_test/flutter_test.dart';
import 'package:blind_navigation/features/navigation/simple_expert.dart';
import 'package:blind_navigation/features/navigation/sensor_data.dart';

void main() {
  group('Navigation Logic Simulation', () {
    late SimpleExpert expert;

    setUp(() {
      expert = SimpleExpert();
    });

    test('Scenario 1: Obstacle Frontal -> Advice to Avoid', () {
      // Données simulées : Obstacle Centre, mais Gauche libre
      final sensor = SensorData(
        lat: 0, lon: 0, heading: 0,
        frontDistance: 0.5, // Bloqué au centre
        leftDistance: 2.0,  // Libre à gauche
        rightDistance: 0.5, // Bloqué à droite
        obstacleUp: 2.0,
        water: false
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0, 
      );

      print("Scenario 1 Output: ${action.instruction}");
      expect(action.shouldStop, true);
      expect(action.instruction, contains("Contournez par la gauche"));
    });
    
    test('Scenario 1b: Obstacle Frontal -> Blocked', () {
      // Tout bloqué
      final sensor = SensorData(
        lat: 0, lon: 0, heading: 0,
        frontDistance: 0.5, 
        leftDistance: 0.5,
        rightDistance: 0.5,
        obstacleUp: 2.0,
        water: false
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0, 
      );

      print("Scenario 1b Output: ${action.instruction}");
      expect(action.instruction, contains("Zone bloquée"));
    });

    test('Scenario 2: Water Detected -> Caution', () {
      // Données simulées : Eau détectée
      final sensor = SensorData(
        lat: 0, lon: 0, heading: 0,
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: true
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0,
      );

      print("Scenario 2 Output: ${action.instruction}");
      expect(action.instruction, contains("eau au sol"));
    });

    test('Scenario 3: Bad Heading -> Correction Right', () {
      // On veut aller au Cap 0 (Nord). On regarde vers -20 (340°)
      // Diff = 0 - 340 = -340 => +20 deg (donc on doit tourner à droite pour revenir à 0)
      // Wait. bearingToDestination = 0. Heading = 340 (-20).
      // Diff = 0 - 340 = -340. Normalize: -340 + 360 = +20.
      // Diff > 15. Direction ?
      // SimpleExpert logic: diff > 0 ? droite : gauche.
      // +20 > 0 -> Droite. Correct.

      final sensor = SensorData(
        lat: 0, lon: 0, heading: 340, // 20 degs off to left
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: false
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 50.0,
        bearingToDestination: 0.0,
      );

      print("Scenario 3 Output: ${action.instruction}");
      expect(action.instruction, contains("droite"));
    });

    test('Scenario 4: Arrival', () {
      final sensor = SensorData(
        lat: 0, lon: 0, heading: 0,
        frontDistance: 2.0,
        obstacleUp: 2.0,
        water: false
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 2.5, // < 3.0m
        bearingToDestination: 0.0,
      );

      print("Scenario 4 Output: ${action.instruction}");
      expect(action.instruction, contains("arrivé"));
      expect(action.shouldStop, true);
    });
  });
}
