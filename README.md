# Diagnosis Outpost

A cross-platform civic health tool that helps individuals and communities detect, understand, and respond to infectious disease outbreaks.

## Features

- **Outbreak map** with public health data and community trend charts
- **AI-assisted risk check** using symptoms, vitals, optional cough audio, and optional photo input
- **Outbreak Intel** educational cards with scientific imagery, molecular structures, and AR/3D models
- **Anonymous opt-in community signals** to strengthen local outbreak awareness
- **Agency dashboard demo** showing aggregated signals and recommended actions

## Important disclaimer

Diagnosis Outpost is an **informational triage and civic awareness tool**, not a medical diagnostic device. It provides risk scores and educational guidance only. Always consult a qualified healthcare provider for personal medical concerns.

## Tech stack

- **Frontend:** Flutter 3.x (Android, iOS, Web)
- **State management:** Riverpod
- **Backend:** Python / FastAPI
- **Cloud:** GCP Cloud Run (backend), Firebase Hosting (web demo)
- **DNS / CDN:** Cloudflare
- **Maps & charts:** flutter_map, fl_chart
- **3D / AR:** model_viewer_plus
- **ML:** TensorFlow Lite on Android/iOS; optional cloud inference on web with explicit opt-in (media is processed in memory and not stored)

## Project structure

```
lib/                  Flutter source code
backend/              FastAPI backend
assets/content/       Educational content and outbreak data
assets/images/        Scientific images and micrographs
assets/models/        3D / AR models and on-device TFLite classifiers
assets/audio/         Audio samples and prompts
test/                 Flutter widget and unit tests
```

## Getting started

### Flutter app

```bash
flutter pub get
flutter run
flutter test
flutter build web --release
flutter build apk --release
```

### Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
# Install the Python dependencies your environment requires,
# then start the development server:
uvicorn app.main:app --reload
```

## Privacy

- No personal identifiers are collected.
- Raw audio recordings and photos stay on the device unless the user explicitly opts in.
- Location is coarse-grained (region/county level).
- Community signals are anonymized and aggregated before storage.


