from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    # Application
    app_name: str = "Navigation Vocale API pour Malvoyants"
    environment: str = "development"
    
    # Whisper - MODÈLE OPTIMAL (compromis précision/vitesse)
    whisper_model: str = "small"  # Meilleur choix pour app mobile temps réel
    
    # Audio
    max_audio_size: int = 5 * 1024 * 1024  # 5MB max pour mobile
    
    # Services externes
    nominatim_user_agent: str = "NavigationVocaleMalvoyants/1.0"
    
    # Flutter
    flutter_app_name: str = "Navigation Yaoundé"
    
    class Config:
        env_file = ".env"

@lru_cache()
def get_settings() -> Settings:
    return Settings()