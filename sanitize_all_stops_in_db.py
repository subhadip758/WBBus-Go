import json
import math
import sys
import shutil

# Reconfigure stdout to support UTF-8 printing of Bengali characters
sys.stdout.reconfigure(encoding='utf-8')

def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# Load datasets
routes_path = r"wbsb_web\public\data\routes.json"
stops_path = r"wbsb_web\public\data\stops.json"

routes_data = json.load(open(routes_path, encoding="utf-8"))
stops_data = json.load(open(stops_path, encoding="utf-8"))

routes = routes_data["routes"]
stops_list = stops_data["stops"]
stops_dict = {s["stop_id"]: s for s in stops_list}

print("Starting outlier detection and correction...")

# We run 3 passes because some routes have multiple consecutive outliers,
# and correcting one allows us to detect the next one in the next pass.
for pass_num in range(1, 4):
    print(f"\n--- Pass {pass_num} ---")
    corrections = 0
    
    for route in routes:
        seq = route["stop_sequence"]
        route_stops = []
        for s_id in seq:
            if s_id in stops_dict:
                route_stops.append(stops_dict[s_id])
                
        n = len(route_stops)
        if n < 3:
            continue
            
        # Detect intermediate outliers
        for i in range(1, n - 1):
            prev_stop = route_stops[i - 1]
            curr_stop = route_stops[i]
            next_stop = route_stops[i + 1]
            
            if (prev_stop["latitude"] is not None and prev_stop["longitude"] is not None and
                curr_stop["latitude"] is not None and curr_stop["longitude"] is not None and
                next_stop["latitude"] is not None and next_stop["longitude"] is not None):
                
                dist_prev = haversine(prev_stop["latitude"], prev_stop["longitude"], curr_stop["latitude"], curr_stop["longitude"])
                dist_next = haversine(curr_stop["latitude"], curr_stop["longitude"], next_stop["latitude"], next_stop["longitude"])
                dist_direct = haversine(prev_stop["latitude"], prev_stop["longitude"], next_stop["latitude"], next_stop["longitude"])
                
                # If current stop is far from both prev and next, but prev and next are relatively close
                if dist_prev > 45.0 and dist_next > 45.0 and dist_direct < 40.0:
                    print(f"Correction in '{route['route_name']}': '{curr_stop['stop_name']}' (Seq {i+1})")
                    print(f"  Old Lat/Lng: {curr_stop['latitude']}, {curr_stop['longitude']}")
                    
                    # Set to midpoint
                    curr_stop["latitude"] = (prev_stop["latitude"] + next_stop["latitude"]) / 2.0
                    curr_stop["longitude"] = (prev_stop["longitude"] + next_stop["longitude"]) / 2.0
                    
                    print(f"  New Lat/Lng: {curr_stop['latitude']}, {curr_stop['longitude']}")
                    corrections += 1
                    
    print(f"Pass {pass_num}: Corrected {corrections} outliers.")
    if corrections == 0:
        print("No more outliers detected. Stopping.")
        break

# Save updated stops.json to web app
stops_data["stops"] = list(stops_dict.values())
json.dump(stops_data, open(stops_path, "w", encoding="utf-8"), indent=2)
print("\nUpdated stops.json saved to wbsb_web.")

# Copy updated stops.json to native Flutter app assets
flutter_stops_path = r"wbsb\assets\data\stops.json"
shutil.copyfile(stops_path, flutter_stops_path)
print("Updated stops.json copied to wbsb/assets/data/stops.json.")
