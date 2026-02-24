from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Dict

# Imports relatifs pour les modules internes à app/
from .routes import navigation, speech
from .config import get_settings
from .services.speech_to_text import SpeechToTextService
from .services.nlp_parser import NLPParser
from .services.maps_service import MapsService

# --- 1. INITIALISATION BASÉE SUR LA CONFIGURATION ---
settings = get_settings()

app = FastAPI(
    title=settings.app_name,
    description="API de navigation vocale pour utilisateurs malvoyants, optimisée pour Yaoundé.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# --- 2. CONFIGURATION CORS ---
# Adapté pour votre application Flutter
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # À restreindre en production (ex: ["https://votreapp.com"])
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 3. GESTION DES DÉPENDANCES CRITIQUES AU DÉMARRAGE ---
@app.on_event("startup")
async def startup_event():
    """
    Initialise les services lourds et les stocke dans l'état de l'application (app.state).
    Ceci est CRUCIAL pour que Whisper (STT) et les parsers ne chargent qu'une seule fois.
    """
    print("\n--- Démarrage de l'API ---")
    try:
        # Initialisation des services
        app.state.stt_service = SpeechToTextService()
        app.state.nlp_parser = NLPParser()
        app.state.maps_service = MapsService()
        print("✅ Tous les services critiques (STT, NLP, Maps) sont chargés.")
        
    except RuntimeError as e:
        # Erreur FFmpeg ou PyTorch/Whisper non gérée
        print(f"❌ ÉCHEC CRITIQUE DE DÉMARRAGE des services: {e}")
        # En production, vous voudriez peut-être lancer une exception pour arrêter l'API
        # raise HTTPException(status_code=500, detail="Configuration critique échouée.")
    except Exception as e:
        print(f"❌ Erreur inattendue au démarrage: {e}")
        
    print("---------------------------\n")


# --- 4. ENREGISTREMENT DES ROUTES ---
# Assurez-vous que les fichiers app/routes/speech.py et app/routes/navigation.py existent
app.include_router(speech.router)
app.include_router(navigation.router)


# --- 5. ROUTES DE BASE ET DE SANTÉ ---
@app.get("/")
async def root() -> Dict[str, str]:
    return {
        "message": "API Navigation Vocale",
        "version": "1.0.0",
        "status": "Opérationnel",
        "documentation": "/docs"
    }

@app.get("/health")
async def health_check() -> Dict[str, str]:
    # Une vérification de santé plus avancée pourrait vérifier l'état des services externes (OSM, OSRM)
    return {"status": "healthy"}