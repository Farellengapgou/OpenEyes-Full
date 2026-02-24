import 'package:flutter_test/flutter_test.dart';
import 'package:blind_navigation/services/nlp_service.dart';

void main() {
  group('NlpService Tests', () {
    late NlpService nlpService;

    setUp(() {
      nlpService = NlpService();
    });

    test('cleanTranscription should not over-correct "bastos"', () {
      const input = "Carrefour Bastos";
      final cleaned = nlpService.cleanTranscription(input);
      print("DEBUG TEST: input='$input' -> cleaned='$cleaned'");
      expect(cleaned, equals("carrefour bastos"));
    });

    test('extractDestination should handle common phrases', () {
      expect(nlpService.extractDestination("Je veux aller à Bastos"), "bastos");
      expect(nlpService.extractDestination("Emmène-moi au Marché Mendong"), "marché mendong");
    });

    test('normalize should capitalize words', () {
      expect(nlpService.normalize("carrefour bastos"), "Carrefour Bastos");
      expect(nlpService.normalize("marché mendong"), "Marché Mendong");
    });
  });
}
