import json

timetable = json.load(open(r"wbsb_web\public\data\timetable.json", encoding="utf-8"))["timetable"]
entries = [t for t in timetable if t["bus_id"] == "bus_banerjee_kol_purulia"]
print(f"Total timetable entries for bus_banerjee_kol_purulia: {len(entries)}")
for e in sorted(entries, key=lambda x: x["sequence"])[:10]:
    print(f"  Seq: {e['sequence']} | Stop ID: {e['stop_id']} | Up: {e['up_time']}")
