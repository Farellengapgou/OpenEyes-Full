import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:blind_navigation/services/api_service.dart';

// Mock http.Client
class MockClient extends Mock implements http.Client {}

// Helper pour MultipartRequest
class FakeMultipartRequest extends Fake implements http.MultipartRequest {
  @override
  final String method;
  @override
  final Uri url;
  @override
  final Map<String, String> fields = {};
  @override
  final List<http.MultipartFile> files = [];

  FakeMultipartRequest(this.method, this.url);
}

void main() {
  late ApiService apiService;
  late MockClient mockClient;

  setUp(() {
    mockClient = MockClient();
    apiService = ApiService(
      baseUrl: 'http://test-url',
      client: mockClient,
      timeout: const Duration(milliseconds: 100), // Short timeout for tests
    );
    
    // Register fallback values if needed
    registerFallbackValue(Uri.parse('http://test-url'));
  });

  group('ApiService Tests', () {
    test('getRoute returns data on success (200)', () async {
      // Arrange
      final responseBody = {'route': {'steps': []}, 'success': true};
      when(() => mockClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      )).thenAnswer((_) async => http.Response(json.encode(responseBody), 200));

      // Act
      final result = await apiService.getRoute(
        destination: 'Paris',
        originLat: 48.0,
        originLng: 2.0,
      );

      // Assert
      expect(result['success'], true);
      verify(() => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body'))).called(1);
    });

    test('getRoute throws ApiException on error (404)', () async {
      // Arrange
      when(() => mockClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      )).thenAnswer((_) async => http.Response('Not Found', 404));

      // Act & Assert
      expect(
        () => apiService.getRoute(
          destination: 'Unknown',
          originLat: 0,
          originLng: 0,
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('getRoute throws ApiException on Timeout', () async {
       // Arrange
       // Note: To really test timeout with the client, we would simulate a delay.
       // However, since we mock the client, we can't easily force the 'timeout' method extension to trigger
       // unless we construct the future ourselves.
       // Instead, we can verify that the TimeoutException is caught if the client throws it.
       // But wait! .timeout() is called ON the future returned by client.post().
       // If we mock client.post() to never return (or return slow), the .timeout() extension takes over.
       
       when(() => mockClient.post(
        any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 200));
        return http.Response('ok', 200);
      });

      // Act & Assert
      expect(
        () => apiService.getRoute(destination: 'Timeout', originLat: 0, originLng: 0),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Timeout'))),
      );
    });
  });
}
