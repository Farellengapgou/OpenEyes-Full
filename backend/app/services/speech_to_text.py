import whisper
import tempfile
import os
import shutil
from fastapi import UploadFile, HTTPException
import torch
import re
import librosa
import soundfile as sf
import numpy as np
import noisereduce as nr
import logging

logger = logging.getLogger(__name__)

class SpeechToTextService:
    def __init__(self, model_name: str = "small"):
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        
        logger.info(f"Chargement du modèle Whisper: {model_name} sur {self.device}")
        if self.device == "cuda":
            logger.info(f"✅ GPU CUDA détecté: {torch.cuda.get_device_name(0)}")
        else:
            logger.warning("⚠️ Aucun GPU CUDA détecté. Utilisation du CPU.")
        
        self.check_ffmpeg()
        
        try:
            self.model = whisper.load_model(model_name, device=self.device)
        except RuntimeError as e:
            if "out of memory" in str(e) and self.device == "cuda":
                logger.warning("Mémoire GPU insuffisante. Chargement sur CPU.")
                self.model = whisper.load_model(model_name, device="cpu")
                self.device = "cpu"
            else:
                raise e
            
    def check_ffmpeg(self):
        if not shutil.which("ffmpeg"):
            raise RuntimeError("FFmpeg n'est pas installé")
        logger.info("✓ FFmpeg détecté")

    async def transcribe_audio(self, audio_file: UploadFile, content: bytes = None) -> str:
        """
        Transcrit un fichier audio en texte
        
        Args:
            audio_file: L'objet UploadFile de FastAPI
            content: Les bytes du fichier audio (optionnel, sera lu depuis audio_file si non fourni)
        
        Returns:
            str: La transcription nettoyée
        """
        temp_path = None
        processed_path = None
        
        try:
            # Lire le contenu si non fourni
            if content is None:
                content = await audio_file.read()
            
            if not content or len(content) == 0:
                raise HTTPException(status_code=400, detail="Le fichier audio est vide")
            
            # Créer fichier temporaire
            file_extension = os.path.splitext(audio_file.filename)[1] if audio_file.filename else ".wav"
            with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as temp_file:
                temp_file.write(content)
                temp_path = temp_file.name
            
            logger.info(f"Fichier temporaire créé: {temp_path} ({len(content)} bytes)")
            
            # PRÉTRAITEMENT AUDIO CRITIQUE
            processed_path = self._preprocess_audio(temp_path)
            
            # Prompt optimisé pour Yaoundé
            prompt_hints = """
            Transcription en français des demandes de navigation à Yaoundé.
            Lieux importants: Carrefour Émia, Marché Mendong, Quartier Bastos, Hôpital Central.
            Noms propres: Mendong, Nkomo, Nlongkak, Melen, Tsinga, Odza.
            Exemple: "Je veux aller au marché Mendong"
            """
            
            # Transcription
            logger.info("Début de la transcription Whisper...")
            result = self.model.transcribe(
                processed_path, 
                language="fr", 
                fp16=(self.device == "cuda"),
                initial_prompt=prompt_hints,
                temperature=0.0,  # Moins de créativité, plus de précision
                best_of=3,
                beam_size=3
            )
            
            transcription = result["text"].strip()
            logger.info(f"✅ Transcription brute: '{transcription}'")
            
            # Nettoyage amélioré
            cleaned_transcription = self.clean_transcription(transcription)
            logger.info(f"✅ Transcription nettoyée: '{cleaned_transcription}'")
            
            return cleaned_transcription
            
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"❌ Erreur transcription: {str(e)}", exc_info=True)
            raise HTTPException(status_code=500, detail=f"Erreur de transcription: {str(e)}")
        
        finally:
            # Nettoyage des fichiers temporaires
            for path in [temp_path, processed_path]:
                if path and os.path.exists(path):
                    try:
                        os.unlink(path)
                        logger.debug(f"Fichier temporaire supprimé: {path}")
                    except Exception as cleanup_error:
                        logger.warning(f"Erreur nettoyage fichier {path}: {cleanup_error}")

    def _preprocess_audio(self, audio_path: str) -> str:
        """
        Améliore radicalement la qualité audio avant transcription
        
        Args:
            audio_path: Chemin vers le fichier audio
            
        Returns:
            str: Chemin vers le fichier audio prétraité
        """
        try:
            logger.info("Début du prétraitement audio...")
            
            # Charger l'audio (resample à 16kHz pour Whisper)
            y, sr = librosa.load(audio_path, sr=16000, mono=True)
            logger.info(f"Audio chargé: {len(y)} samples, {sr} Hz")
            
            # 1. Réduction de bruit
            if len(y) > sr:  # Si assez long pour échantillon de bruit (>1s)
                noise_sample = y[:sr]
                y = nr.reduce_noise(y=y, sr=sr, y_noise=noise_sample, prop_decrease=0.9)
                logger.info("✓ Réduction de bruit appliquée")
            
            # 2. Normalisation
            y = librosa.util.normalize(y)
            logger.info("✓ Normalisation appliquée")
            
            # 3. Augmenter volume si trop bas
            rms = np.sqrt(np.mean(y**2))
            if rms < 0.02:
                y = y * 3
                logger.info("✓ Volume augmenté (signal faible détecté)")
            
            # 4. Limiter les pics pour éviter la distorsion
            y = np.clip(y, -0.9, 0.9)
            
            # Sauvegarder le fichier prétraité
            processed_path = audio_path.replace(os.path.splitext(audio_path)[1], "_processed.wav")
            sf.write(processed_path, y, sr)
            logger.info(f"✅ Audio prétraité sauvegardé: {processed_path}")
            
            return processed_path
            
        except Exception as e:
            logger.warning(f"⚠️ Erreur prétraitement audio (utilisation fichier original): {e}")
            return audio_path

    def clean_transcription(self, text: str) -> str:
        """
        Corrections spécifiques pour les requêtes de navigation à Yaoundé
        
        Args:
            text: Texte brut de la transcription
            
        Returns:
            str: Texte nettoyé et corrigé
        """
        if not text:
            return ""
        
        text_lower = text.lower().strip()
        
        # Corrections exhaustives des erreurs courantes
        corrections = {
            # Erreurs courantes "mendong"
            "minced": "mendong",
            "minded": "mendong",
            "mendon": "mendong",
            "mendog": "mendong",
            "mokolung": "mendong",
            "mend ong": "mendong",
            "men don": "mendong",
            "min dong": "mendong",
            
            # "marché"
            "marshe": "marché",
            "marsh": "marché",
            "march e": "marché",
            "marche": "marché",
            "marshé": "marché",
            
            # "carrefour"
            "carulfour": "carrefour",
            "carrefoure": "carrefour",
            "carrefourr": "carrefour",
            "car four": "carrefour",
            "care four": "carrefour",
            
            # Verbes courants
            "j'suis": "je suis",
            "j'veux": "je veux",
            "je veu": "je veux",
            "je vais": "je veux",
            "voudrais": "veux",
            "voudrai": "veux",
            
            # Noms de lieux Yaoundé
            "emia": "emia",
            "emi a": "emia",
            "emiya": "emia",
            "émia": "emia",
            
            "nkomo": "nkomo",
            "n komo": "nkomo",
            "en como": "nkomo",
            
            "nlongkak": "nlongkak",
            "nlong kak": "nlongkak",
            "long kak": "nlongkak",
            
            "bastos": "bastos",
            "basto": "bastos",
            "basteau": "bastos",
            
            "tsinga": "tsinga",
            "tsing a": "tsinga",
            "sing a": "tsinga",
            
            "odza": "odza",
            "od za": "odza",
            "audzat": "odza",
            
            "yaounde": "yaoundé",
            "yaoundé": "yaoundé",
            
            "mokolo": "mokolo",
            "moco lo": "mokolo",
            
            # Phrases complètes typiques
            "je vous grèmes rannées": "je voudrais me rendre",
            "je voudré aller": "je voudrais aller",
            "emmène moi": "emmène-moi",
            "amène moi": "emmène-moi",
        }
        
        # Appliquer toutes les corrections
        for wrong, right in corrections.items():
            text_lower = text_lower.replace(wrong, right)
        
        # Supprimer ponctuation inutile
        text_lower = re.sub(r'[.,!?;:"]', '', text_lower)
        
        # Nettoyer espaces multiples
        text_lower = re.sub(r'\s+', ' ', text_lower).strip()
        
        # Supprimer formules de politesse en fin de phrase
        text_lower = re.sub(
            r'( s\'il vous plaît| svp| merci| please| s\'il te plaît| stp)$', 
            '', 
            text_lower
        ).strip()
        
        return text_lower