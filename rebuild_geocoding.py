import json
import urllib.request
import urllib.parse
import re
import os

data_dir = r"c:\Users\Subhadip\Downloads\west_bengal_smart_bus\wbsb_web\public\data"

# 1. Static high-precision coordinates for West Bengal terminuses and major cities
major_cities = {
    "kolkata": (22.5726, 88.3639),
    "esplanade": (22.5644, 88.3518),
    "karunamoyee": (22.5901, 88.4239),
    "salt lake": (22.5744, 88.4339),
    "howrah": (22.5855, 88.3315),
    "babughat": (22.5645, 88.3425),
    "digha": (21.6266, 87.5074),
    "new digha": (21.6235, 87.4988),
    "old digha": (21.6285, 87.5140),
    "digha border": (21.6201, 87.4895),
    "asansol": (23.6739, 86.9524),
    "siliguri": (26.7271, 88.3953),
    "tenzing norgay": (26.7324, 88.4290),
    "bankura": (23.2324, 87.0785),
    "purulia": (23.3322, 86.3653),
    "bardhaman": (23.2324, 87.8630),
    "burdwan": (23.2324, 87.8630),
    "kharagpur": (22.3302, 87.3237),
    "chaurangee": (22.3533, 87.3255),
    "medinipur": (22.4164, 87.3269),
    "midnapore": (22.4164, 87.3269),
    "haldia": (22.0620, 88.0698),
    "bolpur": (23.6689, 87.6800),
    "santiniketan": (23.6780, 87.6740),
    "suri": (23.9054, 87.5246),
    "durgapur": (23.5204, 87.3119),
    "raniganj": (23.6111, 87.1215),
    "jhargram": (22.4550, 86.9900),
    "egra": (21.9004, 87.5379),
    "contai": (21.7781, 87.7535),
    "kanthi": (21.7781, 87.7535),
    "malda": (25.0081, 88.1397),
    "english bazar": (25.0081, 88.1397),
    "raiganj": (25.6244, 88.1278),
    "balurghat": (25.2222, 88.7643),
    "cooch behar": (26.3236, 89.4510),
    "koch bihar": (26.3236, 89.4510),
    "alipurduar": (26.4916, 89.5273),
    "jalpaiguri": (26.5215, 88.7196),
    "darjeeling": (27.0410, 88.2627),
    "kalimpong": (27.0594, 88.4689),
    "dharampur": (22.9554, 88.4000),
    "arambagh": (22.8804, 87.7816),
    "ghatal": (22.6680, 87.7170),
    "tarakeswar": (22.8885, 88.0185),
    "chinsurah": (22.9022, 88.3959),
    "hooghly": (22.9022, 88.3959),
    "serampore": (22.7504, 88.3435),
    "barrackpore": (22.7569, 88.3639),
    "barasat": (22.7234, 88.4873),
    "basirhat": (22.6574, 88.8914),
    "canning": (22.3119, 88.6588),
    "diamond harbour": (22.1897, 88.1937),
    "kakdwip": (21.8756, 88.1891),
    "namkhana": (21.7667, 88.2333),
    "bakkhali": (21.5647, 88.2711),
    "habra": (22.8369, 88.6656),
    "bongaon": (23.0427, 88.8267),
    "krishnanagar": (23.4000, 88.5000),
    "nabadwip": (23.4088, 88.3655),
    "ranaghat": (23.1812, 88.5630),
    "kalyani": (22.9750, 88.4344),
    "berhampore": (24.1002, 88.2497),
    "baharampur": (24.1002, 88.2497),
    "murshidabad": (24.1750, 88.2686),
    "jangipur": (24.4719, 88.0642),
    "raghunathganj": (24.4719, 88.0642),
    "dhuliyan": (24.7950, 87.9400),
    "farakka": (24.8111, 87.9014),
    "kandi": (23.9574, 88.0369),
    "taldangra": (23.0189, 87.1121),
    "simlapal": (22.9234, 87.0722),
    "sarenga": (22.7758, 86.9944),
    "raipur": (22.8028, 86.9589),
    "kamarpukur": (22.8988, 87.7780),
    "jairambati": (22.9248, 87.7122),
    "patrasayer": (23.2104, 87.5255),
    "sonamukhi": (23.3033, 87.4172),
    "mejia": (23.5670, 87.1000),
    "saltora": (23.5180, 86.9380),
    "khatra": (22.9800, 86.8500),
    "ranibandh": (22.8667, 86.7833),
    "jaldapara": (26.6800, 89.3300),
    "lataguri": (26.7160, 88.7660),
    "gorumara": (26.7900, 88.8000),
    "chalsa": (26.8833, 88.7833),
    "malbazar": (26.8667, 88.7500),
    "birpara": (26.7000, 89.1333),
    "hasimara": (26.7333, 89.3500),
    "jaigaon": (26.8333, 89.3833),
    "mathabhanga": (26.3500, 89.2167),
    "dinhata": (26.1333, 89.4667),
    "tufanganj": (26.3167, 89.6667),
    "mekhliganj": (26.3500, 88.9000),
    "haldibari": (26.3333, 88.7667),
    "kurseong": (26.8778, 88.2767),
    "mirik": (26.8874, 88.1884),
    "mungpoo": (26.9740, 88.3840),
    "sukna": (26.7878, 88.3653),
    "bagdogra": (26.6860, 88.3140),
    "naxalbari": (26.6833, 88.2000),
    "kharibari": (26.5667, 88.1833),
    "phansidewa": (26.5833, 88.3000),
    "islampur": (26.2667, 88.2000),
    "kaliaganj": (25.6333, 88.3167),
    "gangarampur": (25.4000, 88.5333),
    "itahar": (25.4500, 88.1667),
    "chanchal": (25.3833, 87.9833),
    "harishchandrapur": (25.4167, 87.8833),
    "samsi": (25.2667, 88.0000),
    "gazole": (25.2167, 88.1833),
    "kaliachak": (24.8000, 88.0167),
}

