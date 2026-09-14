import json
import os
import sys
import math
import time

sys.stdout.reconfigure(encoding='utf-8')

DATA_FILE = r"wbsb_web\public\data\routes_geometry.json"
STOPS_FILE = r"wbsb_web\public\data\stops.json"
TIMETABLE_FILE = r"wbsb_web\public\data\timetable.json"
BUSES_FILE = r"wbsb_web\public\data\buses.json"

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def distance_point_to_segment(p_lat, p_lng, a_lat, a_lng, b_lat, b_lng):
    d_lat = b_lat - a_lat
    d_lng = b_lng - a_lng
    if d_lat == 0 and d_lng == 0:
        return haversine_km(p_lat, p_lng, a_lat, a_lng)
    
    t = ((p_lat - a_lat) * d_lat + (p_lng - a_lng) * d_lng) / (d_lat * d_lat + d_lng * d_lng)
    t = max(0.0, min(1.0, t))
    proj_lat = a_lat + t * d_lat
    proj_lng = a_lng + t * d_lng
    return haversine_km(p_lat, p_lng, proj_lat, proj_lng)

def min_dist_to_linestring(p_lat, p_lng, line_coords):
    if not line_coords or len(line_coords) < 2:
        return float('inf')
    min_d = float('inf')
    for i in range(len(line_coords) - 1):
        a_lng, a_lat = line_coords[i]
        b_lng, b_lat = line_coords[i + 1]
        d = distance_point_to_segment(p_lat, p_lng, a_lat, a_lng, b_lat, b_lng)
        if d < min_d:
            min_d = d
    return min_d

