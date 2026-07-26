import json

buses = json.load(open(r"wbsb_web\public\data\buses.json", encoding="utf-8"))["buses"]
empty_buses = []
for b in buses:
    if not b.get("routeStops") or len(b["routeStops"]) == 0:
        empty_buses.append(b)

print(f"Total buses: {len(buses)}")
print(f"Buses with 0 routeStops: {len(empty_buses)}")
for eb in empty_buses[:15]:
    print(f"  Empty Bus: {eb['bus_name']} (ID: {eb['bus_id']})")