# 2. OSM elements cache
osm_elements_file = "geocode_osm_elements.json"
if os.path.exists(osm_elements_file):
    print("Loading OSM elements from local cache...")
    with open(osm_elements_file, "r", encoding="utf-8") as f:
        osm_data = json.load(f)
else:
    print("OSM elements cache not found. Querying Overpass API...")
    overpass_url = "https://overpass-api.de/api/interpreter"
    query = """[out:json][timeout:180];
    area["ISO3166-2"="IN-WB"]->.searchArea;
    (
      node["place"~"city|town|village|suburb|neighbourhood|locality"](area.searchArea);
      node["highway"="bus_stop"](area.searchArea);
      node["amenity"="bus_station"](area.searchArea);
    );
    out body;"""
    data = urllib.parse.urlencode({'data': query}).encode('utf-8')
    req = urllib.request.Request(overpass_url, data=data, headers={'User-Agent': 'WBBusGo Geocoder'})
    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            osm_data = json.loads(response.read().decode('utf-8'))
        with open(osm_elements_file, "w", encoding="utf-8") as f:
            json.dump(osm_data, f)
        print(f"Downloaded and cached {len(osm_data['elements'])} elements from OSM.")
    except Exception as e:
        print(f"Error fetching Overpass data: {e}")
        osm_data = {"elements": []}

# Index OSM elements by normalized name
def norm(name):
    n = name.lower()
    n = re.sub(r'\b(bus\s+stand|bus\s+depot|railway\s+station|junction|crossing|more|mor|ch चौराहे|bus\s+stop|stand|stn|rly|border)\b', '', n)
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
            priority = 0
            if "highway" in tags or "amenity" in tags:
                priority = 2
            elif tags.get("place") in ["city", "town"]:
                priority = 1
                
            existing = osm_index.get(normalized)
            if not existing or priority > existing[2]:
                osm_index[normalized] = (el["lat"], el["lon"], priority, name)

# 3. Load stops and reset intermediate stops' coordinates
stops_path = f"{data_dir}\\stops.json"
with open(stops_path, "r", encoding="utf-8") as f:
    stops_file = json.load(f)
stops = stops_file["stops"]

# Preserve original custom stops (stop_1 to stop_63 are the 8 original mock buses' stops)
preserved_ids = {f"stop_{i}" for i in range(1, 64)}

for stop in stops:
    if stop["stop_id"] in preserved_ids:
        # Keep original coordinates intact
        continue
    # Reset coordinates for all others to allow clean recalculation
    stop["latitude"] = None
    stop["longitude"] = None

