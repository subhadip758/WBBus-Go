import urllib.request
import urllib.parse
import json
import re
import os

overpass_url = "https://overpass-api.de/api/interpreter"

# Overpass query to download all place nodes and bus facilities in West Bengal
query = """[out:json][timeout:180];
area["ISO3166-2"="IN-WB"]->.searchArea;
(
  node["place"~"city|town|village|suburb|neighbourhood|locality"](area.searchArea);
  node["highway"="bus_stop"](area.searchArea);
  node["amenity"="bus_station"](area.searchArea);
);
out body;"""

print("Sending request to Overpass API (this might take a few seconds)...")
data = urllib.parse.urlencode({'data': query}).encode('utf-8')
req = urllib.request.Request(overpass_url, data=data, headers={'User-Agent': 'WBBusGo Geocoder'})

try:
    with urllib.request.urlopen(req, timeout=180) as response:
        osm_data = json.loads(response.read().decode('utf-8'))
    print(f"Downloaded {len(osm_data['elements'])} elements from OSM.")
except Exception as e:
    print(f"Error fetching Overpass data: {e}")
    # Fallback to empty
    osm_data = {"elements": []}

# Load stops
stops_path = r"c:\Users\Subhadip\Downloads\west_bengal_smart_bus\wbsb_web\public\data\stops.json"
with open(stops_path, "r", encoding="utf-8") as f:
    stops_file = json.load(f)
stops = stops_file["stops"]

print(f"Loaded {len(stops)} stops from stops.json.")

# Index OSM elements by name
# Normalize name for matching
def norm(name):
    n = name.lower()
    # Remove common suffixes like "bus stand", "bus depot", "railway station", etc.
    n = re.sub(r'\b(bus\s+stand|bus\s+depot|railway\s+station|junction|crossing|more|mor|ch चौराहे|bus\s+stop|stand|stn|rly)\b', '', n)
    n = re.sub(r'[^a-z0-9]', '', n).strip()
    return n

osm_index = {}
for el in osm_data.get("elements", []):
    tags = el.get("tags", {})
    name = tags.get("name")
    name_en = tags.get("name:en")
    
    names_to_index = []
    if name: names_to_index.append(name)
    if name_en: names_to_index.append(name_en)
    
    for n in names_to_index:
        normalized = norm(n)
        if normalized:
            # Prefer bus stands or stations, then towns
            priority = 0
            if "highway" in tags or "amenity" in tags:
                priority = 2
            elif tags.get("place") in ["city", "town"]:
                priority = 1
                
            existing = osm_index.get(normalized)
            if not existing or priority > existing[2]:
                osm_index[normalized] = (el["lat"], el["lon"], priority, name)

# Perform matching
matched_count = 0
updated_stops = []

for stop in stops:
    # If the stop already has coordinates, keep them!
    if stop["latitude"] is not None and stop["longitude"] is not None:
        updated_stops.append(stop)
        continue
        
    normalized_name = norm(stop["stop_name"])
    match = osm_index.get(normalized_name)
    
    if match:
        stop["latitude"] = match[0]
        stop["longitude"] = match[1]
        matched_count += 1
    else:
        # Fallback coordinates: if we don't find it, we can assign a random nearby offset or just keep it null.
        # But wait, to keep things working, let's keep it null. We'll handle interpolation of coordinates later!
        pass
        
    updated_stops.append(stop)

print(f"Geocoded {matched_count} stops out of {len(stops) - sum(1 for s in stops if s['latitude'] is not None)} missing stops.")

# Write back
with open(stops_path, "w", encoding="utf-8") as f:
    json.dump({"stops": updated_stops}, f, indent=2)

print("Saved updated stops.json.")
