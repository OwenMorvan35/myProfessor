# Cours AI – Backend Go + Front Flutter

## Pré-requis

- Go 1.22+
- Flutter 3.19+
- `ffmpeg` (pour certains formats audio éventuels)
- Node facultatif (pas utilisé ici)

## Configuration .env

Créez un fichier `.env` à partir de `.env.example` :

```
API_BASE_URL=http://localhost:8080/api
SHARE_OPEN_IN_BROWSER=true
```

## Backend (Go)

```bash
cd myProfessor
make run              # lance l'API sur http://localhost:8080
```

Endpoints clés :
- `GET /api/health`
- `POST /api/folders/:id/documents/upload`
- `POST /api/documents/:id/pdf`
- `POST /api/documents/:id/share`

## Front Flutter

```
flutter create --platforms=web .     # première fois seulement
cp .env.example .env
flutter pub get
```

### Lancement

- Web : `flutter run -d chrome`
- iOS : `open ios/Runner.xcworkspace` puis `flutter run`
- Android : `flutter run -d android`

## Permissions

### iOS (Info.plist)
```
<key>NSMicrophoneUsageDescription</key>
<string>Cette application nécessite l'accès au micro pour enregistrer les cours.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Permet de sauvegarder les enregistrements.</string>
```

### Android (AndroidManifest.xml)
```
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

## Fonctionnalités clés

- Liste de dossiers (Hive + Riverpod)
- Upload/enregistrement audio → transcription (OpenAI) + résumé
- Génération PDF + partage (URLs signées)
- Aperçu PDF mobile (option : package `printing`) à intégrer si besoin
