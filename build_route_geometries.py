import json
import os
import sys
import time
import math
import hashlib
import urllib.request
import urllib.parse

sys.stdout.reconfigure(encoding='utf-8')
os.environ["PYTHONUNBUFFERED"] = "1"

DATA_DIR_WEB = r"wbsb_web\public\data"
DATA_DIR_FLUTTER = r"wbsb\assets\data"
CACHE_FILE = r".osrm_cache.json"

# Helper: Haversine distance in KM
def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

# Load OSRM Cache
osrm_cache = {}
if os.path.exists(CACHE_FILE):
    try:
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            osrm_cache = json.load(f)
        print(f"Loaded {len(osrm_cache)} cached OSRM responses.")
    except Exception as e:
        print(f"Warning loading cache: {e}")

def save_cache():
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(osrm_cache, f)
    except Exception as e:
        print(f"Warning saving cache: {e}")

def fetch_osrm_batch(coord_list):
    """
    coord_list: list of [lat, lng]
    Returns: list of [lng, lat] GeoJSON coordinates, distance_km
    """
    if not coord_list or len(coord_list) < 2:
        return None, 0

    # Deduplicate consecutive identical coordinates
    unique_coords = [coord_list[0]]
    for c in coord_list[1:]:
        if abs(c[0] - unique_coords[-1][0]) > 1e-6 or abs(c[1] - unique_coords[-1][1]) > 1e-6:
            unique_coords.append(c)

    if len(unique_coords) < 2:
        return None, 0

    # Build cache key based on coordinates
    key_str = "|".join(f"{c[0]:.5f},{c[1]:.5f}" for c in unique_coords)
    cache_key = hashlib.md5(key_str.encode('utf-8')).hexdigest()

    if cache_key in osrm_cache and osrm_cache[cache_key].get("coordinates") is not None:
        cached = osrm_cache[cache_key]
        return cached["coordinates"], cached["distanceKm"]

    # If list of points is large, chunk them into max 15 waypoints per OSRM request
    MAX_WAYPOINTS = 15
    if len(unique_coords) > MAX_WAYPOINTS:
        all_geojson_coords = []
        total_dist = 0
        for i in range(0, len(unique_coords) - 1, MAX_WAYPOINTS - 1):
            chunk = unique_coords[i:i + MAX_WAYPOINTS]
            chunk_coords, chunk_dist = fetch_osrm_batch(chunk)
            if chunk_coords:
                if all_geojson_coords and chunk_coords:
                    # Stitching: skip first point if duplicate of last
                    if (abs(all_geojson_coords[-1][0] - chunk_coords[0][0]) < 1e-6 and
                        abs(all_geojson_coords[-1][1] - chunk_coords[0][1]) < 1e-6):
                        chunk_coords = chunk_coords[1:]
                all_geojson_coords.extend(chunk_coords)
                total_dist += chunk_dist
        
        if all_geojson_coords:
            osrm_cache[cache_key] = {"coordinates": all_geojson_coords, "distanceKm": total_dist}
            return all_geojson_coords, total_dist
        return None, 0

    # Query OSRM API
    # GeoJSON format uses [longitude, latitude]
    coords_str = ";".join(f"{c[1]:.6f},{c[0]:.6f}" for c in unique_coords)
    url = f"https://router.project-osrm.org/route/v1/driving/{coords_str}?overview=full&geometries=geojson&continue_straight=true"

    retries = 3
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'WBBusGo/1.0 (subhadip758/WBBus-Go)'})
            with urllib.request.urlopen(req, timeout=12) as response:
                data = json.loads(response.read().decode('utf-8'))
                if data.get("code") == "Ok" and data.get("routes"):
                    route = data["routes"][0]
                    geojson_coords = route["geometry"]["coordinates"] # [[lng, lat], ...]
                    dist_km = route.get("distance", 0) / 1000.0
                    
                    osrm_cache[cache_key] = {"coordinates": geojson_coords, "distanceKm": dist_km}
                    time.sleep(0.15) # Throttle OSRM requests
                    return geojson_coords, dist_km
        except Exception as e:
            time.sleep(0.5 * (attempt + 1))
            if attempt == retries - 1:
                print(f"  [OSRM Error] URL length {len(url)}: {e}")

    return None, 0

