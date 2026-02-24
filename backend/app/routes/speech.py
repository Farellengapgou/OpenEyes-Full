from fastapi import APIRouter, UploadFile, File, HTTPException, Depends
from app.services.speech_to_text import SpeechToTextService
from app.services.nlp_parser import NLPParser
from app.services.maps_service import MapsService
from app.models.response_models import SpeechResponse, ConfirmationResponse
from app.config import get_settings, Settings
import logging

# Logger
logger = logging.getLogger(__name__)

router = APIRouter(prefix="/speech", tags=["Speech"])

# Services globaux avec lazy initialization
speech_service = None
nlp_parser = None
maps_service = None

# Dépendances avec lazy loading
def get_speech_service(settings: Settings = Depends(get_settings)):
    global speech_service
    if speech_service is None:
        from app.services.speech_to_text import SpeechToTextService
        speech_service = SpeechToTextService(settings.whisper_model)
    return speech_service

def get_nlp_parser():
    global nlp_parser
    if nlp_parser is None:
        from app.services.nlp_parser import NLPParser
        nlp_parser = NLPParser()
    return nlp_parser

def get_maps_service():
    global maps_service
    if maps_service is None:
        from app.services.maps_service import MapsService
        maps_service = MapsService()
    return maps_service


@router.post("/transcribe", response_model=SpeechResponse)
async def transcribe_speech(
    audio: UploadFile = File(...),
    speech_svc: SpeechToTextService = Depends(get_speech_service),
    nlp_svc: NLPParser = Depends(get_nlp_parser),
    maps_svc: MapsService = Depends(get_maps_service),
    settings: Settings = Depends(get_settings)
):
    """
    Transcrit un fichier audio en texte, extrait et confirme la destination.
    """
    try:
        # Logs
        content = await audio.read()
        print(f"📥 Fichier reçu: {audio.filename}")
        print(f"📊 Taille: {len(content)} bytes")
        print(f"📝 Content-Type: {audio.content_type}")
        await audio.seek(0)
    
        
        # Vérification type de fichier
        if not audio.content_type.startswith('audio/'):
            raise HTTPException(
                status_code=400, 
                detail=f"Format de fichier non supporté. Type reçu: {audio.content_type}"
            )
        
        # Lire et vérifier le contenu
        content = await audio.read()
        logger.info(f"Taille du fichier: {len(content)} bytes")
        
        if len(content) > settings.max_audio_size:
            raise HTTPException(
                status_code=413, 
                detail=f"Fichier audio trop volumineux ({len(content)} bytes > {settings.max_audio_size} bytes)"
            )
        
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="Fichier audio vide")
        
        # ✅ CORRECTION: Passer le fichier ET le contenu à transcribe_audio
        transcription = await speech_svc.transcribe_audio(audio, content)
        logger.info(f"Transcription brute: '{transcription}'")
        
        if not transcription or len(transcription.strip()) < 2:
            raise HTTPException(
                status_code=400, 
                detail="Aucune parole détectée dans l'audio. Parlez plus clairement."
            )
        
        # Nettoyage transcription (déjà fait dans transcribe_audio mais on peut nettoyer à nouveau)
        cleaned_text = transcription.lower().strip()
        logger.info(f"Transcription nettoyée: '{cleaned_text}'")
        
        # Extraction destination avec fallback
        destination = nlp_svc.extract_destination(cleaned_text)
        
        # Si NLP échoue, essayer une extraction simple
        if not destination:
            destination = extract_destination_fallback(cleaned_text)
        
        logger.info(f"Destination extraite: '{destination}'")
        
        # Validation destination
        if not destination or not nlp_svc.validate_destination(destination):
            logger.warning(f"Destination invalide ou vide: '{destination}'")
            
            # Fournir des suggestions basées sur la transcription
            suggestions = get_destination_suggestions(cleaned_text)
            
            return SpeechResponse(
                success=False,
                transcription=transcription,
                destination=None,
                confirmation_text=None,
                error=f"Je n'ai pas compris la destination. Dites par exemple: '{suggestions}'"
            )
        
        # Normalisation et phrase de confirmation
        normalized_dest = destination.strip().title()
        
        # Vérifier que le service maps a la méthode
        if not hasattr(maps_svc, 'confirm_destination_text'):
            logger.error("MapsService n'a pas la méthode confirm_destination_text")
            confirmation_text = f"Destination: {normalized_dest}. Voulez-vous continuer ?"
        else:
            confirmation_text = maps_svc.confirm_destination_text(normalized_dest)
        
        logger.info(f"Confirmation à renvoyer: '{confirmation_text}'")
        
        # Retour
        return SpeechResponse(
            success=True,
            transcription=transcription,
            destination=normalized_dest,
            confirmation_text=confirmation_text,
            error=None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Erreur serveur: {str(e)}", exc_info=True)
        return SpeechResponse(
            success=False,
            transcription="",
            destination=None,
            confirmation_text=None,
            error=f"Erreur de traitement: {str(e)}"
        )


def extract_destination_fallback(text: str) -> str:
    """
    Extraction simple de destination en fallback
    """
    if not text:
        return ""
    
    text_lower = text.lower()
    
    # Recherche de mots-clés de lieux
    place_keywords = [
        "mendong", "emia", "nkomo", "nlongkak", "melen", "bastos", "tsinga",
        "mokolo", "odza", "ekounou", "ngoa", "biyem", "mfoundi", "nkolbisson"
    ]
    
    for place in place_keywords:
        if place in text_lower:
            return place
    
    # Recherche après des prépositions
    prepositions = ["à", "au", "aux", "chez", "vers"]
    words = text_lower.split()
    
    for i, word in enumerate(words):
        if word in prepositions and i + 1 < len(words):
            # Prendre le mot suivant comme destination potentielle
            return words[i + 1]
    
    # Sinon, prendre les derniers mots
    if len(words) >= 2:
        return " ".join(words[-2:])
    
    return ""


def get_destination_suggestions(text: str) -> str:
    """
    Génère des suggestions basées sur ce qui a été compris
    """
    suggestions = [
        "Carrefour Émia à Yaoundé",
        "Marché Mendong",
        "Quartier Bastos",
        "Hôpital Central de Yaoundé"
    ]
    
    # Prioriser en fonction du texte
    text_lower = text.lower()
    
    if "carrefour" in text_lower:
        return "Carrefour Émia ou Carrefour Nkomo"
    elif "marché" in text_lower:
        return "Marché Mendong ou Marché Mokolo"
    elif "quartier" in text_lower:
        return "Quartier Bastos ou Quartier Melen"
    elif "hôpital" in text_lower:
        return "Hôpital Central ou Hôpital Général"
    else:
        return "Carrefour Émia, Marché Mendong, ou Quartier Bastos"


@router.post("/confirm", response_model=ConfirmationResponse)
async def confirm_destination(
    audio: UploadFile = File(...),
    speech_svc: SpeechToTextService = Depends(get_speech_service),
    settings: Settings = Depends(get_settings)
):
    """
    Vérifie si l'utilisateur confirme (Oui/Non) la destination.
    
    Retourne:
    - confirmed: True si "oui", False si "non"
    - needs_retry: True si la réponse n'est ni oui ni non
    - message: Message à lire à l'aveugle
    """
    try:
        logger.info(f"Réception confirmation audio: {audio.filename}")
        
        # Vérification type de fichier
        if not audio.content_type.startswith('audio/'):
            raise HTTPException(
                status_code=400, 
                detail=f"Format de fichier non supporté. Type reçu: {audio.content_type}"
            )
        
        # Lire le contenu
        content = await audio.read()
        logger.info(f"Taille du fichier: {len(content)} bytes")
        
        if len(content) > settings.max_audio_size:
            raise HTTPException(
                status_code=413, 
                detail=f"Fichier audio trop volumineux"
            )
        
        if len(content) == 0:
            raise HTTPException(status_code=400, detail="Fichier audio vide")
        
        # Transcription
        transcription = await speech_svc.transcribe_audio(audio, content)
        logger.info(f"Confirmation transcrite: '{transcription}'")
        
        if not transcription or len(transcription.strip()) < 1:
            return ConfirmationResponse(
                confirmed=False,
                needs_retry=True,
                transcription="",
                message="Je n'ai rien entendu. Dites 'Oui' pour confirmer ou 'Non' pour annuler."
            )
        
        # Nettoyer et analyser
        text_clean = transcription.lower().strip()
        
        # Détecter "Oui"
        yes_keywords = ["oui", "oui", "yes", "ok", "d'accord", "daccord", "exactement", 
                        "correct", "parfait", "c'est ça", "c est ca", "vas-y", "vas y",
                        "allons-y", "allons y", "go"]
        
        # Détecter "Non"
        no_keywords = ["non", "no", "pas ça", "pas ca", "pas correct", "mauvais",
                       "ce n'est pas ça", "ce nest pas ca", "annuler", "stop", "arrête"]
        
        # Vérifier si c'est un oui
        if any(keyword in text_clean for keyword in yes_keywords):
            logger.info("✅ Destination confirmée par l'utilisateur")
            return ConfirmationResponse(
                confirmed=True,
                needs_retry=False,
                transcription=transcription,
                message="Parfait ! Lancement de la navigation."
            )
        
        # Vérifier si c'est un non
        if any(keyword in text_clean for keyword in no_keywords):
            logger.info("❌ Destination refusée par l'utilisateur")
            return ConfirmationResponse(
                confirmed=False,
                needs_retry=False,
                transcription=transcription,
                message="D'accord. Quelle est votre destination ?"
            )
        
        # Réponse ambiguë
        logger.warning(f"Réponse ambiguë: '{text_clean}'")
        return ConfirmationResponse(
            confirmed=False,
            needs_retry=True,
            transcription=transcription,
            message=f"Je n'ai pas compris votre réponse. Dites simplement 'Oui' ou 'Non'."
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Erreur confirmation: {str(e)}", exc_info=True)
        return ConfirmationResponse(
            confirmed=False,
            needs_retry=True,
            transcription="",
            message=f"Erreur de traitement. Réessayez en disant 'Oui' ou 'Non'."
        )