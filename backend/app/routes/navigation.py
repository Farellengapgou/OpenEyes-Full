from fastapi import APIRouter, UploadFile, File, HTTPException, Depends, Form, Body
from app.services.speech_to_text import SpeechToTextService
from app.services.nlp_parser import NLPParser
from app.services.maps_service import MapsService
from app.services.place_index_service import PlaceIndexService
from app.models.response_models import NavigationResponse, PositionUpdateResponse
from app.models.request_models import NavigationRequest, PositionUpdate
from app.config import get_settings, Settings
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/navigation", tags=["Navigation"])

# Services globaux
speech_service: SpeechToTextService = None
nlp_parser = NLPParser()
maps_service: MapsService = None
place_index_service = PlaceIndexService()

# Dépendances FastAPI
def get_speech_service(settings: Settings = Depends(get_settings)):
    global speech_service
    if speech_service is None:
        speech_service = SpeechToTextService(settings.whisper_model)
    return speech_service

def get_maps_service(settings: Settings = Depends(get_settings)):
    global maps_service
    if maps_service is None:
        maps_service = MapsService(settings.nominatim_user_agent)
    return maps_service

def get_place_service():
    return place_index_service


# ------------------------------------------------------------------
# GET ROUTE (texte -> itinéraire)
# ------------------------------------------------------------------
@router.post("/get-route", response_model=NavigationResponse)
async def get_route(
    request: NavigationRequest,
    maps_svc: MapsService = Depends(get_maps_service),
    place_svc: PlaceIndexService = Depends(get_place_service)
):
    """
    Obtient un itinéraire à partir d'une destination textuelle
    """
    try:
        logger.info(f"Calcul itinéraire vers: {request.destination}")
        
        # Géocoder la destination avec contexte
        context_city = place_svc.current_city
        dest_coords = maps_svc.geocode_destination(request.destination, city_context=context_city)
        
        if dest_coords.get("source") in ["not_found", "error"]:
             raise HTTPException(status_code=404, detail=f"Destination introuvable: {request.destination}")

        # Calculer l'itinéraire
        route = maps_svc.get_directions(
            request.origin_lat, request.origin_lng,
            dest_coords['lat'], dest_coords['lng']
        )
        
        # Stocker l'itinéraire pour le suivi GPS
        maps_svc.store_active_route(request.destination, route)
        
        # Générer instructions vocales
        voice_instructions = maps_svc.generate_voice_instructions(route)
        
        logger.info(f"✅ Itinéraire calculé: {route.total_distance}, {len(route.steps)} étapes")

        return NavigationResponse(
            success=True,
            destination=dest_coords['formatted_address'],
            destination_coords={
                "lat": dest_coords['lat'], 
                "lng": dest_coords['lng']
            },
            route=route,
            voice_instructions=voice_instructions,
            error=None
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Erreur calcul itinéraire: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Erreur calcul itinéraire: {str(e)}")


# ------------------------------------------------------------------
# VOICE NAVIGATION (audio -> itinéraire)
# ------------------------------------------------------------------
@router.post("/voice-navigation", response_model=NavigationResponse)
async def voice_navigation(
    audio: UploadFile = File(...),
    origin_lat: float = Form(...),
    origin_lng: float = Form(...),
    speech_svc: SpeechToTextService = Depends(get_speech_service),
    maps_svc: MapsService = Depends(get_maps_service),
    place_svc: PlaceIndexService = Depends(get_place_service),
    settings: Settings = Depends(get_settings)
):
    """
    Endpoint complet: audio -> transcription -> destination -> itinéraire
    """
    try:
        logger.info(f"Voice navigation demandée depuis ({origin_lat}, {origin_lng})")
        
        # Initialiser le contexte ville si inconnu (important pour premier appel)
        if not place_svc.current_city:
            city = place_svc.detect_city(origin_lat, origin_lng)
            if city:
                place_svc.fetch_city_places(city)

        # 1️⃣ Lire le contenu audio
        content = await audio.read()
        
        if len(content) > settings.max_audio_size:
            raise HTTPException(status_code=413, detail="Fichier audio trop volumineux")
        
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="Fichier audio vide")
        
        # 2️⃣ Transcrire l'audio
        transcription = await speech_svc.transcribe_audio(audio, content)
        logger.info(f"Transcription: '{transcription}'")

        # 3️⃣ Extraire et valider la destination
        candidate = nlp_parser.extract_destination_candidate(transcription)
        
        if not candidate:
            logger.warning("Aucun candidat destination extrait")
            return NavigationResponse(
                success=False,
                destination="Non comprise",
                destination_coords={},
                route=None,
                voice_instructions=[],
                error="Je n'ai pas compris la destination. Essayez de reformuler."
            )

        # Recherche dans l'index local
        matched_name, confidence, source = nlp_parser.match_place(candidate, place_svc)
        
        final_destination = matched_name if matched_name else candidate
        logger.info(f"NLP: '{candidate}' -> '{final_destination}' (Source: {source}, Confiance: {confidence:.2f})")

        # 4️⃣ Géocoder la destination
        dest_coords = maps_svc.geocode_destination(final_destination, city_context=place_svc.current_city)
        logger.info(f"Destination géocodée: {dest_coords['formatted_address']}")
        
        if dest_coords.get("source") == "not_found":
             return NavigationResponse(
                success=False,
                destination=final_destination,
                destination_coords={},
                route=None,
                voice_instructions=[],
                error=f"Je ne trouve pas '{final_destination}' à {place_svc.current_city or 'proximité'}."
            )

        # 5️⃣ Obtenir l'itinéraire
        route = maps_svc.get_directions(
            origin_lat, origin_lng,
            dest_coords['lat'], dest_coords['lng']
        )
        
        # Stocker pour suivi GPS
        maps_svc.store_active_route(final_destination, route)

        # 6️⃣ Générer instructions vocales
        voice_instructions = maps_svc.generate_voice_instructions(route)
        
        # Ajouter une confirmation contextuelle
        voice_instructions.insert(0, maps_svc.confirm_destination_text(dest_coords['formatted_address'].split(',')[0]))
        
        logger.info(f"✅ Voice navigation prête: {route.total_distance}")

        # 7️⃣ Retour
        return NavigationResponse(
            success=True,
            destination=dest_coords['formatted_address'],
            destination_coords={
                "lat": dest_coords['lat'], 
                "lng": dest_coords['lng']
            },
            route=route,
            voice_instructions=voice_instructions,
            error=None
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"❌ Erreur voice navigation: {e}", exc_info=True)
        return NavigationResponse(
            success=False,
            destination="Erreur",
            destination_coords={},
            route=None,
            voice_instructions=[],
            error=f"Erreur lors du traitement: {str(e)}"
        )


