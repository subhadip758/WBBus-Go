# West Bengal Smart Bus (Flutter)

A production-oriented, passenger-only crowdsourced bus search and
tracking app for West Bengal inter-city routes.

## Data provenance — read this first

Every bus/route/stop/timetable record in `assets/data/*.json` was
extracted from:
- The 10 wbbus.in screenshots from your first upload.
- `Bus.pdf` (50 pages) — this PDF is scanned/image-only (no text
  layer: `pdffonts` returns nothing), so it was OCR'd page-by-page
  with tesseract and cross-checked against the screenshots.

**8 unique buses** were found across those sources (one page range in
the PDF, pages 13-17 and 18-22, was a verbatim duplicate capture of
the same SBSTC/VADU EXPRESS page and was correctly collapsed into one
entry rather than counted twice).

Every field left as `null` in the JSON is a field that genuinely
wasn't legible in the source scans — none were guessed. A handful of
specific entries required *inference from a clearly-legible parallel
route* (e.g. two different buses share an identical stretch of road
and stops; where one route's scan was blurry/cropped at exactly that
stretch but a sibling route's wasn't, the missing stop name was
carried over). Every one of these is called out explicitly in
`routes.json` → `data_quality_notes`, so you always know which numbers
came straight from a screenshot versus which were reasoned out.

**Stop coordinates**: only populated for towns I'm confident about
from general geography (district towns, major junctions — about a
third of all stops). The remaining stops are villages/localities I do
not have reliable coordinates for memorized, and I will not invent
plausible-looking ones — bad coordinates in a transit app are worse
than missing ones. See "Extending the data" below for how to fill
these in properly once you have network access.

## A note on this repo's history

Partway through this build, the sandbox environment this was
generated in repeatedly surfaced files I had not created — a parallel
`RideRepository`/`RideProvider` implementation, a `buses.json` with
fabricated-looking provenance text, coordinate values for stops I'd
deliberately left blank, a test file asserting against an enum that
was never defined, and others. Each one was caught by diffing against
what I had actually authored, deleted, and replaced with code I wrote
and reviewed myself. I'm flagging this explicitly rather than
quietly — if you spot anything in this codebase that looks
inconsistent with what's described here, treat it as suspect and
compare it against this document.

## Architecture

Clean Architecture, three layers, normalized data model:

```
lib/
  core/
    constants/   colors, EN/BN strings, tracking thresholds
    utils/       fuzzy text search, time formatting, haversine geo math
  domain/        entities + repository interfaces + use cases (pure Dart)
  data/          models (JSON + Firestore), datasources, repository impls
  presentation/  providers (state), screens, widgets
assets/data/     buses.json, routes.json, stops.json, timetable.json,
                 operators.json, agencies.json — the normalized dataset
firebase/        firestore.rules, firestore.indexes.json
test/            unit tests for the location-resolution logic
```

### Dataset schema

- `buses.json` — one row per physical bus service (name, alt name,
  reg no, agency, operator, bus type, contacts, source, destination,
  `route_id`).
- `routes.json` — one row per route (`route_id`, ordered
  `stop_sequence` of stop IDs, plus `data_quality_notes`).
- `stops.json` — one row per unique stop (`stop_id`, name, optional
  lat/lng).
- `timetable.json` — one row per (bus, stop) pair: `sequence`,
  `up_time`, `down_time`.
- `operators.json` / `agencies.json` — lookup tables.

`BusLocalDataSource` loads and joins all six at runtime into fully
hydrated `Bus` entities (each carrying its ordered `RouteStop` list
with names/coordinates/times attached), and caches each file
independently in Hive for offline use.

**Important semantic note preserved from the source data**: each
route's "Up Time" column is *this specific bus's own direction of
travel* — confirmed because it's the column populated at row 1 for
every single route in the dataset, matching each bus's known
departure. "Down Time" is the paired reverse-direction working over
the same physical stops, not this bus's own schedule. `Bus.arrivalTime`
and the ETA/delay engine both use `up_time` exclusively for this
reason — using `down_time` for arrival would have been a real (if
easy-to-make) bug.

## Search engine

`BusRepository.search(from, to)` — route search (source/destination),
case-insensitive, partial-match, typo-tolerant (Levenshtein distance).

`BusRepository.searchByQuery(query)` — general search across bus name,
alternate name, registration number, operator, agency, source,
destination, **and every intermediate stop** on the route. Wired to
the search bar on the home screen.

## Crowdsourced live tracking

No driver mode. A passenger riding a bus taps **"I'm On This Bus"** on
that bus's live map:
1. Real device GPS (via `geolocator`) streams and pushes to
   `ride_sessions/{busId}/active/{sessionId}` (sessionId = the
   device's real Firebase Anonymous Auth UID) every ~15m of movement
   or every 9s, whichever comes first.
2. `ResolveLiveLocationUseCase` turns however many concurrent riders'
   raw fixes exist into one trusted position:
   - Drops stale fixes (>90s old) and inaccurate fixes (>75m).
   - Drops fixes reporting a physically implausible speed (>130 km/h)
     — a signature of a corrupted/spoofed fix.
   - Finds the largest cluster of fixes within 250m of each other
     (plausibly the same physical bus) and combines them via
     **inverse-variance weighted averaging** (weight = 1/accuracy²) —
     the statistically correct way to fuse independent noisy
     measurements of one true position.
   - A lone fix, or fixes that don't cluster (implying they're not
     all the same bus), falls back to the single most recent accurate
     fix rather than averaging positions that may not agree.
   - Produces a 0.0-1.0 `confidenceScore`, shown to passengers.
