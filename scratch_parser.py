import re
import json

md_path = r"C:\Users\Subhadip\.gemini\antigravity\brain\763263d8-76c8-479d-a228-3a76215342ea\.system_generated\steps\846\content.md"

with open(md_path, 'r', encoding='utf-8') as f:
    html = f.read()

# Regular expression to match links in the <ul> block
# e.g., <li><a href="/bus-timetable/bankura-bus-stand-to-amlashuli/" title="...">Amlashuli → Bankura Bus Stand (JOY BABA KHETRAPAL)</a></li>
pattern = r'href="([^"]+)"[^>]*>([^<]+)</a>'
matches = re.findall(pattern, html)

buses = []
routes = []
operators = set()
stops = set()

print(f"Found {len(matches)} links.")

for href, text in matches:
    # We only care about /bus-timetable/ routes
    if not href.startswith('/bus-timetable/'):
        continue
        
    text = text.replace('&rarr;', '→')
    
    # Parse "Source → Destination (Operator)"
    # e.g., "Amlashuli → Bankura Bus Stand (JOY BABA KHETRAPAL)"
    parts = text.split('→')
    if len(parts) != 2:
        continue
        
    source = parts[0].strip()
    rest = parts[1].strip()
    
    # Extract operator name inside parentheses
    op_match = re.search(r'\(([^)]+)\)', rest)
    if op_match:
        operator = op_match.group(1).strip()
        destination = rest[:op_match.start()].strip()
    else:
        operator = "Unknown Operator"
        destination = rest
        
    # Generate clean IDs
    # strip out special characters, replace spaces with underscores, lowercase
    def clean_id(name):
        c = re.sub(r'[^\w\s]', '', name, flags=re.UNICODE).strip().lower()
        c = re.sub(r'\s+', '_', c)
        if not c:
            import hashlib
            c = hashlib.md5(name.encode('utf-8')).hexdigest()[:8]
        return c
        
    bus_id = f"bus_{clean_id(operator)}_{clean_id(source)}_{clean_id(destination)}"
    route_id = f"route_{clean_id(source)}_{clean_id(destination)}_{clean_id(operator)}"
    
    # Register stops
    stops.add(source)
    stops.add(destination)
    operators.add(operator)
    
    buses.append({
        "bus_id": bus_id,
        "bus_name": operator.split()[0].upper() if operator else "BUS",
        "alternate_name": operator if len(operator.split()) > 1 else None,
        "registration_number": None,
        "agency": None,
        "operator": operator,
        "bus_type": "Private - NON AC", # default
        "contact_number": None,
        "alternate_number": None,
        "source": source,
        "destination": destination,
        "route_id": route_id,
        "url": f"https://wbbustime.in{href}"
    })
    
    routes.append({
        "route_id": route_id,
        "route_name": f"{source} - {destination} ({operator})",
        "source": source,
        "destination": destination,
        "estimated_distance_km": None,
        "estimated_travel_time_min": None,
        "stop_sequence": [source, destination], # basic representation
        "data_quality_notes": []
    })

# Format stops
stops_list = []
for idx, stop in enumerate(sorted(stops)):
    stops_list.append({
        "stop_id": f"stop_{clean_id(stop)}",
        "stop_name": stop,
        "latitude": None,
        "longitude": None
    })

output = {
    "buses": buses,
    "routes": routes,
    "operators": sorted(list(operators)),
    "stops": stops_list
}

with open("draft_wbbustime_datasets.json", "w", encoding="utf-8") as f:
    json.dump(output, f, indent=2)

print(f"Successfully processed {len(buses)} buses, {len(routes)} routes, {len(operators)} operators, and {len(stops_list)} unique stops.")
