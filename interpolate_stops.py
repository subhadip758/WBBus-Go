import json

data_dir = r"c:\Users\Subhadip\Downloads\west_bengal_smart_bus\wbsb_web\public\data"

# Load stops
with open(f"{data_dir}\\stops.json", "r", encoding="utf-8") as f:
    stops_file = json.load(f)
stops = {s["stop_id"]: s for s in stops_file["stops"]}

# Load routes
with open(f"{data_dir}\\routes.json", "r", encoding="utf-8") as f:
    routes_file = json.load(f)
routes = routes_file["routes"]

print(f"Loaded {len(stops)} stops and {len(routes)} routes.")

# Let's perform route-based interpolation
# For each route, find its stop sequences
for route in routes:
    seq_stop_ids = route["stop_sequence"]
    
    # Extract coordinates for each stop in sequence
    coords = []
    for stop_id in seq_stop_ids:
        stop = stops.get(stop_id)
        if stop and stop["latitude"] is not None and stop["longitude"] is not None:
            coords.append((stop["latitude"], stop["longitude"]))
        else:
            coords.append(None)
            
    # Interpolate
    # Find indices that are not None
    valid_indices = [i for i, c in enumerate(coords) if c is not None]
    
    if len(valid_indices) == 0:
        # Default fallback to Kolkata coordinates
        for stop_id in seq_stop_ids:
            stop = stops.get(stop_id)
            if stop and stop["latitude"] is None:
                stop["latitude"] = 22.5726
                stop["longitude"] = 88.3639
        continue
        
    for i in range(len(coords)):
        if coords[i] is not None:
            continue
            
        # Find preceding valid index
        prec = [idx for idx in valid_indices if idx < i]
        succ = [idx for idx in valid_indices if idx > i]
        
        if prec and succ:
            p_idx = prec[-1]
            s_idx = succ[0]
            # Linear interpolation
            ratio = (i - p_idx) / (s_idx - p_idx)
            lat = coords[p_idx][0] + (coords[s_idx][0] - coords[p_idx][0]) * ratio
            lng = coords[p_idx][1] + (coords[s_idx][1] - coords[p_idx][1]) * ratio
        elif prec:
            # Extrapolate using last known
            lat = coords[prec[-1]][0]
            lng = coords[prec[-1]][1]
        elif succ:
            # Extrapolate using first known
            lat = coords[succ[0]][0]
            lng = coords[succ[0]][1]
            
        # Write back to stops dictionary
        stop_id = seq_stop_ids[i]
        stop = stops.get(stop_id)
        if stop and stop["latitude"] is None:
            stop["latitude"] = lat
            stop["longitude"] = lng

# Count null coords remaining
null_count = sum(1 for s in stops.values() if s["latitude"] is None)
print(f"Stops with missing coordinates after interpolation: {null_count}")

# Write back stops
with open(f"{data_dir}\\stops.json", "w", encoding="utf-8") as f:
    json.dump({"stops": list(stops.values())}, f, indent=2)

print("Saved interpolated stops.json successfully!")
