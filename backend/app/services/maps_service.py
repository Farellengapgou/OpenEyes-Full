import requests
from typing import Dict, List, Optional, Tuple
from fastapi import HTTPException
from app.models.response_models import Route, Step, Location
import time
import logging
import math

logger = logging.getLogger(__name__)


class MapsService:
    def __init__(self, user_agent: str = "BlindNavigationApp/1.0 (student_project@univ.cm)"):

        self.nominatim_url = "https://nominatim.openstreetmap.org"
        self.osrm_url = "https://router.project-osrm.org"
        
        self.headers = {
            "User-Agent": user_agent,
            "Accept": "application/json",
            "Accept-Language": "fr"
        }
        
        # Seuils de proximité (en mètres)
        self.STEP_COMPLETION_THRESHOLD = 30  # 30m pour considérer étape terminée
        self.ARRIVAL_THRESHOLD = 20  # 20m pour considérer arrivée
        
        # Cache des itinéraires actifs
        self.active_routes: Dict[str, Route] = {}

    def confirm_destination_text(self, destination: str) -> str:
        """Texte de confirmation générique"""
        if not destination:
            return "Je n'ai pas compris la destination. Pouvez-vous répéter ?"
        
        return f"Je vais vous guider vers {destination}. Souhaitez-vous que je trace l'itinéraire ?"

    
    def geocode_destination(self, destination: str, city_context: Optional[str] = None) -> Dict:
        """Géocodage avec contexte de ville optionnel"""
        try:
            query = destination.strip()
            
            # Ajouter le contexte de ville si disponible et non présent
            if city_context and city_context.lower() not in query.lower():
                query += f", {city_context}"
                
            # Ajouter le pays si non présent pour aider Nominatim
            if "cameroun" not in query.lower():
                query += ", Cameroun"
            
            params = {
                'q': query,
                'format': 'json',
                'limit': 1,
                'countrycodes': 'cm',
                'addressdetails': 1,
                'accept-language': 'fr'
            }
            
            # time.sleep(1) # Removed sleep for performance, Nominatim usage policy permits 1req/s, ensure client respects it logic-side if needed
            
            response = requests.get(
                f"{self.nominatim_url}/search",
                params=params,
                headers=self.headers,
                timeout=10
            )
            
            response.raise_for_status()
            results = response.json()
            
            if not results:
                # Fallback sur une coordonnée par défaut (à améliorer) ou erreur
                # On retourne le point central si on a un contexte, sinon (0,0) ou erreur
                # Pour l'instant on garde le comportement "fallback" mais sans hardcoder Yaoundé si possible
                # Ou on retourne les coords de la ville si on les a ?
                return {
                    "lat": 0.0, 
                    "lng": 0.0,
                    "formatted_address": f"{destination} (Introuvable)",
                    "source": "not_found"
                }
            
            loc = results[0]
            return {
                "lat": float(loc["lat"]),
                "lng": float(loc["lon"]),
                "formatted_address": loc.get("display_name", destination),
                "source": "nominatim"
            }
            
        except Exception as e:
            logger.error(f"Erreur géocodage: {e}")
            return {
                "lat": 0.0,
                "lng": 0.0,
                "formatted_address": "Erreur service",
                "source": "error"
            }

    
    def get_directions(self, origin_lat: float, origin_lng: float,
                      dest_lat: float, dest_lng: float) -> Route:
        """Itinéraire piéton"""
        try:
            coords = f"{origin_lng},{origin_lat};{dest_lng},{dest_lat}"
            
            response = requests.get(
                f"{self.osrm_url}/route/v1/foot/{coords}",
                params={
                    'overview': 'full',
                    'steps': 'true',
                    'geometries': 'geojson',
                    'alternatives': 'false'
                },
                timeout=10
            )
            
            response.raise_for_status()
            data = response.json()
            
            if data.get("code") != "Ok" or not data.get("routes"):
                return self._create_fallback_route(origin_lat, origin_lng, dest_lat, dest_lng)
            
            route = data["routes"][0]
            leg = route["legs"][0]
            steps = []
            
            # ✅ CORRECTION: Utiliser les bonnes coordonnées de début et fin
            for i, step_data in enumerate(leg["steps"]):
                instruction = self._translate_instruction(step_data)
                
                # Coordonnées de départ de cette étape
                start_coords = step_data["maneuver"]["location"]
                
                # Coordonnées de fin: soit le prochain maneuver, soit destination
                if i < len(leg["steps"]) - 1:
                    end_coords = leg["steps"][i + 1]["maneuver"]["location"]
                else:
                    end_coords = [dest_lng, dest_lat]
                
                steps.append(Step(
                    instruction=instruction,
                    distance=f"{step_data['distance']:.0f} m",
                    duration=f"{step_data['duration']/60:.1f} min",
                    start_location=Location(
                        lat=start_coords[1],  # latitude
                        lng=start_coords[0]   # longitude
                    ),
                    end_location=Location(
                        lat=end_coords[1],
                        lng=end_coords[0]
                    )
                ))
            
            return Route(
                summary=leg.get("summary", "Itinéraire piéton"),
                total_distance=f"{route['distance']/1000:.2f} km" if route['distance'] > 1000 else f"{route['distance']:.0f} m",
                total_duration=f"{route['duration']/60:.0f} min",
                steps=steps
            )
            
        except Exception as e:
            logger.error(f"Erreur itinéraire: {e}")
            return self._create_fallback_route(origin_lat, origin_lng, dest_lat, dest_lng)
    
    def _create_fallback_route(self, origin_lat: float, origin_lng: float,
                              dest_lat: float, dest_lng: float) -> Route:
        """Itinéraire de secours"""
        distance = self.calculate_distance(origin_lat, origin_lng, dest_lat, dest_lng)
        
        return Route(
            summary="Itinéraire direct",
            total_distance=f"{distance:.0f} m" if distance < 1000 else f"{distance/1000:.2f} km",
            total_duration=f"{distance/80:.0f} min",  # 80m/min vitesse marche
            steps=[
                Step(
                    instruction="Marchez en ligne droite vers la destination",
                    distance=f"{distance:.0f} m",
                    duration=f"{distance/80:.0f} min",
                    start_location=Location(lat=origin_lat, lng=origin_lng),
                    end_location=Location(lat=dest_lat, lng=dest_lng)
                )
            ]
        )
    
    def _translate_instruction(self, step: dict) -> str:
        """Traduction instructions"""
        m = step["maneuver"]
        typ = m.get("type", "")
        mod = m.get("modifier", "")
        
        if typ == "depart":
            return "Commencez à marcher"
        elif typ == "arrive":
            return "Vous êtes arrivé à destination"
        elif typ == "turn":
            if mod == "left":
                return "Tournez à gauche"
            elif mod == "right":
                return "Tournez à droite"
            elif mod == "straight":
                return "Continuez tout droit"
            elif mod == "sharp left":
                return "Tournez fortement à gauche"
            elif mod == "sharp right":
                return "Tournez fortement à droite"
            elif mod == "slight left":
                return "Tournez légèrement à gauche"
            elif mod == "slight right":
                return "Tournez légèrement à droite"
        elif typ == "roundabout":
            return "Prenez le rond-point"
        elif typ == "continue":
            return "Continuez sur cette voie"
        
        return "Continuez à marcher"
    
    def generate_voice_instructions(self, route: Route) -> List[str]:
        """Instructions audio"""
        instructions = []
        instructions.append(f"Itinéraire trouvé. Distance totale: {route.total_distance}. Durée estimée: {route.total_duration}.")
        
        if route.steps:
            instructions.append(f"Première instruction: {route.steps[0].instruction}.")
        
        instructions.append("Je vous guiderai à chaque étape. Bonne route !")
        return instructions
    
    # ==================== NAVIGATION TEMPS RÉEL ====================
    
    def calculate_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """Calcule distance en mètres (Haversine)"""
        R = 6371000
        
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lng2 - lng1)
        
        a = (math.sin(delta_phi / 2) ** 2 +
             math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        
        return R * c
    
    def get_current_step(self, route: Route, current_lat: float, current_lng: float) -> Tuple[int, Step, float]:
        """
        ✅ CORRIGÉ: Trouve l'étape actuelle basée sur progression du trajet
        """
        if not route.steps:
            return 0, None, 0.0
        
        min_total_distance = float('inf')
        best_step_idx = 0
        
        for i, step in enumerate(route.steps):
            # Distance au DÉBUT de l'étape
            dist_to_start = self.calculate_distance(
                current_lat, current_lng,
                step.start_location.lat, step.start_location.lng
            )
            
            # Distance à la FIN de l'étape
            dist_to_end = self.calculate_distance(
                current_lat, current_lng,
                step.end_location.lat, step.end_location.lng
            )
            
            # Si on est proche du début OU de la fin de cette étape
            if dist_to_start < min_total_distance or dist_to_end < min_total_distance:
                min_total_distance = min(dist_to_start, dist_to_end)
                best_step_idx = i
        
        # Retourner l'étape et la distance jusqu'à la fin de cette étape
        best_step = route.steps[best_step_idx]
        distance_to_end = self.calculate_distance(
            current_lat, current_lng,
            best_step.end_location.lat,
            best_step.end_location.lng
        )
        
        return best_step_idx, best_step, distance_to_end
    
    def check_step_completion(self, distance_to_end: float) -> bool:
        """Vérifie si étape terminée"""
        return distance_to_end < self.STEP_COMPLETION_THRESHOLD
    
    def check_arrival(self, current_lat: float, current_lng: float,
                     dest_lat: float, dest_lng: float) -> bool:
        """Vérifie arrivée"""
        distance = self.calculate_distance(
            current_lat, current_lng, dest_lat, dest_lng
        )
        return distance < self.ARRIVAL_THRESHOLD
    
    def get_navigation_update(self, route: Route, current_lat: float, current_lng: float,
                            dest_lat: float, dest_lng: float) -> Dict:
        """
        Mise à jour navigation temps réel
        """
        # Vérifier arrivée
        if self.check_arrival(current_lat, current_lng, dest_lat, dest_lng):
            return {
                "current_step_index": len(route.steps) - 1,
                "current_instruction": "Vous êtes arrivé à destination",
                "next_instruction": None,
                "distance_to_next": "0 m",
                "distance_to_destination": "0 m",
                "step_completed": True,
                "journey_completed": True,
                "message": "Félicitations ! Vous êtes arrivé à destination."
            }
        
        # Trouver étape actuelle
        step_idx, current_step, dist_to_step_end = self.get_current_step(
            route, current_lat, current_lng
        )
        
        # Vérifier si étape complétée
        step_completed = self.check_step_completion(dist_to_step_end)
        
        # Message à dire
        if step_completed and step_idx < len(route.steps) - 1:
            # Passer à l'étape suivante
            step_idx += 1
            current_step = route.steps[step_idx]
            dist_to_step_end = self.calculate_distance(
                current_lat, current_lng,
                current_step.end_location.lat,
                current_step.end_location.lng
            )
            message = f"Étape terminée. {current_step.instruction}"
        else:
            message = current_step.instruction
        
        # Prochaine instruction
        next_instruction = None
        if step_idx < len(route.steps) - 1:
            next_instruction = route.steps[step_idx + 1].instruction
        
        # Distance totale restante
        total_distance_left = self.calculate_distance(
            current_lat, current_lng, dest_lat, dest_lng
        )
        
        return {
            "current_step_index": step_idx,
            "current_instruction": current_step.instruction,
            "next_instruction": next_instruction,
            "distance_to_next": f"{dist_to_step_end:.0f} m",
            "distance_to_destination": f"{total_distance_left:.0f} m" if total_distance_left < 1000 else f"{total_distance_left/1000:.1f} km",
            "step_completed": step_completed,
            "journey_completed": False,
            "message": message
        }
    
    def store_active_route(self, destination: str, route: Route):
        """Stocke itinéraire actif"""
        self.active_routes[destination.lower()] = route
    
    def get_active_route(self, destination: str) -> Optional[Route]:
        """Récupère itinéraire actif"""
        return self.active_routes.get(destination.lower())
    
    def clear_active_route(self, destination: str):
        """Supprime itinéraire actif"""
        if destination.lower() in self.active_routes:
            del self.active_routes[destination.lower()]