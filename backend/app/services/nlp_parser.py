import re
import logging
from typing import Optional, Tuple
from app.services.place_index_service import PlaceIndexService

logger = logging.getLogger(__name__)

class NLPParser:
    def __init__(self):
        # Patterns de recherche pour isoler la destination
        self.destination_patterns = [
            r"(?:aller|vais|veux|voudrais|aimerais)\s+(?:à|au|aux|chez)?\s*(.+)",
            r"(?:vers|direction|jusqu['\s]*à)\s+(.+)",
            r"(?:emmène-moi|guide-moi|conduis-moi)\s+(?:à|au|aux)?\s*(.+)",
        ]

    def extract_destination_candidate(self, text: str) -> Optional[str]:
        """Extrait une chaîne candidate pour la destination (sans validation)"""
        if not text:
            return None

        text = text.lower().strip()

        # 1️⃣ Regex
        for pattern in self.destination_patterns:
            match = re.search(pattern, text)
            if match:
                return self._clean(match.group(1))

        # 2️⃣ Fallback : dernier groupe nominal (3 derniers mots)
        words = text.split()
        if len(words) >= 2:
            return self._clean(" ".join(words[-3:]))

        return None

    def match_place(self, candidate: str, index_service: PlaceIndexService) -> Tuple[Optional[str], float, str]:
        """
        Cherche le candidat dans l'index local.
        Retourne: (Nom complet trouvé, Confiance, Source)
        """
        if not candidate:
            return None, 0.0, "none"
            
        # 1. Recherche floue dans l'index
        matches = index_service.search_place(candidate)
        
        if matches:
            best_place, score = matches[0]
            if score > 0.6:
                return best_place.name, score, "local_index"
        
        # 2. Si rien trouvé, on garde le candidat brut pour Nominatim
        return candidate, 0.5, "raw_text"

    def _clean(self, dest: str) -> str:
        """Nettoie les mots de liaison"""
        stop_words = {"le", "la", "les", "l'", "un", "une", "du", "de", "des"}
        words = dest.split()
        
        # Enlever les stop words du début seulement
        while words and words[0] in stop_words:
            words.pop(0)
            
        return " ".join(words).strip()