def clean_road_geometry(geojson_coords, stops_latlng):
    """
    Cleans OSRM side-carriageway U-turn loops and duplicate consecutive points
    while preserving true road network geometry.
    geojson_coords: list of [lng, lat]
    stops_latlng: list of [lat, lng]
    """
    if not geojson_coords or len(geojson_coords) < 3:
        return geojson_coords

    # 1. Remove duplicate adjacent points
    deduped = [geojson_coords[0]]
    for p in geojson_coords[1:]:
        last = deduped[-1]
        if abs(p[0] - last[0]) > 1e-6 or abs(p[1] - last[1]) > 1e-6:
            deduped.append(p)

    if len(deduped) < 4:
        return deduped

    # 2. Road-Aware U-turn Spike Sanitization
    # Detect 180° U-turn spikes where path goes forward, turns back > 140°, and returns to main corridor within < 1.0 km
    cleaned = [deduped[0]]
    i = 1
    N = len(deduped)

    while i < N - 1:
        curr = deduped[i]
        nxt = deduped[i + 1]
        prev = cleaned[-1]

        # Calculate vectors: prev -> curr vs curr -> nxt
        v1 = (curr[0] - prev[0], curr[1] - prev[1])
        v2 = (nxt[0] - curr[0], nxt[1] - curr[1])
        mag1 = math.hypot(v1[0], v1[1])
        mag2 = math.hypot(v2[0], v2[1])

        if mag1 > 1e-7 and mag2 > 1e-7:
            dot = (v1[0] * v2[0] + v1[1] * v2[1]) / (mag1 * mag2)
            dot = max(-1.0, min(1.0, dot))
            angle_deg = math.degrees(math.acos(dot))

            # If sharp turn > 140° (almost complete reversal)
            if angle_deg > 140.0:
                dist_prev_curr = haversine_km(prev[1], prev[0], curr[1], curr[0])
                dist_curr_nxt = haversine_km(curr[1], curr[0], nxt[1], nxt[0])
                dist_prev_nxt = haversine_km(prev[1], prev[0], nxt[1], nxt[0])

                # Check if curr point is NOT near a legitimate stop
                is_near_stop = False
                for st in stops_latlng:
                    if haversine_km(curr[1], curr[0], st[0], st[1]) < 0.15: # 150m
                        is_near_stop = True
                        break

                # If turnback is short (< 1.0km) and NOT at a stop terminal, it's an OSRM carriageway loop artifact
                if not is_near_stop and dist_prev_curr < 1.0 and dist_prev_nxt < dist_prev_curr:
                    i += 1
                    continue

        cleaned.append(curr)
        i += 1

    cleaned.append(deduped[-1])
    return cleaned

