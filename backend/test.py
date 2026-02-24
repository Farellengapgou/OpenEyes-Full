from gtts import gTTS
from playsound import playsound
import time
import os

swagger_response = {
    "voice_instructions": [
        "Itinéraire trouvé. Distance 296 mètres. Durée 1 minute.",
        "Début du guidage.",
        "Partez à droite sur Rue 3.383. Marchez environ 12 mètres.",
        "Continuez tout droit sur Rue de Melen pour environ 284 mètres.",
        "Vous êtes arrivé à destination a la soirée."
    ]
}

def speak(text, filename="temp.mp3"):
    # Nettoyage du texte
    clean_text = text.strip().replace('\n', ' ').replace('\r', '')
    tts = gTTS(text=clean_text, lang='fr')
    tts.save(filename)
    playsound(filename)
    os.remove(filename)

for idx, instruction in enumerate(swagger_response["voice_instructions"], start=1):
    print(f"[Instruction {idx}/{len(swagger_response['voice_instructions'])}] {instruction}")
    speak(instruction)
    time.sleep(4)  # pause optionnelle