# ------------------------------------------------------------------
# UPDATE POSITION (GPS temps réel) - NOUVEAU
# ------------------------------------------------------------------
@router.post("/update-position", response_model=PositionUpdateResponse)
async def update_position(
    position: PositionUpdate = Body(...),
    maps_svc: MapsService = Depends(get_maps_service),
    place_svc: PlaceIndexService = Depends(get_place_service)
):
    """
    Mise à jour de position GPS en temps réel
    """
    try:
        # Check changement de ville ou initialisation (optimisation basique)
        if not place_svc.current_city:
             city = place_svc.detect_city(position.current_lat, position.current_lng)
             if city:
                 # On lance le fetch en background idéalement, mais ici en sync pour simplicité prototype
                 place_svc.fetch_city_places(city)

        # Récupérer l'itinéraire actif
        route = maps_svc.get_active_route(position.destination)
        
        if not route:
            # Code existant...
            return PositionUpdateResponse(
                success=False,
                current_step_index=0,
                current_instruction="Aucun itinéraire actif.",
                next_instruction=None,
                distance_to_next="N/A",
                distance_to_destination="N/A",
                step_completed=False,
                journey_completed=False,
                message="Aucun itinéraire en cours."
            )
        
        # Géocoder la destination pour avoir ses coordonnées 
        # (Idéalement on devrait stocker les coords de la dest active pour ne pas re-geocoder a chaque tick)
        dest_coords = maps_svc.geocode_destination(position.destination, city_context=place_svc.current_city)
        
        # Calculer la mise à jour de navigation
        nav_update = maps_svc.get_navigation_update(
            route,
            position.current_lat,
            position.current_lng,
            dest_coords['lat'],
            dest_coords['lng']
        )
        
        # Si arrivée, nettoyer l'itinéraire
        if nav_update['journey_completed']:
            maps_svc.clear_active_route(position.destination)
        
        return PositionUpdateResponse(
            success=True,
            current_step_index=nav_update['current_step_index'],
            current_instruction=nav_update['current_instruction'],
            next_instruction=nav_update['next_instruction'],
            distance_to_next=nav_update['distance_to_next'],
            distance_to_destination=nav_update['distance_to_destination'],
            step_completed=nav_update['step_completed'],
            journey_completed=nav_update['journey_completed'],
            message=nav_update['message']
        )
        
    except Exception as e:
        logger.error(f"❌ Erreur mise à jour position: {e}", exc_info=True)
        return PositionUpdateResponse(
            success=False,
            current_step_index=0,
            current_instruction="Erreur",
            next_instruction=None,
            distance_to_next="N/A",
            distance_to_destination="N/A",
            step_completed=False,
            journey_completed=False,
            message=str(e)
        )