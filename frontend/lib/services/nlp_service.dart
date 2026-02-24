/// Service de parsing NLP en Dart.
/// Port direct du backend nlp_parser.py – même logique, zéro dépendance externe.
class NlpService {
  /// Patterns regex pour isoler la destination depuis le texte transcrit.
  static final List<RegExp> _patterns = [
    RegExp(
      r"(?:aller|vais|veux|voudrais|aimerais)\s+(?:à|au|aux|chez)?\s*(.+)",
      caseSensitive: false,
    ),
    RegExp(
      r"(?:vers|direction|jusqu['\s]*à)\s+(.+)",
      caseSensitive: false,
    ),
    RegExp(
      r"(?:emmène-moi|guide-moi|conduis-moi)\s+(?:à|au|aux)?\s*(.+)",
      caseSensitive: false,
    ),
  ];

  /// Mots à ignorer en début de destination.
  static const _stopWords = {
    'le', 'la', 'les', "l'", 'un', 'une', 'du', 'de', 'des',
  };

  /// Corrections phonétiques des erreurs de STT fréquentes à Yaoundé.
  static const Map<String, String> _corrections = {
    'minced': 'mendong',
    'minded': 'mendong',
    'mendon': 'mendong',
    'mendog': 'mendong',
    'mend ong': 'mendong',
    'marshe': 'marché',
    'marche': 'marché',
    'carulfour': 'carrefour',
    'car four': 'carrefour',
    'care four': 'carrefour',
    'emi a': 'emia',
    'emiya': 'emia',
    'n komo': 'nkomo',
    'en como': 'nkomo',
    'nlong kak': 'nlongkak',
    'long kak': 'nlongkak',
    'basto': 'bastos',
    'od za': 'odza',
    'yaounde': 'yaoundé',
    'moco lo': 'mokolo',
  };

  /// Corrige les erreurs phonétiques courantes du STT.
  String cleanTranscription(String text) {
    var result = text.toLowerCase().trim();

    // Appliquer toutes les corrections
    for (final entry in _corrections.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // Supprimer ponctuation inutile
    result = result.replaceAll(RegExp(r'[.,!?;:"]'), '');

    // Nettoyer espaces multiples
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Supprimer formules de politesse en fin
    result = result.replaceAll(
      RegExp(r"( s'il vous plaît| svp| merci| please| s'il te plaît| stp)$"),
      '',
    ).trim();

    return result;
  }

  /// Extrait la destination candidate depuis le texte nettoyé.
  /// Retourne null si rien n'est trouvé.
  String? extractDestination(String rawText) {
    if (rawText.trim().isEmpty) return null;

    final text = cleanTranscription(rawText);

    // 1. Essayer les patterns regex (ex: "aller à ...")
    for (final pattern in _patterns) {
      final match = pattern.firstMatch(text);
      if (match != null && match.groupCount >= 1) {
        final candidate = _clean(match.group(1) ?? '');
        if (candidate.isNotEmpty) return candidate;
      }
    }

    // 2. Fallback flexible : 
    // Si aucun pattern n'a matché, on prend TOUT le texte nettoyé (ex: "Mendong").
    // Plus besoin de vérifier si words.length >= 2.
    final candidate = _clean(text);
    if (candidate.isNotEmpty) return candidate;

    return null;
  }

  /// Supprime les stop-words du début de la chaîne.
  String _clean(String dest) {
    var words = dest.trim().split(' ').where((w) => w.isNotEmpty).toList();

    while (words.isNotEmpty && _stopWords.contains(words.first.toLowerCase())) {
      words = words.sublist(1);
    }

    return words.join(' ').trim();
  }

  /// Normalise la destination pour l'affichage et l'envoi à l'API.
  /// Ex: "marché mendong" → "Marché Mendong"
  String normalize(String destination) {
    return destination
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : word)
        .join(' ');
  }

  /// Génère le texte de confirmation TTS.
  String confirmationText(String destination) {
    if (destination.isEmpty) {
      return "Je n'ai pas compris la destination. Pouvez-vous répéter ?";
    }
    return "Je vais vous guider vers $destination. Dites oui pour confirmer ou non pour annuler.";
  }

  /// Génère des suggestions si la destination n'est pas comprise.
  String getSuggestions(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('carrefour')) return 'Carrefour Émia ou Carrefour Nkomo';
    if (lower.contains('marché')) return 'Marché Mendong ou Marché Mokolo';
    if (lower.contains('quartier')) return 'Quartier Bastos ou Quartier Melen';
    if (lower.contains('hôpital')) return 'Hôpital Central ou Hôpital Général';
    return 'Carrefour Émia, Marché Mendong, ou Quartier Bastos';
  }
}