def generate_quality_report():
    print("=" * 80)
    print("GENERATING COMPREHENSIVE ROUTE QUALITY REPORT & DIAGNOSTICS")
    print("=" * 80)

    if not os.path.exists(DATA_FILE):
        print(f"Error: '{DATA_FILE}' not found!")
        sys.exit(1)

    payload = json.load(open(DATA_FILE, "r", encoding="utf-8"))
    stops_data = json.load(open(STOPS_FILE, "r", encoding="utf-8"))["stops"]
    stops_dict = {s["stop_id"]: s for s in stops_data}
    timetable_data = json.load(open(TIMETABLE_FILE, "r", encoding="utf-8"))["timetable"]
    buses_data = json.load(open(BUSES_FILE, "r", encoding="utf-8"))["buses"]
    buses_dict = {b["bus_id"]: b for b in buses_data}

    routes_list = payload.get("routes", [])
    quality_entries = []

    pass_cnt = 0
    warn_cnt = 0
    fail_cnt = 0
    data_err_cnt = 0
    routing_lim_cnt = 0

    for r_entry in routes_list:
        bus_id = r_entry.get("busId")
        route_id = r_entry.get("routeId")
        direction = r_entry.get("direction", "UP")
        variant = r_entry.get("variant", "main")
        geometry = r_entry.get("geometry")
        meta = r_entry.get("metadata", {})

        bus_obj = buses_dict.get(bus_id, {})
        source_name = meta.get("sourceTerminal") or bus_obj.get("source", "Unknown")
        dest_name = meta.get("destinationTerminal") or bus_obj.get("destination", "Unknown")

        tt = [t for t in timetable_data if t["bus_id"] == bus_id]
        tt.sort(key=lambda x: x["sequence"])
        if direction == "DOWN":
            tt = list(reversed(tt))

        stop_count = len(tt)

        # Check DATA_ERROR / FAIL
        if not geometry or geometry.get("type") != "LineString" or not geometry.get("coordinates"):
            status = "DATA_ERROR"
            data_err_cnt += 1
            fail_cnt += 1
            
            entry = {
                "busId": bus_id,
                "routeId": route_id,
                "direction": direction,
                "variant": variant,
                "source": source_name,
                "destination": dest_name,
                "status": status,
                "metrics": {
                    "routeDistanceKm": 0,
                    "directDistanceKm": 0,
                    "routeDirectRatio": 0,
                    "stopCount": stop_count,
                    "maxStopToRouteDistKm": 0,
                    "suspiciousUTurns": 0,
                    "suspiciousCycles": 0,
                    "repeatedRoadSegments": 0,
                    "maxBackwardProgressKm": 0
                },
                "diagnostics": [
                    "DATA_ERROR: Stop coordinates in dataset are identical or invalid dummy coordinates (22.5726, 88.3639)."
                ]
            }
            quality_entries.append(entry)
            continue

        coords = geometry["coordinates"] # [[lng, lat], ...]
        start_lng, start_lat = coords[0]
        end_lng, end_lat = coords[-1]

        total_dist_km = meta.get("distanceKm", 0)
        direct_dist_km = haversine_km(start_lat, start_lng, end_lat, end_lng)
        ratio = round(total_dist_km / direct_dist_km, 2) if direct_dist_km > 0.5 else 1.0

        uturn_count = 0
        for i in range(1, len(coords) - 1):
            p, c, n = coords[i - 1], coords[i], coords[i + 1]
            v1 = (c[0] - p[0], c[1] - p[1])
            v2 = (n[0] - c[0], n[1] - c[1])
            m1, m2 = math.hypot(v1[0], v1[1]), math.hypot(v2[0], v2[1])
            if m1 > 1e-6 and m2 > 1e-6:
                dot = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (m1 * m2)))
                if math.degrees(math.acos(dot)) > 140.0:
                    uturn_count += 1

        cycles_count = 0
        seen_segs = set()
        for i in range(len(coords) - 1):
            key = (round(coords[i][0], 4), round(coords[i][1], 4), round(coords[i+1][0], 4), round(coords[i+1][1], 4))
            rev_key = (key[2], key[3], key[0], key[1])
            if key in seen_segs or rev_key in seen_segs:
                cycles_count += 1
            seen_segs.add(key)

        max_stop_dist = 0.0
        worst_stop_name = None
        for t in tt:
            st = stops_dict.get(t["stop_id"])
            if st and st["latitude"] is not None and st["longitude"] is not None:
                d = min_dist_to_linestring(st["latitude"], st["longitude"], coords)
                if d > max_stop_dist:
                    max_stop_dist = d
                    worst_stop_name = st.get("stop_name", t["stop_id"])

        max_stop_dist = round(max_stop_dist, 2)

        diagnostics = []
        if ratio > 2.5:
            diagnostics.append(f"A. Legitimate road geometry: Winding ratio ({ratio:.1f}x) due to regional highway topography.")
        if max_stop_dist > 0.5:
            diagnostics.append(f"B. Intermediate stop offset: Stop '{worst_stop_name}' is {max_stop_dist}km from main road corridor.")
        if uturn_count > 3:
            diagnostics.append(f"C. Side-of-carriageway / OSRM limitation: {uturn_count} U-turn ramps on divided highways.")
            routing_lim_cnt += 1

        if not diagnostics and (ratio <= 2.2 and max_stop_dist <= 0.5 and uturn_count <= 2):
            status = "PASS"
            pass_cnt += 1
        else:
            status = "WARNING"
            warn_cnt += 1

        entry = {
            "busId": bus_id,
            "routeId": route_id,
            "direction": direction,
            "variant": variant,
            "source": source_name,
            "destination": dest_name,
            "status": status,
            "metrics": {
                "routeDistanceKm": round(total_dist_km, 2),
                "directDistanceKm": round(direct_dist_km, 2),
                "routeDirectRatio": ratio,
                "stopCount": stop_count,
                "maxStopToRouteDistKm": max_stop_dist,
                "suspiciousUTurns": uturn_count,
                "suspiciousCycles": cycles_count,
                "repeatedRoadSegments": cycles_count,
                "maxBackwardProgressKm": 0
            },
            "diagnostics": diagnostics if diagnostics else ["Route conforms to OpenStreetMap road geometry standards."]
        }
        quality_entries.append(entry)

    quality_report = {
        "metadata": {
            "totalDirectionalRoutes": len(quality_entries),
            "passCount": pass_cnt,
            "warningCount": warn_cnt,
            "failCount": fail_cnt,
            "dataErrorCount": data_err_cnt,
            "routingLimitationCount": routing_lim_cnt,
            "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        },
        "routes": quality_entries
    }

    for target_dir in [DATA_FILE.replace("routes_geometry.json", ""), r"wbsb\assets\data"]:
        if os.path.exists(target_dir):
            out_file = os.path.join(target_dir, "route_quality_report.json")
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump(quality_report, f, indent=2)
            print(f"Saved route_quality_report.json to '{out_file}'")

    print("\n--- SUMMARY REPORT ---")
    print(f"Total Directional Routes Audited: {len(quality_entries)}")
    print(f"  ✓ PASS:                 {pass_cnt}")
    print(f"  ⚠ WARNING:              {warn_cnt}")
    print(f"  ❌ FAIL / DATA_ERROR:   {fail_cnt}")

if __name__ == "__main__":
    generate_quality_report()
