from pydantic import BaseModel, Field
from typing import List, Optional, Dict

class Location(BaseModel):
    lat: float = Field(..., description="Latitude")
    lng: float = Field(..., description="Longitude")

class Step(BaseModel):
    instruction: str = Field(..., description="Instruction vocale")
    distance: str = Field(..., description="Distance formatée")
    duration: str = Field(..., description="Durée formatée")
    start_location: Location = Field(..., description="Point de départ")
    end_location: Location = Field(..., description="Point d'arrivée")

class Route(BaseModel):
    summary: str = Field(..., description="Résumé de l'itinéraire")
    total_distance: str = Field(..., description="Distance totale")
    total_duration: str = Field(..., description="Durée totale")
    steps: List[Step] = Field(..., description="Liste des étapes")

class SpeechResponse(BaseModel):
    """Réponse pour la transcription vocale (Flutter audio)"""
    success: bool = Field(..., description="Succès de la transcription")
    transcription: str = Field(..., description="Texte transcrit")
    destination: Optional[str] = Field(None, description="Destination extraite")
    confirmation_text: Optional[str] = Field(None, description="Texte de confirmation audio")
    error: Optional[str] = Field(None, description="Message d'erreur")

class ConfirmationResponse(BaseModel):
    """Réponse pour la confirmation Oui/Non de la destination"""
    confirmed: bool = Field(..., description="True si 'oui', False si 'non'")
    needs_retry: bool = Field(..., description="True si réponse ambiguë (ni oui ni non)")
    transcription: str = Field(..., description="Ce que l'utilisateur a dit")
    message: str = Field(..., description="Message vocal à lire à l'aveugle via TTS")

class NavigationResponse(BaseModel):
    """Réponse pour la navigation (Flutter audio)"""
    success: bool = Field(..., description="Succès de la navigation")
    destination: str = Field(..., description="Nom de la destination")
    destination_coords: Location = Field(..., description="Coordonnées de destination")
    route: Optional[Route] = Field(None, description="Itinéraire calculé")
    voice_instructions: List[str] = Field(..., description="Instructions audio")
    error: Optional[str] = Field(None, description="Message d'erreur")

class HealthResponse(BaseModel):
    status: str = Field(..., description="État du service")
    version: str = Field(..., description="Version de l'API")
    whisper_model: str = Field(..., description="Modèle Whisper utilisé")

class PositionUpdateResponse(BaseModel):
    """Réponse pour mise à jour position GPS en temps réel"""
    success: bool = Field(..., description="Succès de la mise à jour")
    current_step_index: int = Field(..., description="Index de l'étape actuelle (0-based)")
    current_instruction: str = Field(..., description="Instruction vocale actuelle")
    next_instruction: Optional[str] = Field(None, description="Prochaine instruction")
    distance_to_next: str = Field(..., description="Distance jusqu'au prochain tournant")
    distance_to_destination: str = Field(..., description="Distance totale restante")
    step_completed: bool = Field(..., description="True si l'étape vient d'être complétée")
    journey_completed: bool = Field(..., description="True si destination atteinte")
    message: str = Field(..., description="Message vocal à lire")