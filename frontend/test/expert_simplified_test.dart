import 'package:flutter_test/flutter_test.dart';
import '../lib/features/navigation/sensor_data.dart';
import '../lib/features/navigation/simple_expert.dart';

void main() {
  group('SimpleExpert Simplified Logic Tests', () {
    late SimpleExpert expert;

    setUp(() {
      expert = SimpleExpert();
    });

    test('Obstacle stops and suggests turn', () {
      final sensor = SensorData(
        lat: 3.0,
        lon: 11.0,
        heading: 0.0,
        frontDistance: 0.2, // Obstacle below 0.4m
        obstacleUp: 99.9,
        water: false,
        waterRawData: 500.0,
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 100.0,
        bearingToDestination: 0.0,
      );

      expect(action.shouldStop, isTrue);
      expect(action.instruction, contains("Obstacle devant"));
      expect(action.instruction, contains("Tournez à droite"));
    });

    test('Critical water stops and suggests turn', () {
      final sensor = SensorData(
        lat: 3.0,
        lon: 11.0,
        heading: 0.0,
        frontDistance: 5.0,
        obstacleUp: 99.9,
        water: true,
        waterRawData: 3500.0, // Critical water
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 100.0,
        bearingToDestination: 0.0,
      );

      expect(action.shouldStop, isTrue);
      expect(action.instruction, contains("Niveau d'eau critique"));
    });

    test('Caution water gives warning', () {
      final sensor = SensorData(
        lat: 3.0,
        lon: 11.0,
        heading: 0.0,
        frontDistance: 5.0,
        obstacleUp: 99.9,
        water: true,
        waterRawData: 2000.0, // Caution water
      );

      final action = expert.evaluate(
        sensor: sensor,
        distToDestination: 100.0,
        bearingToDestination: 0.0,
      );

      expect(action.shouldStop, isFalse);
      expect(action.instruction, contains("eau au sol considérable"));
    });

    test('Heading correction threshold is increased', () {
      final sensor = SensorData(
        lat: 3.0,
        lon: 11.0,
        heading: 35.0, // 35° deviation
        frontDistance: 5.0,
        obstacleUp: 99.9,
        water: false,
        waterRawData: 200.0,
      );

      // First call to establish previous position
      expert.evaluate(
        sensor: sensor,
        distToDestination: 100.0,
        bearingToDestination: 0.0,
      );

      // Move a bit to satisfy hasMoved (requires > 2.0m)
      final sensorMoved = SensorData(
        lat: 3.0001, // Roughly 11m shift
        lon: 11.0,
        heading: 35.0,
        frontDistance: 5.0,
        obstacleUp: 99.9,
        water: false,
        waterRawData: 200.0,
      );

      final action = expert.evaluate(
        sensor: sensorMoved,
        distToDestination: 90.0,
        bearingToDestination: 0.0,
      );

      // Deviation of 35° should NOT trigger correction as threshold is now 40°
      expect(action.instruction, isEmpty);
    });
  });
}