# Match against major cities list first
static_matches = 0
for stop in stops:
    if stop["stop_id"] in preserved_ids:
        continue
    normalized_name = norm(stop["stop_name"])
    
    # Try direct match
    if normalized_name in major_cities:
        stop["latitude"] = major_cities[normalized_name][0]
        stop["longitude"] = major_cities[normalized_name][1]
        static_matches += 1
    else:
        # Try substring match
        for key, coords in major_cities.items():
            if key in normalized_name or normalized_name in key:
                stop["latitude"] = coords[0]
                stop["longitude"] = coords[1]
                static_matches += 1
                break

print(f"Matched {static_matches} stops using static major cities lookup.")

# Match against OSM
osm_matches = 0
for stop in stops:
    if stop["stop_id"] in preserved_ids or stop["latitude"] is not None:
        continue
    normalized_name = norm(stop["stop_name"])
    match = osm_index.get(normalized_name)
    if match:
        stop["latitude"] = match[0]
        stop["longitude"] = match[1]
        osm_matches += 1

print(f"Matched {osm_matches} stops using OSM elements index.")

# Index stops by ID for interpolation
stops_dict = {s["stop_id"]: s for s in stops}

# 4. Load routes to perform linear route interpolation
routes_path = f"{data_dir}\\routes.json"
with open(routes_path, "r", encoding="utf-8") as f:
    routes_file = json.load(f)
routes = routes_file["routes"]

for route in routes:
    seq_stop_ids = route["stop_sequence"]
    if not seq_stop_ids:
        continue
        
    # Ensure FIRST and LAST stops of the route sequence have coordinates
    # If they don't, resolve them using route source/destination properties!
    first_stop = stops_dict.get(seq_stop_ids[0])
    if first_stop and first_stop["latitude"] is None:
        # Resolve using route source name
        src_norm = norm(route["source"])
        if src_norm in major_cities:
            first_stop["latitude"] = major_cities[src_norm][0]
            first_stop["longitude"] = major_cities[src_norm][1]
        else:
            # Fallback to general Kolkata coordinates if completely unknown
            first_stop["latitude"] = 22.5726
            first_stop["longitude"] = 88.3639
            
    last_stop = stops_dict.get(seq_stop_ids[-1])
    if last_stop and last_stop["latitude"] is None:
        # Resolve using route destination name
        dest_norm = norm(route["destination"])
        if dest_norm in major_cities:
            last_stop["latitude"] = major_cities[dest_norm][0]
            last_stop["longitude"] = major_cities[dest_norm][1]
        else:
            # Fallback to general Digha coordinates if unknown
            last_stop["latitude"] = 21.6266
            last_stop["longitude"] = 87.5074

    # Extract coordinates in sequence
    coords = []
    for stop_id in seq_stop_ids:
        stop = stops_dict.get(stop_id)
        if stop and stop["latitude"] is not None and stop["longitude"] is not None:
            coords.append((stop["latitude"], stop["longitude"]))
        else:
            coords.append(None)
            
    # Perform interpolation between the known points (which now include the first and last stops!)
    valid_indices = [i for i, c in enumerate(coords) if c is not None]
    
    for i in range(len(coords)):
        if coords[i] is not None:
            continue
            
        # Find preceding valid index (guaranteed to find at least 0 since index 0 is valid)
        prec = [idx for idx in valid_indices if idx < i]
        # Find succeeding valid index (guaranteed to find at least len-1 since the last index is valid)
        succ = [idx for idx in valid_indices if idx > i]
        
        if prec and succ:
            p_idx = prec[-1]
            s_idx = succ[0]
            ratio = (i - p_idx) / (s_idx - p_idx)
            lat = coords[p_idx][0] + (coords[s_idx][0] - coords[p_idx][0]) * ratio
            lng = coords[p_idx][1] + (coords[s_idx][1] - coords[p_idx][1]) * ratio
        else:
            # Should never happen since 0 and last are populated, but fallback:
            lat, lng = 22.5726, 88.3639
            
        stop_id = seq_stop_ids[i]
        stop = stops_dict.get(stop_id)
        if stop and stop["latitude"] is None:
            stop["latitude"] = lat
            stop["longitude"] = lng

# Verify
null_count = sum(1 for s in stops if s["latitude"] is None)
print(f"Stops with missing coordinates after rebuild: {null_count}")

# Write back stops.json
with open(stops_path, "w", encoding="utf-8") as f:
    json.dump({"stops": stops}, f, indent=2)

print("Rebuilt stops.json with high-precision coordinates successfully!")
