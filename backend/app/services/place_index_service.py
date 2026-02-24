import requests
import logging
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from difflib import SequenceMatcher
import time

logger = logging.getLogger(__name__)

@dataclass
class Place:
    name: str
    type: str  # amenity, shop, etc.
    lat: float
    lng: float
    keywords: List[str]

class PlaceIndexService:
    def __init__(self):
        self.current_city: Optional[str] = None
        self.places_index: List[Place] = []
        self.nominatim_url = "https://nominatim.openstreetmap.org"
        self.overpass_url = "https://overpass-api.de/api/interpreter"
        self.headers = {
            "User-Agent": "BlindNavigationApp/1.0 (student_project@univ.cm)",
            "Accept": "application/json"
        }

    def detect_city(self, lat: float, lng: float) -> Optional[str]:
        """Détermine la ville actuelle via Reverse Geocoding"""
        try:
            params = {
                "lat": lat,
                "lon": lng,
                "format": "json",
                "accept-language": "fr"
            }
            response = requests.get(
                f"{self.nominatim_url}/reverse",
                params=params,
                headers=self.headers,
                timeout=5
            )
            response.raise_for_status()
            data = response.json()
            address = data.get("address", {})
            
            # Ordre de priorité pour le nom de la ville
            city = address.get("city") or address.get("town") or address.get("village") or address.get("municipality")
            
            if city:
                logger.info(f"📍 Ville détectée : {city}")
                return city
            return "Yaoundé" # Fallback safe pour la démo
        except Exception as e:
            logger.error(f"❌ Erreur détection ville : {e}")
            return "Yaoundé"

    def fetch_city_places(self, city: str, lat: float = None, lng: float = None):
        """Récupère les lieux d'intérêt via Overpass API"""
        if self.current_city == city and self.places_index:
            logger.info(f"✅ Lieux pour {city} déjà en cache.")
            return

        logger.info(f"🌍 Chargement des lieux pour : {city}...")
        self.current_city = city
        self.places_index = []

        # Construction de la requête Overpass
        # Priorité 1: Recherche par zone (Ville)
        area_query = f'area["name"="{city}"]->.a;'
        
        # Priorité 2: Si on a des coordonnées, on cherche autour (plus fiable si nom de ville complexe)
        location_filter = "(area.a);"
        if lat is not None and lng is not None:
             # Fallback ou complément: 5km autour
             # Mais pour faire simple on va essayer de combiner ou utiliser le fallback si 0 résultats
             pass

        query = f"""
        [out:json][timeout:25];
        area["name"~"^{city}$", i]->.a;
        (
          node(area.a)["amenity"];
          node(area.a)["shop"];
          node(area.a)["tourism"];
          node(area.a)["leisure"];
          node(area.a)["highway"="bus_stop"];
          node(area.a)["place"="square"];
        );
        out tags center;
        """
        
        # Si coords dispos, on prépare une requête fallback radius
        fallback_query = ""
        if lat and lng:
            fallback_query = f"""
            [out:json][timeout:25];
            (
              node(around:5000, {lat}, {lng})["amenity"];
              node(around:5000, {lat}, {lng})["shop"];
              node(around:5000, {lat}, {lng})["place"];
            );
            out tags center;
            """

        try:
            # Essai 1: Nom de ville
            response = requests.post(
                self.overpass_url,
                data=query,
                headers=self.headers,
                timeout=30
            )
            
            elements = []
            if response.status_code == 200:
                elements = response.json().get("elements", [])
            
            # Essai 2: Radius si vide et courds dispos
            if not elements and fallback_query:
                logger.info(f"⚠️ Ville non trouvée ou vide, passage en mode Radius (5km)...")
                response = requests.post(
                    self.overpass_url,
                    data=fallback_query,
                    headers=self.headers,
                    timeout=30
                )
                if response.status_code == 200:
                    elements = response.json().get("elements", [])

            for el in elements:
                tags = el.get("tags", {})
                name = tags.get("name")
                if not name:
                    continue
                
                # Détermination du type
                place_type = (
                    tags.get("amenity") or 
                    tags.get("shop") or 
                    tags.get("tourism") or 
                    tags.get("leisure") or 
                    tags.get("highway") or
                    tags.get("place") or
                    "lieu"
                )

                # Extraction mots-clés simples
                keywords = [w.lower() for w in name.split() if len(w) > 2]
                
                # Coordonnées (node vs center)
                lat_pl = el.get("lat") or el.get("center", {}).get("lat")
                lng_pl = el.get("lon") or el.get("center", {}).get("lon")
                
                if lat_pl and lng_pl:
                    self.places_index.append(Place(
                        name=name,
                        type=place_type,
                        lat=lat_pl,
                        lng=lng_pl,
                        keywords=keywords
                    ))
            
            logger.info(f"✅ Index construit : {len(self.places_index)} lieux trouvés.")
            
        except Exception as e:
            logger.error(f"❌ Erreur Overpass : {e}")


    def search_place(self, query: str, threshold: float = 0.6) -> List[Tuple[Place, float]]:
        """Recherche floue dans l'index local"""
        if not self.places_index:
            return []
            
        query_norm = query.lower().strip()
        matches = []
        
        for place in self.places_index:
            # Score de similarité (SequenceMatcher)
            similarity = SequenceMatcher(None, query_norm, place.name.lower()).ratio()
            
            # Bonus si le mot clé est contenu
            if query_norm in place.name.lower():
                similarity += 0.2
                
            if similarity >= threshold:
                matches.append((place, min(similarity, 1.0)))
        
        # Trier par score décroissant
        matches.sort(key=lambda x: x[1], reverse=True)
        return matches[:5]  # Top 5 résultats
