import json
import os
import sys
import math

sys.stdout.reconfigure(encoding='utf-8')

DATA_FILE = r"wbsb_web\public\data\routes_geometry.json"
STOPS_FILE = r"wbsb_web\public\data\stops.json"
TIMETABLE_FILE = r"wbsb_web\public\data\timetable.json"

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def distance_point_to_segment(p_lat, p_lng, a_lat, a_lng, b_lat, b_lng):
    # Snaps point p to line segment ab and returns distance in km
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
    # line_coords is [[lng, lat], ...]
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

def verify_all_routes():
    print("=" * 80)
    print("COMPREHENSIVE ROUTE GEOMETRY AUDIT & QUALITY REPORT")
    print("=" * 80)

    if not os.path.exists(DATA_FILE):
        print(f"Error: '{DATA_FILE}' not found! Run build_route_geometries.py first.")
        sys.exit(1)

    with open(DATA_FILE, "r", encoding="utf-8") as f:
        payload = json.load(f)

    with open(STOPS_FILE, "r", encoding="utf-8") as f:
        stops_data = json.load(f)["stops"]
    stops_dict = {s["stop_id"]: s for s in stops_data}

    with open(TIMETABLE_FILE, "r", encoding="utf-8") as f:
        timetable_data = json.load(f)["timetable"]

    routes_list = payload.get("routes", [])

    pass_count = 0
    warning_count = 0
    fail_count = 0

    warnings_details = []
    fails_details = []

    for r_entry in routes_list:
        bus_id = r_entry.get("busId")
        direction = r_entry.get("direction")
        geometry = r_entry.get("geometry")
        meta = r_entry.get("metadata", {})

        route_label = f"{bus_id} ({direction})"

        # Check 1: Geometry exists and is LineString
        if not geometry or geometry.get("type") != "LineString" or not geometry.get("coordinates"):
            fail_count += 1
            fails_details.append(f"{route_label}: Missing geometry or invalid GeoJSON LineString")
            continue

        coords = geometry["coordinates"] # [[lng, lat], ...]
        coord_count = len(coords)

        # Check 2: Minimum coordinate count
        if coord_count < 2:
            fail_count += 1
            fails_details.append(f"{route_label}: Insufficient coordinates ({coord_count})")
            continue

        start_lng, start_lat = coords[0]
        end_lng, end_lat = coords[-1]

        # Calculate metrics
        total_dist_km = meta.get("distanceKm", 0)
        direct_dist_km = haversine_km(start_lat, start_lng, end_lat, end_lng)
        ratio = (total_dist_km / direct_dist_km) if direct_dist_km > 0.5 else 1.0

        # Check duplicate consecutive coordinates
        duplicate_coords = 0
        for i in range(len(coords) - 1):
            if abs(coords[i][0] - coords[i+1][0]) < 1e-7 and abs(coords[i][1] - coords[i+1][1]) < 1e-7:
                duplicate_coords += 1

        # Check suspicious U-turns (> 140° within 1.0 km)
        suspicious_uturns = 0
        for i in range(1, len(coords) - 1):
            p = coords[i - 1]
            c = coords[i]
            n = coords[i + 1]
            v1 = (c[0] - p[0], c[1] - p[1])
            v2 = (n[0] - c[0], n[1] - c[1])
            m1 = math.hypot(v1[0], v1[1])
            m2 = math.hypot(v2[0], v2[1])
            if m1 > 1e-6 and m2 > 1e-6:
                dot = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / (m1 * m2)))
                if math.degrees(math.acos(dot)) > 140.0:
                    suspicious_uturns += 1

        # Check stop snapping distance
        tt = [t for t in timetable_data if t["bus_id"] == bus_id]
        tt.sort(key=lambda x: x["sequence"])
        if direction == "DOWN":
            tt = list(reversed(tt))

        max_stop_dist = 0.0
        for t in tt:
            st = stops_dict.get(t["stop_id"])
            if st and st["latitude"] is not None and st["longitude"] is not None:
                d = min_dist_to_linestring(st["latitude"], st["longitude"], coords)
                if d > max_stop_dist:
                    max_stop_dist = d

        # Terminal distance checks
        first_stop = stops_dict.get(tt[0]["stop_id"]) if tt else None
        last_stop = stops_dict.get(tt[-1]["stop_id"]) if tt else None
        start_term_dist = haversine_km(first_stop["latitude"], first_stop["longitude"], start_lat, start_lng) if first_stop else 0
        end_term_dist = haversine_km(last_stop["latitude"], last_stop["longitude"], end_lat, end_lng) if last_stop else 0

        # Classification Criteria
        is_fail = (
            coord_count < 5 or
            ratio > 4.5 or
            start_term_dist > 5.0 or
            end_term_dist > 5.0
        )

        is_warning = (
            ratio > 2.2 or
            suspicious_uturns > 5 or
            max_stop_dist > 2.0 or
            duplicate_coords > 0 or
            start_term_dist > 1.0 or
            end_term_dist > 1.0
        )

        if is_fail:
            fail_count += 1
            fails_details.append(f"{route_label}: FAIL (Ratio: {ratio:.1f}x, StartTermDist: {start_term_dist:.2f}km, EndTermDist: {end_term_dist:.2f}km)")
        elif is_warning:
            warning_count += 1
            warnings_details.append(f"{route_label}: WARNING (Ratio: {ratio:.1f}x, U-Turns: {suspicious_uturns}, MaxStopSnap: {max_stop_dist:.2f}km)")
        else:
            pass_count += 1

    print(f"Total Routes Audited: {len(routes_list)}")
    print(f"  ✓ PASS:    {pass_count}")
    print(f"  ⚠ WARNING: {warning_count}")
    print(f"  ❌ FAIL:   {fail_count}")

    if warnings_details:
        print("\n--- WARNING DETAILS (Routes with minor detour ratio or stop offsets) ---")
        for w in warnings_details[:15]:
            print("  *", w)
        if len(warnings_details) > 15:
            print(f"  ... and {len(warnings_details) - 15} more warnings.")

    if fails_details:
        print("\n--- FAIL DETAILS (Routes requiring review) ---")
        for f_det in fails_details:
            print("  *", f_det)

    print("=" * 80)

if __name__ == "__main__":
    verify_all_routes()
