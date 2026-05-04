# Strikezone

Applicazione Flutter + Firebase (Auth, Firestore multi-database, Functions, Storage) con supporto esplicito a:
- esecuzione locale su Firebase Emulator Suite
- switch pulito verso ambiente live (Firebase project reale)

## Prerequisiti

- Flutter SDK installato
- Firebase CLI installata (`firebase --version`)
- Python 3.11 per Cloud Functions (`functions/`)

## Esecuzione in Emulator (default)

1. Avvia emulatori:

```bash
firebase emulators:start --import=./emulator_data --export-on-exit=./emulator_data
```

2. Avvia app Flutter in ambiente emulator:

```bash
flutter run --dart-define=APP_ENV=emulator
```

Opzionale (override host/porte):

```bash
flutter run \
  --dart-define=APP_ENV=emulator \
  --dart-define=FIREBASE_EMULATOR_HOST=localhost \
  --dart-define=FIREBASE_AUTH_EMULATOR_PORT=9099 \
  --dart-define=FIREBASE_FIRESTORE_EMULATOR_PORT=8080 \
  --dart-define=FIREBASE_FUNCTIONS_EMULATOR_PORT=5001 \
  --dart-define=FIRESTORE_DATABASE_ID=strikezonedb
```

## Switch a Firebase Live

Per puntare al backend live non serve modificare codice: basta cambiare environment.

```bash
flutter run --dart-define=APP_ENV=live
```

Per build web:

```bash
flutter build web --dart-define=APP_ENV=live
```

## Variabili Runtime supportate

- `APP_ENV`: `emulator` | `live` (default `emulator`)
- `FIREBASE_EMULATOR_HOST`: host emulator (default auto: `10.0.2.2` su Android, altrimenti `localhost`)
- `FIREBASE_AUTH_EMULATOR_PORT` (default `9099`)
- `FIREBASE_FIRESTORE_EMULATOR_PORT` (default `8080`)
- `FIREBASE_FUNCTIONS_EMULATOR_PORT` (default `5001`)
- `FIREBASE_FUNCTIONS_REGION` (default `us-central1`)
- `FIRESTORE_DATABASE_ID`
  - default automatico: `(default)` in emulator, `strikezonedb` in live
  - override possibile con `--dart-define=FIRESTORE_DATABASE_ID=...`

## Note Functions (Python)

Le Cloud Functions leggono variabili ambiente per evitare hardcode:
- `FIRESTORE_DATABASE_ID` (stessa logica: default emulator `(default)`, live `strikezonedb`)
- `STORAGE_BUCKET` (default `${GCLOUD_PROJECT}.firebasestorage.app`)
