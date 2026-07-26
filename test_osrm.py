import json
import urllib.request
import urllib.parse

# Load routes and stops
routes = json.load(open(r"wbsb_web\public\data\routes.json", encoding="utf-8"))["routes"]
stops_dict = {s["stop_id"]: s for s in json.load(open(r"wbsb_web\public\data\stops.json", encoding="utf-8"))["stops"]}

# Find Asansol - Digha route
target_route = None
for r in routes:
    if "asansol" in r["route_id"] and "digha" in r["route_id"]:
        target_route = r
        break

if not target_route:
    target_route = routes[0]

print(f"Target route: {target_route['route_name']}")
coord_stops = []
for s_id in target_route["stop_sequence"]:
    if s_id in stops_dict:
        s = stops_dict[s_id]
        if s["latitude"] is not None and s["longitude"] is not None:
            coord_stops.append(s)

# Deduplicate
seen = set()
unique_stops = []
for s in coord_stops:
    key = f"{round(s['latitude'], 5)},{round(s['longitude'], 5)}"
    if key not in seen:
        seen.add(key)
        unique_stops.append(s)

print(f"Total stops: {len(coord_stops)}, Unique stops: {len(unique_stops)}")

# Sample exactly 8 waypoints
sampled_stops = []
max_waypoints = 8
if len(unique_stops) <= max_waypoints:
    sampled_stops = unique_stops
else:
    sampled_stops.append(unique_stops[0])
    step = (len(unique_stops) - 1) / (max_waypoints - 1)
    for i in range(1, max_waypoints - 1):
        idx = round(i * step)
        if idx > 0 and idx < len(unique_stops) - 1:
            sampled_stops.append(unique_stops[idx])
    sampled_stops.append(unique_stops[-1])

print(f"Sampled waypoints: {len(sampled_stops)}")

# Test OSRM
coords_str = ";".join(f"{s['longitude']},{s['latitude']}" for s in sampled_stops)
url = f"https://router.project-osrm.org/route/v1/driving/{coords_str}?overview=full&geometries=geojson"
print(f"URL Length: {len(url)}")

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        if data.get("code") == "Ok":
            print("OSRM returned OK! Route found.")
            print(f"Number of geometry points: {len(data['routes'][0]['geometry']['coordinates'])}")
        else:
            print(f"OSRM returned error: {data.get('code')}")
except Exception as e:
    print(f"OSRM request failed: {e}")
