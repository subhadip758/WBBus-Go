import json

data_dir = r"c:\Users\Subhadip\Downloads\west_bengal_smart_bus\wbsb_web\public\data"

# Load original datasets
with open(f"{data_dir}\\buses.json", "r", encoding="utf-8") as f:
    orig_buses = json.load(f)["buses"]
with open(f"{data_dir}\\routes.json", "r", encoding="utf-8") as f:
    orig_routes = json.load(f)["routes"]
with open(f"{data_dir}\\stops.json", "r", encoding="utf-8") as f:
    orig_stops = json.load(f)["stops"]
with open(f"{data_dir}\\timetable.json", "r", encoding="utf-8") as f:
    orig_timetable = json.load(f)["timetable"]

# Load crawled dataset
with open(f"{data_dir}\\wbbustime_crawled_dataset.json", "r", encoding="utf-8") as f:
    crawled_data = json.load(f)

crawled_buses = crawled_data["buses"]
crawled_routes = crawled_data["routes"]
crawled_stops = crawled_data["stops"]
crawled_timetable = crawled_data["timetable"]

# Merge buses (avoiding duplicate bus_ids)
buses_dict = {b["bus_id"]: b for b in orig_buses}
for b in crawled_buses:
    buses_dict[b["bus_id"]] = b
merged_buses = list(buses_dict.values())

# Merge routes (avoiding duplicate route_ids)
routes_dict = {r["route_id"]: r for r in orig_routes}
for r in crawled_routes:
    routes_dict[r["route_id"]] = r
merged_routes = list(routes_dict.values())

# Merge stops: keep original if coordinates exist
stops_dict = {s["stop_id"]: s for s in orig_stops}
for s in crawled_stops:
    if s["stop_id"] not in stops_dict:
        stops_dict[s["stop_id"]] = s
    else:
        # Keep original since it might have coordinates, but merge names if needed
        pass
merged_stops = list(stops_dict.values())

# Merge timetable (avoiding duplicates)
# We can index by (bus_id, sequence)
timetable_dict = {(t["bus_id"], t["sequence"]): t for t in orig_timetable}
for t in crawled_timetable:
    timetable_dict[(t["bus_id"], t["sequence"])] = t
merged_timetable = list(timetable_dict.values())

# Generate operators dynamically
operators = set()
for b in merged_buses:
    if b.get("operator"):
        operators.add(b["operator"])

operators_list = []
for idx, op in enumerate(sorted(list(operators))):
    operators_list.append({
        "operator_id": f"op_{idx+1}",
        "name": op
    })

# Write back merged datasets
with open(f"{data_dir}\\buses.json", "w", encoding="utf-8") as f:
    json.dump({"buses": merged_buses}, f, indent=2)

with open(f"{data_dir}\\routes.json", "w", encoding="utf-8") as f:
    json.dump({"routes": merged_routes}, f, indent=2)

with open(f"{data_dir}\\stops.json", "w", encoding="utf-8") as f:
    json.dump({"stops": merged_stops}, f, indent=2)

with open(f"{data_dir}\\timetable.json", "w", encoding="utf-8") as f:
    json.dump({"timetable": merged_timetable}, f, indent=2)

with open(f"{data_dir}\\operators.json", "w", encoding="utf-8") as f:
    json.dump({"operators": operators_list}, f, indent=2)

print("Merging completed successfully!")
print(f"Buses: {len(orig_buses)} -> {len(merged_buses)}")
print(f"Routes: {len(orig_routes)} -> {len(merged_routes)}")
print(f"Stops: {len(orig_stops)} -> {len(merged_stops)}")
print(f"Timetable: {len(orig_timetable)} -> {len(merged_timetable)}")
print(f"Operators: {len(operators_list)}")
