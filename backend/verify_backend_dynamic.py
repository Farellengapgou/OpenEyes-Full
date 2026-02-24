import asyncio
import logging
from app.services.place_index_service import PlaceIndexService
from app.services.nlp_parser import NLPParser
from app.services.maps_service import MapsService

# Configuration des logs
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("Verification")

async def test_dynamic_flow():
    print("\n--- 1. Initialisation des Services ---")
    place_service = PlaceIndexService()
    nlp_parser = NLPParser()
    maps_service = MapsService()

    print("\n--- 2. Simulation Localisation (Yaoundé) ---")
    # Simulation: on est à Yaoundé
    lat, lng = 3.8480, 11.5021
    
    city = place_service.detect_city(lat, lng)
    print(f"Ville détectée: {city}")
    
    if not city:
        print("❌ Échec détection ville. Arrêt.")
        return

    print("\n--- 3. Chargement des lieux (Overpass API) ---")
    print("Cela peut prendre quelques secondes...")
    place_service.fetch_city_places(city, lat, lng)
    
    print(f"Index contient {len(place_service.places_index)} lieux.")
    if len(place_service.places_index) == 0:
        print("⚠️ Aucun lieu chargé via Overpass. Vérifiez la connexion ou l'API.")
    
    print("\n--- 4. Test NLP Dynanique ---")
    test_phrases = [
        "emmène-moi à la pharmacie du soleil",
        "je veux aller à carrefour émia", 
        "guide moi vers bastos",
        "direction poste centrale",
        "vers une destination inconnue au bataillon"
    ]
    
    for text in test_phrases:
        print(f"\n> User: '{text}'")
        candidate = nlp_parser.extract_destination_candidate(text)
        print(f"  Extrait: '{candidate}'")
        
        if candidate:
            name, score, source = nlp_parser.match_place(candidate, place_service)
            print(f"  Match: '{name}' (Score: {score:.2f}, Source: {source})")
            
            final_dest = name if name else candidate
            
            # Test géocodage contextuel
            coords = maps_service.geocode_destination(final_dest, city_context=city)
            print(f"  Geocoding: {coords['formatted_address']} (Source: {coords['source']})")

    print("\n--- 5. Conclusion ---")
    print("Si les lieux ci-dessus (Pharmacie du Soleil, EMIA, Bastos...) sont trouvés avec Source 'local_index' ou 'nominatim', le système fonctionne.")

if __name__ == "__main__":
    asyncio.run(test_dynamic_flow())
