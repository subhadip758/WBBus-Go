import json

# Load files
stops_dict = {s["stop_id"]: s for s in json.load(open(r"wbsb_web\public\data\stops.json", encoding="utf-8"))["stops"]}
timetable = json.load(open(r"wbsb_web\public\data\timetable.json", encoding="utf-8"))["timetable"]
buses = json.load(open(r"wbsb_web\public\data\buses.json", encoding="utf-8"))["buses"]

bus_id = "bus_jinia_asansol_digha_border"
entries = [t for t in timetable if t["bus_id"] == bus_id]
entries.sort(key=lambda x: x["sequence"])

print(f"Total stops for {bus_id}: {len(entries)}")
for e in entries:
    s = stops_dict.get(e["stop_id"])
    if s:
        print(f"Seq: {e['sequence']} | ID: {e['stop_id']} | Name: {s['stop_name']} | Lat: {s['latitude']} | Lng: {s['longitude']}")
    else:
        print(f"Seq: {e['sequence']} | ID: {e['stop_id']} (NOT FOUND)")
