# 🦯 Navigation Vocale - App Mobile

Application mobile Flutter de navigation vocale pour personnes malvoyantes à Yaoundé (Cameroun).

## 📱 Fonctionnalités

- ✅ **Navigation vocale** complète
- ✅ **Reconnaissance vocale** (transcription audio)
- ✅ **Confirmation Oui/Non** intelligente
- ✅ **Navigation GPS temps réel** avec instructions audio
- ✅ **Interface accessible** pour malvoyants
- ✅ **Support Bluetooth** (pour canne GSM 8008)

## 🎯 Captures d'écran

[TODO: Ajouter screenshots]

## 🔧 Installation Développement

### Prérequis
- Flutter SDK 3.0+
- Android Studio / VS Code
- Android SDK (pour Android)
- Xcode (pour iOS - Mac uniquement)

### Setup
```bash
# 1. Cloner le repo
git clone https://github.com/TASSEAROLE/blind-navigation-app.git
cd blind-navigation-app

# 2. Installer dépendances
flutter pub get

# 3. Configurer l'API Backend
# Modifier services/api_service.dart
# Remplacer baseUrl par votre URL backend

# 4. Lancer sur émulateur/device
flutter run
```

## 📦 Build APK
```bash
# Debug APK
flutter build apk --debug

# Release APK (production)
flutter build apk --release

# APK sera dans : build/app/outputs/flutter-apk/
```

## 🔑 Configuration

### Backend API
Modifier `lib/services/api_service.dart` :
```dart
static const String baseUrl = 'VOTRE_URL_BACKEND';
```

### Permissions Android
L'app demande :
- 🎤 Microphone (enregistrement audio)
- 📍 Localisation (GPS navigation)
- 🔵 Bluetooth (canne connectée)

## 📱 Installation sur Téléphone

### Via APK Direct
1. Télécharger `app-release.apk`
2. Activer "Sources inconnues" dans Paramètres
3. Installer l'APK
4. Autoriser permissions

### Via Play Store
[TODO: Lien Play Store]

## 🏗️ Architecture
```
lib/
├── main.dart              # Point d'entrée
├── services/
│   └── api_service.dart   # Communication backend
└── screens/
    └── navigation_screen.dart  # Écran principal
```

## 🧪 Tests
```bash
# Tests unitaires
flutter test

# Tests d'intégration
flutter drive --target=test_driver/app.dart
```

## 🚀 Déploiement

### Android
1. Build APK release
2. Upload sur Play Store Console
3. Soumettre pour review

### iOS
1. Build iOS release (nécessite Mac + compte Apple Developer)
2. Upload sur App Store Connect
3. Soumettre pour review

## 🤝 Contribution

Les contributions sont bienvenues !
1. Fork le projet
2. Créer une branche (`git checkout -b feature/nouvelle-fonctionnalite`)
3. Commit (`git commit -m 'Ajout nouvelle fonctionnalité'`)
4. Push (`git push origin feature/nouvelle-fonctionnalite`)
5. Ouvrir une Pull Request

## 📝 Changelog

### v1.0.0 (2024)
- ✅ Navigation vocale de base
- ✅ Transcription audio avec Whisper
- ✅ GPS temps réel
- ✅ Instructions vocales

## 📄 Licence

MIT

## 👥 Auteurs

- [@TASSEAROLE](https://github.com/TASSEAROLE)

## 🔗 Liens

- Backend API: [blind-navigation-backend](https://github.com/TASSEAROLE/blind-navigation-backend)
- Documentation: [Wiki](https://github.com/TASSEAROLE/blind-navigation-app/wiki)

## 💡 Support

Pour bugs ou questions, ouvrir une [issue](https://github.com/TASSEAROLE/blind-navigation-app/issues).