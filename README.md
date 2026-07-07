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
