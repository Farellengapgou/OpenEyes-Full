# 🎯 API de Navigation Vocale pour Malvoyants

> Projet d'application mobile Flutter avec backend FastAPI permettant à un utilisateur malvoyant d'obtenir un itinéraire uniquement via commande vocale.

## 📋 Table des matières
- [Vue d'ensemble](#-vue-densemble)
- [Architecture du système](#-architecture-du-système)
- [Comment ça fonctionne](#-comment-ça-fonctionne)
- [Technologies utilisées](#-technologies-utilisées)
- [Structure du projet](#-structure-du-projet)
- [Installation et configuration](#-installation-et-configuration)
- [Utilisation](#-utilisation)
- [Exemples de requêtes](#-exemples-de-requêtes)
- [Points d'amélioration futurs](#-points-damélioration-futurs)

---

## 🎯 Vue d'ensemble

### Problématique
Les utilisateurs malvoyants ont des difficultés à utiliser les applications de navigation classiques qui nécessitent de lire et toucher l'écran. Notre solution permet une interaction **100% vocale**.

### Solution proposée
Une application mobile Flutter qui :
1. ✅ Enregistre la voix de l'utilisateur
2. ✅ Envoie l'audio à un backend intelligent
3. ✅ Reçoit un itinéraire détaillé
4. ✅ Lit les instructions vocalement (text-to-speech)

---

## 🏗 Architecture du système

```
┌─────────────────┐
│  FLUTTER APP    │
│  (Mobile)       │
│                 │
│  1. Micro 🎤    │
│  2. GPS 📍      │
│  3. Haut-parleur🔊│
└────────┬────────┘
         │
         │ HTTP (Audio + GPS)
         │
         ↓
┌─────────────────┐
│  BACKEND API    │
│  (FastAPI)      │
│                 │
│  ┌───────────┐  │
│  │  Whisper  │  │ ← Transcription audio → texte
│  └───────────┘  │
│        ↓        │
│  ┌───────────┐  │
│  │    NLP    │  │ ← Extraction destination
│  └───────────┘  │
│        ↓        │
│  ┌───────────┐  │
│  │ OpenStreet│  │ ← Calcul itinéraire
│  │    Map    │  │
│  └───────────┘  │
└────────┬────────┘
         │
         │ JSON (Itinéraire + Instructions)
         │
         ↓
┌─────────────────┐
│  FLUTTER APP    │
│                 │
│  📱 Affiche carte│
│  🔊 Lecture vocale│
└─────────────────┘
```

---

## 🔄 Comment ça fonctionne

### Étape 1 : Enregistrement vocal (Flutter)
```
Utilisateur : "Emmène-moi à la Poste centrale"
           ↓
      [Enregistrement audio]
           ↓
      Fichier WAV créé
```

### Étape 2 : Envoi au backend
```dart
// Flutter envoie :
{
  audio: fichier.wav,
  origin_lat: 3.8480,    // Position GPS actuelle
  origin_lng: 11.5021
}
```

### Étape 3 : Traitement backend (Python)

#### 3.1 - Transcription (Whisper)
```python
Audio → "emmène-moi à la poste centrale"
```

#### 3.2 - Extraction NLP
```python
"emmène-moi à la poste centrale" → "Poste centrale"
```

#### 3.3 - Géocodage (Nominatim/OpenStreetMap)
```python
"Poste centrale" → {lat: 3.8667, lng: 11.5167}
```

#### 3.4 - Calcul itinéraire (OSRM)
```python
De: (3.8480, 11.5021)
Vers: (3.8667, 11.5167)
    ↓
Itinéraire piéton avec étapes détaillées
```

### Étape 4 : Réponse au frontend
```json
{
  "success": true,
  "destination": "Poste Centrale, Yaoundé",
  "route": {
    "total_distance": "2.3 km",
    "total_duration": "28 minutes",
    "steps": [
      {
        "instruction": "Partez sur Avenue Kennedy",
        "distance": "450 m",
        "duration": "5 min"
      },
      {
        "instruction": "Tournez à droite sur Rue de la Poste",
        "distance": "300 m",
        "duration": "4 min"
      }
    ]
  },
  "voice_instructions": [
    "Itinéraire trouvé. Distance totale: 2.3 km. Durée: 28 minutes.",
    "Étape 1: Partez sur Avenue Kennedy. 450 m.",
    "Étape 2: Tournez à droite sur Rue de la Poste. 300 m.",
    "Vous êtes arrivé à destination."
  ]
}
```

### Étape 5 : Lecture vocale (Flutter)
```
🔊 "Itinéraire trouvé. Distance totale: 2 kilomètres 3..."
🔊 "Étape 1: Partez sur Avenue Kennedy..."
🔊 "Étape 2: Tournez à droite..."
```

---

## 🛠 Technologies utilisées

### Backend (FastAPI)
| Technologie | Rôle | Pourquoi |
|------------|------|----------|
| **FastAPI** | Framework web | Rapide, moderne, documentation auto |
| **Whisper (OpenAI)** | Speech-to-text | Précision élevée, multilingue, offline |
| **OpenStreetMap** | Cartographie | Gratuit, open source, mondial |
| **OSRM** | Calcul d'itinéraire | Rapide, gratuit, itinéraires piétons |
| **Nominatim** | Géocodage | Convertit adresses en GPS |

### Frontend (Flutter)
| Package | Rôle |
|---------|------|
| **record** | Enregistrement audio |
| **http** | Communication API |
| **flutter_tts** | Text-to-speech |
| **geolocator** | GPS |

---

## 📁 Structure du projet

```
openn/
├── app/
│   ├── main.py                    # 🚀 Point d'entrée de l'API
│   ├── config.py                  # ⚙️ Configuration (variables env)
│   │
│   ├── routes/                    # 🛣️ Endpoints API
│   │   ├── speech.py              #    → POST /speech/transcribe
│   │   └── navigation.py          #    → POST /navigation/voice-navigation
│   │
│   ├── services/                  # 🧠 Logique métier
│   │   ├── speech_to_text.py      #    → Service Whisper
│   │   ├── nlp_parser.py          #    → Extraction de destination
│   │   └── maps_service.py        #    → OpenStreetMap + OSRM
│   │
│   └── models/                    # 📦 Modèles de données
│       ├── request_models.py      #    → Structures des requêtes
│       └── response_models.py     #    → Structures des réponses
│
├── requirements.txt               # 📋 Dépendances Python
├── .env                          # 🔐 Variables d'environnement
└── README.md                     # 📖 Ce fichier
```

### Détail des fichiers clés

#### `app/main.py`
- Initialise FastAPI
- Configure CORS pour Flutter
- Enregistre les routes

#### `app/services/speech_to_text.py`
- Charge le modèle Whisper
- Transcrit les fichiers audio
- Gère les fichiers temporaires

#### `app/services/nlp_parser.py`
- Détecte les mots-clés ("aller à", "emmène-moi")
- Extrait la destination du texte transcrit
- Nettoie et valide la destination

#### `app/services/maps_service.py`
- **Géocodage** : Adresse → Coordonnées GPS
- **Routing** : Calcule l'itinéraire piéton
- **Traduction** : Instructions en français

---

## 🚀 Installation et configuration

### Prérequis
- Python 3.8+
- FFmpeg (pour Whisper)
- Connexion Internet

### 1. Installation FFmpeg

**Windows :**
```bash
# Télécharger depuis https://ffmpeg.org/download.html
# Ajouter au PATH système
```

**Ubuntu/Debian :**
```bash
sudo apt update
sudo apt install ffmpeg
```

**macOS :**
```bash
brew install ffmpeg
```

### 2. Configuration du projet

```bash
# Cloner/télécharger le projet
cd C:\Users\COMPUTER-CARE\Desktop\openn

# Créer environnement virtuel
python -m venv venv

# Activer l'environnement
# Windows PowerShell:
venv\Scripts\Activate.ps1
# Windows CMD:
venv\Scripts\activate.bat

# Installer les dépendances
pip install -r requirements.txt
```

### 3. Configuration `.env`

Créer un fichier `.env` à la racine :

```env
# Modèle Whisper (tiny/base/small/medium/large)
WHISPER_MODEL=base

# Taille max audio (10MB)
MAX_AUDIO_SIZE=10485760

# User agent pour OpenStreetMap
NOMINATIM_USER_AGENT=navigation_vocale_yaunde_v1
```

### 4. Premier lancement

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**⚠️ Au premier lancement :**
- Whisper téléchargera son modèle (~140 MB pour "base")
- Cela peut prendre 2-5 minutes

**✅ Si tout fonctionne :**
```
INFO:     Uvicorn running on http://0.0.0.0:8000
INFO:     Application startup complete.
```

Ouvrir : `http://localhost:8000/docs`

---

## 💻 Utilisation

### API Endpoints

#### 1. Test simple : Transcription seule
```http
POST http://localhost:8000/speech/transcribe
Content-Type: multipart/form-data

audio: [fichier.wav]
```

**Réponse :**
```json
{
  "success": true,
  "transcription": "emmène-moi à la poste centrale",
  "destination": "poste centrale"
}
```

#### 2. Endpoint principal : Navigation complète
```http
POST http://localhost:8000/navigation/voice-navigation
Content-Type: multipart/form-data

audio: [fichier.wav]
origin_lat: 3.8480
origin_lng: 11.5021
```

**Réponse :** Itinéraire complet (voir exemple JSON plus haut)

#### 3. Itinéraire sans audio (texte direct)
```http
POST http://localhost:8000/navigation/get-route
Content-Type: application/json

{
  "origin_lat": 3.8480,
  "origin_lng": 11.5021,
  "destination": "Poste centrale"
}
```

---

## 🧪 Exemples de requêtes

### Avec cURL

```bash
# 1. Transcription
curl -X POST "http://localhost:8000/speech/transcribe" \
  -F "audio=@test_audio.wav"

# 2. Navigation vocale
curl -X POST "http://localhost:8000/navigation/voice-navigation" \
  -F "audio=@commande.wav" \
  -F "origin_lat=3.8480" \
  -F "origin_lng=11.5021"

# 3. Itinéraire texte
curl -X POST "http://localhost:8000/navigation/get-route" \
  -H "Content-Type: application/json" \
  -d '{
    "origin_lat": 3.8480,
    "origin_lng": 11.5021,
    "destination": "Université de Yaoundé"
  }'
```

### Avec Python (pour tests)

```python
import requests

# Envoyer un audio
with open("commande.wav", "rb") as audio:
    response = requests.post(
        "http://localhost:8000/navigation/voice-navigation",
        files={"audio": audio},
        data={
            "origin_lat": 3.8480,
            "origin_lng": 11.5021
        }
    )
    print(response.json())
```

---

## 📊 État d'avancement

### ✅ Fonctionnalités implémentées
- [x] Transcription audio en texte (Whisper)
- [x] Extraction intelligente de destination
- [x] Géocodage avec OpenStreetMap
- [x] Calcul d'itinéraire piéton
- [x] Génération d'instructions vocales
- [x] API REST complète
- [x] Documentation automatique (Swagger)

### 🔄 En cours d'intégration
- [ ] Interface Flutter complète
- [ ] Affichage carte interactive
- [ ] Suivi GPS en temps réel

### 🎯 Points d'amélioration futurs

#### Court terme
- [ ] Support multi-langues (anglais, français)
- [ ] Gestion des erreurs de connexion
- [ ] Cache des destinations fréquentes
- [ ] Mode hors-ligne partiel

#### Moyen terme
- [ ] Navigation en temps réel (étape par étape)
- [ ] Détection automatique de la langue
- [ ] Points d'intérêt à proximité
- [ ] Historique des trajets

#### Long terme
- [ ] Intégration transport en commun
- [ ] Alertes vocales (obstacles, virages)
- [ ] Communauté d'utilisateurs
- [ ] Base de données de lieux accessibles

---

## 🎓 Concepts techniques expliqués

### Whisper (Speech-to-Text)
Modèle d'IA d'OpenAI qui convertit la parole en texte. Fonctionne en local (pas besoin d'Internet après téléchargement).

**Modèles disponibles :**
- `tiny` : 39M paramètres, rapide, moins précis
- `base` : 74M paramètres, **recommandé**
- `small` : 244M paramètres, très précis
- `medium` : 769M paramètres, lent mais excellent
- `large` : 1550M paramètres, meilleur mais très lent

### OpenStreetMap vs Google Maps

| Critère | OpenStreetMap | Google Maps |
|---------|---------------|-------------|
| Coût | **Gratuit** | Payant après quota |
| Données | Open source | Propriétaire |
| Précision | Bonne (dépend de la zone) | Excellente |
| Hors-ligne | Possible | Limité |
| Vie privée | Respectée | Tracking |

### OSRM (Open Source Routing Machine)
Moteur de calcul d'itinéraire ultra-rapide. Optimisé pour piétons, vélos, voitures.

---

## ⚠️ Limitations actuelles

### Techniques
- **Whisper** : Nécessite FFmpeg installé
- **OpenStreetMap** : 1 requête/seconde max (Nominatim)
- **Audio** : Limité à 10 MB par fichier
- **Réseau** : Nécessite connexion Internet

### Fonctionnelles
- Pas de navigation turn-by-turn en temps réel
- Pas de recalcul automatique si déviation
- Supporte uniquement le français actuellement
- Pas de mode hors-ligne complet

---

## 🐛 Résolution de problèmes

### Erreur : "FFmpeg not found"
```bash
# Installer FFmpeg et vérifier
ffmpeg -version
```

### Erreur : "Too many requests" (429)
OpenStreetMap limite à 1 requête/seconde. Ajouter un délai :
```python
import time
time.sleep(1)
```

### Whisper très lent
- Utiliser le modèle `tiny` ou `base`
- Vérifier si GPU est utilisé
- Réduire la qualité audio (16kHz mono)

### Destination non trouvée
- Soyez plus précis ("Poste Centrale Yaoundé" au lieu de "Poste")
- Ajoutez la ville
- Vérifiez l'orthographe

---

## 📞 Contact & Contribution

**Équipe projet :**  
Développement backend : [Votre nom]  
Intégration Flutter : [Nom collègue]

**Pour contribuer :**
1. Fork le projet
2. Créer une branche (`git checkout -b feature/amelioration`)
3. Commit (`git commit -m 'Ajout fonctionnalité'`)
4. Push (`git push origin feature/amelioration`)
5. Créer une Pull Request

---

## 📄 Licence

Projet éducatif - ENSP Yaoundé 2024-2025  
Destiné à l'assistance aux personnes malvoyantes.

---

**Dernière mise à jour :** 06 Décembre 2024  
**Version :** 1.0.0  
**Status :** En développement actif 🚧