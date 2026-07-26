import json

stops_dict = {s["stop_id"]: s for s in json.load(open(r"wbsb_web\public\data\stops.json", encoding="utf-8"))["stops"]}
timetable = json.load(open(r"wbsb_web\public\data\timetable.json", encoding="utf-8"))["timetable"]
entries = [t for t in timetable if t["bus_id"] == "bus_banerjee_kol_purulia"]

print(f"Total stops for Banerjee: {len(entries)}")
for e in sorted(entries, key=lambda x: x["sequence"]):
    s = stops_dict.get(e["stop_id"])
    if s:
        print(f"  Seq: {e['sequence']} | Name: {s['stop_name']} | Lat: {s['latitude']} | Lng: {s['longitude']}")
    else:
        print(f"  Seq: {e['sequence']} | Stop ID {e['stop_id']} not found in stops.json")