def build_all_routes():
    print("=" * 70)
    print("BUILDING ROAD GEOMETRIES FOR ALL 124 BUSES (248 DIRECTIONAL ROUTES)")
    print("=" * 70)

    with open(os.path.join(DATA_DIR_WEB, "buses.json"), "r", encoding="utf-8") as f:
        buses_data = json.load(f)["buses"]
    with open(os.path.join(DATA_DIR_WEB, "routes.json"), "r", encoding="utf-8") as f:
        routes_data = json.load(f)["routes"]
    with open(os.path.join(DATA_DIR_WEB, "stops.json"), "r", encoding="utf-8") as f:
        stops_data = json.load(f)["stops"]
    with open(os.path.join(DATA_DIR_WEB, "timetable.json"), "r", encoding="utf-8") as f:
        timetable_data = json.load(f)["timetable"]

    stops_dict = {s["stop_id"]: s for s in stops_data}
    routes_dict = {r["route_id"]: r for r in routes_data}

    generated_routes = []
    success_count = 0
    fail_count = 0

    processed_timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    for idx, bus in enumerate(buses_data, start=1):
        bus_id = bus["bus_id"]
        route_id = bus["route_id"]
        bus_name = bus["bus_name"]

        # Find timetable entries
        tt_entries = [t for t in timetable_data if t["bus_id"] == bus_id]
        tt_entries.sort(key=lambda x: x["sequence"])

        if not tt_entries:
            # Fallback to route stop_sequence if timetable is missing
            r_obj = routes_dict.get(route_id)
            if r_obj and r_obj.get("stop_sequence"):
                tt_entries = [{"stop_id": sid, "sequence": i + 1} for i, sid in enumerate(r_obj["stop_sequence"])]

        # Extract ordered stops with valid coordinates
        stops_up = []
        for t in tt_entries:
            st = stops_dict.get(t["stop_id"])
            if st and st["latitude"] is not None and st["longitude"] is not None:
                stops_up.append(st)

        if len(stops_up) < 2:
            print(f"[{idx}/{len(buses_data)}] FAIL: '{bus_name}' ({bus_id}) - Insufficient stop coordinates ({len(stops_up)})")
            fail_count += 2
            continue

        # Directions to generate: UP (forward) and DOWN (reverse)
        directions = [
            ("UP", stops_up),
            ("DOWN", list(reversed(stops_up)))
        ]

        for direction, dir_stops in directions:
            coords_latlng = [[s["latitude"], s["longitude"]] for s in dir_stops]
            
            # Fetch OSRM multi-waypoint road geometry
            raw_geojson, dist_km = fetch_osrm_batch(coords_latlng)

            if raw_geojson and len(raw_geojson) >= 2:
                # Clean carriageway U-turn loops while preserving OSM roads
                cleaned_geojson = clean_road_geometry(raw_geojson, coords_latlng)
                
                route_entry = {
                    "busId": bus_id,
                    "routeId": route_id,
                    "direction": direction,
                    "variant": "main",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": cleaned_geojson # [[lng, lat], ...]
                    },
                    "metadata": {
                        "source": "OSRM + OpenStreetMap",
                        "processedAt": processed_timestamp,
                        "distanceKm": round(dist_km, 2),
                        "stopCount": len(dir_stops),
                        "coordinateCount": len(cleaned_geojson),
                        "sourceTerminal": dir_stops[0]["stop_name"],
                        "destinationTerminal": dir_stops[-1]["stop_name"]
                    }
                }
                generated_routes.append(route_entry)
                success_count += 1
            else:
                # Failed OSRM route: record FAIL entry in geometry store
                route_entry = {
                    "busId": bus_id,
                    "routeId": route_id,
                    "direction": direction,
                    "variant": "main",
                    "geometry": None,
                    "metadata": {
                        "source": "OSRM + OpenStreetMap",
                        "processedAt": processed_timestamp,
                        "error": "OSRM routing failed or produced zero coordinates",
                        "stopCount": len(dir_stops)
                    }
                }
                generated_routes.append(route_entry)
                fail_count += 1

        print(f"[{idx}/{len(buses_data)}] Processed '{bus_name}' ({bus_id}): UP ({len(stops_up)} stops) & DOWN ({len(stops_up)} stops)")

    save_cache()

    output_payload = {
        "metadata": {
            "totalBuses": len(buses_data),
            "totalDirectionalRoutes": len(generated_routes),
            "generatedAt": processed_timestamp,
            "osrmSource": "OpenStreetMap OSRM Server v1"
        },
        "routes": generated_routes
    }

    # Save to wbsb_web and wbsb
    for target_dir in [DATA_DIR_WEB, DATA_DIR_FLUTTER]:
        if os.path.exists(target_dir):
            out_file = os.path.join(target_dir, "routes_geometry.json")
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump(output_payload, f, indent=2)
            print(f"Successfully saved routes_geometry.json to '{out_file}' ({len(generated_routes)} directional routes)")

    print("=" * 70)
    print(f"BUILD SUMMARY: {success_count} routes generated, {fail_count} failed routes.")
    print("=" * 70)

if __name__ == "__main__":
    build_all_routes()
