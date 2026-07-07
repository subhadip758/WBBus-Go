# West Bengal Smart Bus

A crowdsourced bus search and real-time ride tracking application for West Bengal inter-city routes.

This repository contains two related projects:

- `wbsb/`: Flutter mobile app with offline route search and Firebase-backed live passenger tracking.
- `wbsb_web/`: Capacitor-based web app scaffold, including the web frontend and native Android wrapper files.

## Key Features

- Search buses by source, destination, route, registration number, operator, agency, or intermediate stop.
- Offline dataset bundled in JSON assets and cached with Hive.
- Live tracking using passenger GPS contributions via Firebase Firestore.
- Route progress, ETA, and delay estimation from crowdsourced location fixes.
- OpenStreetMap-based map support through `flutter_map`.

## Repository Structure

- `wbsb/`
  - `lib/`
    - `core/` — constants and utility helpers
    - `data/` — JSON models, datasources, repository implementations
    - `domain/` — entities, repository interfaces, use cases
    - `presentation/` — providers, screens, widgets
  - `assets/data/` — normalized route data JSON files
  - `firebase/` — Firestore rules and index configuration
  - `test/` — unit tests for location resolution logic
  - `pubspec.yaml` — Flutter and dependency configuration

- `wbsb_web/`
  - `src/` — React-like web frontend source
  - `public/` — static web assets and data files
  - `android/` — Capacitor Android wrapper configuration
  - `package.json`, `vite.config.js` — web build toolchain

## Data and Provenance

The app uses curated dataset files under `wbsb/assets/data/` and `wbsb_web/public/data/`:

- `buses.json`
- `routes.json`
- `stops.json`
- `timetable.json`
- `operators.json`
- `agencies.json`

The Flutter app joins these datasets at runtime to build route, stop, timetable, and bus entities.

## How to Build and Run

### Flutter app (`wbsb/`)

1. Install Flutter SDK and required platform tooling.
2. Open `wbsb/` in your editor or terminal.
3. Run:

```bash
cd wbsb
flutter pub get
flutter analyze
flutter run
```

If you are targeting Android or iOS, make sure the device/emulator is available and configured.

### Web app (`wbsb_web/`)

1. Install Node.js and npm.
2. Open `wbsb_web/` in your terminal.
3. Run:

```bash
cd wbsb_web
npm install
npm run dev
```

For Android wrapper builds, use Capacitor commands after validating the web app.

## Firebase and Live Tracking

The Flutter app uses Firebase for:

- anonymous authentication
- Firestore live ride session writes

Firestore paths include:

- `ride_sessions/{busId}/active/{sessionId}`
- `buses/{busId}` (reserved for future use)

The app resolves multiple passenger GPS contributions into a trusted bus location and calculates trip progress from that resolved position.

## Notes

- `wbsb/README.md` contains detailed architecture notes, data provenance, and known limitations.
- This root README is intended to provide a quick orientation to the repository and the two contained apps.

## License

This repository does not include a license file. Add one if you intend to publish or share this project publicly.
# WBBus Go 🚌
**WBBus Go** is a premium, real-time smart bus tracking and prediction system for West Bengal. It combines live passenger crowdsourcing, Leaflet mapping overlays, and a resilient real-world historical travel time fallback engine. The application is packaged as both a responsive web application and a native Android mobile app using Ionic Capacitor.
---
## Key Features
1. **Automatic Geolocation & User Pinning**
   - Promptly requests location access on startup.
   - Centers the map view on the passenger's current position and places a blue user pin marker.
   - Displays live GPS coordinates (Lat, Lng) inside the main panel.
2. **Smart Search & Advanced Collapsible Filters**
   - Quick search by bus name, operator, registration number, or route stops.
   - Collapsible Boarding & Destination filters (saves screen space on mobile viewports).
3. **Live Passenger Crowdsourcing Simulator**
   - Simulates single or multiple passengers riding the bus (crowdsourcing).
   - Speed multipliers ($1x$ to $10x$), movement pause/resume button, and custom device accuracy sliders.
4. **Resilient Geolocation Fallback Engine**
   - **GPS Signal Outage Detection**: Automatically switches to the fallback travel engine if the GPS signal is lost or watch coordinates stall for $>8$ seconds.
   - **Piecewise Linear Interpolation**: Extrapolates missing segments and linear-interpolates skipped stops.
   - **Timetable-Based ETA Projection**: Computes real-world speed (~35 km/h) based on bus scheduled up-times, generating steadily decreasing, accurate ETAs rather than simulated timer ticks.
   - **Sanitized Coordinates**: Enforces strict monotonic time-checks on previous runs to prevent backwards coordinates jumps.
5. **Destination Status & Auto Lock**
   - Displays a green **Reached Destination** alert when within 300 meters of the terminus.
   - Locks the simulation index and pauses the movement loop.
6. **Custom Branding**
   - Packed with custom favicon, logo images, and mobile launcher app icons generated using `@capacitor/assets`.
---
## Tech Stack
* **Frontend**: React (Vite), Leaflet Map (react-leaflet), Lucide Icons
* **Mobile Wrapper**: Ionic Capacitor
* **Database / Syncer**: Firebase Firestore (Anonymous Auth & real-time sync)
* **Branding Assets Generator**: `@capacitor/assets`
---
## Folder Structure
* [/wbsb](file:///c:/Users/Subhadip/Downloads/west_bengal_smart_bus/wbsb) - Flutter/Dart core modules, repositories, scraper parsers, and data ingestion models.
* [/wbsb_web](file:///c:/Users/Subhadip/Downloads/west_bengal_smart_bus/wbsb_web) - The main Vite + React frontend web app and native Android project wrapper.
---
## Getting Started
### Prerequisites
* **Node.js** (v18+)
* **Java JDK 21 & Android Studio** (for building the Android APK)
### Run Web App Locally
1. Navigate to the web folder:
   ```bash
   cd wbsb_web
   ```
2. Install dependencies:
   ```bash
   npm install
   ```
3. Expose the dev server (so you can test it on your phone):
   ```bash
   npm run dev -- --host
   ```
### Compile & Install Native Android App on Connected Phone (USB Debugging)
1. Turn on **Developer Mode** and enable **USB Debugging** on your Android phone.
2. Plug your phone into your computer over USB and allow authorization.
3. Sync web assets:
   ```bash
   npm run build
   npx cap sync
   ```
4. Build the native APK package and install it on your phone:
   ```bash
   # Windows PowerShell
   $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
   cd android
   ./gradlew.bat assembleDebug
   cd ..
   & "C:\Users\Subhadip\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "android/app/build/outputs/apk/debug/app-debug.apk"
   ```
