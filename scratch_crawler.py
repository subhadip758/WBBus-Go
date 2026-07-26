import sys
import json
import re
import urllib.request
import urllib.error
import time
import os

try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

# Load draft datasets to get the list of URLs
with open("draft_wbbustime_datasets.json", "r", encoding="utf-8") as f:
    draft_data = json.load(f)

buses = draft_data["buses"]
routes = draft_data["routes"]

final_buses = []
final_routes = []
final_stops = {}
final_timetable = []

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36'
}

def clean_id(name):
    c = re.sub(r'[^\w\s]', '', name, flags=re.UNICODE).strip().lower()
    c = re.sub(r'\s+', '_', c)
    if not c:
        import hashlib
        c = hashlib.md5(name.encode('utf-8')).hexdigest()[:8]
    return c

def convert_to_24h(time_str):
    if not time_str or time_str.strip() == '-' or time_str.strip() == '':
        return None
    time_str = time_str.strip()
    match = re.match(r'(\d+):(\d+)\s*(AM|PM)', time_str, re.IGNORECASE)
    if not match:
        return None
    h, m, p = match.groups()
    h = int(h)
    p = p.upper()
    if p == 'PM' and h != 12:
        h += 12
    elif p == 'AM' and h == 12:
        h = 0
    return f"{h:02d}:{m}"

total = len(buses)
print(f"Starting crawl for {total} bus routes...")

for index, bus in enumerate(buses):
    url = bus["url"]
    print(f"[{index+1}/{total}] Fetching: {bus['operator']} ({bus['source']} -> {bus['destination']})")
    
    # Simple retry mechanism
    html = ""
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=10) as response:
                html = response.read().decode('utf-8')
            break
        except Exception as e:
            print(f"  Attempt {attempt+1} failed: {e}")
            time.sleep(2)
            
    if not html:
        print(f"  Skipping {url} due to download failure.")
        continue
        
    # Extract the table rows
    # We find <tbody>...</tbody> or <tr>...</tr> inside the table
    # Simple regex to extract stop names and times
    rows_pattern = r'<tr><td>([^<]+)</td><td>([^<]*)</td><td>([^<]*)</td></tr>'
    rows = re.findall(rows_pattern, html)
    
    if not rows:
        # Check if there is another structure, or retry matching
        print(f"  No timetable rows found for {url}.")
        continue
        
    route_stop_ids = []
    
    for seq_idx, (stop_name, up_time_str, down_time_str) in enumerate(rows):
        stop_name = stop_name.strip()
        stop_id = f"stop_{clean_id(stop_name)}"
        
        # Register stop globally
        if stop_id not in final_stops:
            final_stops[stop_id] = {
                "stop_id": stop_id,
                "stop_name": stop_name,
                "latitude": None,
                "longitude": None
            }
            
        route_stop_ids.append(stop_id)
        
        up_time = convert_to_24h(up_time_str)
        down_time = convert_to_24h(down_time_str)
        
        final_timetable.append({
            "bus_id": bus["bus_id"],
            "stop_id": stop_id,
            "sequence": seq_idx + 1,
            "up_time": up_time,
            "down_time": down_time
        })
        
    # Build final route entry
    route_id = bus["route_id"]
    final_routes.append({
        "route_id": route_id,
        "route_name": f"{bus['source']} - {bus['destination']} ({bus['operator']})",
        "source": bus["source"],
        "destination": bus["destination"],
        "estimated_distance_km": None,
        "estimated_travel_time_min": None,
        "stop_sequence": route_stop_ids,
        "data_quality_notes": []
    })
    
    # Save bus entry (without temporary URL key)
    bus_entry = bus.copy()
    bus_entry.pop("url", None)
    final_buses.append(bus_entry)
    
    # Polite sleep to avoid rate limiting
    time.sleep(0.5)

# Convert stops dict to sorted list
stops_list = [v for k, v in sorted(final_stops.items())]

# Combine into output dict
final_dataset = {
    "buses": final_buses,
    "routes": final_routes,
    "stops": stops_list,
    "timetable": final_timetable
}

# Write output file
with open("c:\\Users\\Subhadip\\Downloads\\west_bengal_smart_bus\\wbsb_web\\public\\data\\wbbustime_crawled_dataset.json", "w", encoding="utf-8") as f:
    json.dump(final_dataset, f, indent=2)

print("\nCrawl and build completed successfully!")
print(f"Total Buses: {len(final_buses)}")
print(f"Total Routes: {len(final_routes)}")
print(f"Total Unique Stops: {len(stops_list)}")
print(f"Total Timetable Entries: {len(final_timetable)}")