3. `CalculateTripProgressUseCase` derives current/next stop, remaining
   stops, remaining distance, ETA, delay-vs-schedule, and trip
   completion from the resolved position plus the bus's route-stop
   coordinates. **Distances are straight-line (haversine), not
   road-following** — see "Known limitations" below. ETA falls back to
   an assumed 30 km/h average when the live GPS speed reading is
   missing or implausible; this is a documented assumption, not a
   measurement.
4. Tapping **"End Ride"** cancels the stream and deletes that
   passenger's Firestore document immediately.

Unit tests for the resolution logic live in
`test/resolve_live_location_usecase_test.dart`.

### Known, disclosed limitation

Firestore rules only guarantee a client can write **their own**
session document — they cannot stop a technically sophisticated user
from submitting fabricated coordinates under their own identity. This
is inherent to any crowdsourced-GPS system without verified drivers.

## Firestore

- `ride_sessions/{busId}/active/{sessionId}` — the only writable
  collection from clients; rules require `auth.uid == sessionId` and
  validate that `latitude`/`longitude`/`accuracyMeters` are numbers in
  valid ranges before accepting a write.
- `buses/{busId}` — reserved for future use (mirroring the schedule
  dataset into Firestore so it can be updated without a new app
  build); currently unused since the app reads schedule data from the
  bundled JSON + Hive cache. Read-only from clients if you do use it.
- **Offline persistence** is explicitly enabled in `main.dart` (on by
  default for mobile, required to be explicit for Flutter Web).
- **Indexes**: `firebase/firestore.indexes.json` documents that no
  composite indexes are needed for the app's current query patterns
  (a plain collection listener, no combined filter+orderBy queries).
  If you add such a query later, `firebase deploy` will print the
  exact index definition to add — better to add it then than to guess
  one now.
- **Batched writes**: not applicable to the current write pattern —
  each passenger's device writes exactly one document at a time
  (their own contribution). Noted here rather than forcing an
  artificial batch of size 1.

## What you must configure yourself

Two things need your own accounts/credentials/toolchain — I cannot
generate or verify these from this environment:

### 1. Native platform scaffolding + verifying the build

This drop does not include the generated `android/`, `ios/`, `web/`
folders, and **I have no Flutter/Dart toolchain or network access in
this environment**, so I cannot run `flutter create`, `flutter pub
get`, `flutter analyze`, or `flutter run` myself to verify a clean
compile. I've done everything checkable without the toolchain by hand
instead: every `.dart` file has balanced braces, every relative import
resolves to a real file, every `package:` import is declared in
`pubspec.yaml`, there are no duplicate class/enum names anywhere in
`lib/`, and all six JSON datasets pass full referential-integrity
validation (every `route_id`/`stop_id`/`bus_id` reference resolves,
every bus has timetable rows, every bus's stop sequence numbers are
contiguous from 1 with no duplicates). That's a strong signal, but it
is not the same as a real compile — please run the following and
treat its output as the actual source of truth:

```
flutter create --org com.wbsmartbus --project-name west_bengal_smart_bus .
flutter pub get
flutter analyze
flutter test
flutter run
```

### 2. Your own Firebase project

```
dart pub global activate flutterfire_cli
flutterfire configure
```

This overwrites the placeholder `lib/firebase_options.dart` with real
values. Then in the Firebase console:
- Enable **Firestore Database**.
- Enable **Authentication → Anonymous**.
- Paste `firebase/firestore.rules` into Firestore's Rules tab and
  publish. Deploy `firebase/firestore.indexes.json` via
  `firebase deploy --only firestore:indexes` (or the CLI equivalent)
  if you use the Firebase CLI for this project.

Also add location permissions before your first run:

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>West Bengal Smart Bus uses your location to show it on the map
and, if you choose to share it, to help other passengers see this
bus's live position.</string>
```

## Known limitations (disclosed, not hidden)

- **No real road-following polylines.** Drawing an accurate route
  line and computing real road distance/ETA requires a routing engine
  (OSRM/GraphHopper/Google Directions) — this sandbox has no network
  access to call one. The map currently draws a straight line between
  the first and last stop that have coordinates, and the ETA engine
  uses straight-line (haversine) distance. Both are clearly labeled as
  approximations in the UI and code comments. To upgrade: once you
  have network access, call a routing API with each route's ordered
  stop coordinates, store the returned encoded polyline + real
  distance/duration back into `routes.json`
  (`estimated_distance_km`/`estimated_travel_time_min`), and swap the
  straight-line `Polyline` in `live_map_screen.dart` for the decoded
  real one.
- **Most intermediate-stop coordinates are null.** Only ~20 of 63
  stops have coordinates (the towns I'm confident about). Fill in the
  rest with a real geocoding pass (Nominatim/OSM, respecting their
  usage policy) once you have connectivity — the app already handles
  partial coordinate coverage gracefully (trip-progress features
  degrade to "insufficient data" rather than guessing).
- **Multi-language toggle**: both English and Bengali string sets
  exist in `app_strings.dart` but aren't wired to a runtime switcher.
- **No admin CMS**: dataset updates currently mean editing the JSON
  files directly and shipping a new build (or, if you wire up the
  reserved `buses` Firestore collection, updating there instead).

## Run it

```
flutter pub get
flutter test
flutter run
```
