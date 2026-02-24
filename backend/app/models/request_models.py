from pydantic import BaseModel, Field
from typing import Optional

class NavigationRequest(BaseModel):
    """Requête pour obtenir un itinéraire depuis une destination textuelle"""
    destination: str = Field(..., description="Nom de la destination (ex: 'Carrefour Emia')")
    origin_lat: float = Field(..., description="Latitude de départ")
    origin_lng: float = Field(..., description="Longitude de départ")


class PositionUpdate(BaseModel):
    """Mise à jour de position GPS pour navigation temps réel"""
    current_lat: float = Field(..., description="Latitude actuelle")
    current_lng: float = Field(..., description="Longitude actuelle")
    route_id: Optional[str] = Field(None, description="ID de l'itinéraire en cours (optionnel)")
    destination: str = Field(..., description="Destination en cours")