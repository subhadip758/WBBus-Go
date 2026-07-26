import json
import os

# Define the correct coordinates for the Contai-Digha NH-116B route stops
corrections = {
    "stop_contai": {"latitude": 21.7781, "longitude": 87.7535},
    "stop_ghatua": {"latitude": 21.7525, "longitude": 87.7078},
    "stop_pichaboni": {"latitude": 21.7266, "longitude": 87.6441},
    "stop_chaulkhola": {"latitude": 21.7058, "longitude": 87.6045},
    "stop_balisai": {"latitude": 21.6792, "longitude": 87.5950},
    "stop_choddomail": {"latitude": 21.6715, "longitude": 87.5645},
    "stop_ramnagar": {"latitude": 21.6786, "longitude": 87.5592},
    "stop_thikra_more": {"latitude": 21.6385, "longitude": 87.5255}
}

paths = [
    r"wbsb_web\public\data\stops.json",
    r"wbsb\assets\data\stops.json"
]

for p in paths:
    if os.path.exists(p):
        print(f"Correcting stops in: {p}")
        data = json.load(open(p, encoding="utf-8"))
        updated_count = 0
        for s in data["stops"]:
            s_id = s["stop_id"]
            if s_id in corrections:
                s["latitude"] = corrections[s_id]["latitude"]
                s["longitude"] = corrections[s_id]["longitude"]
                updated_count += 1
        
        # Save updated file
        json.dump(data, open(p, "w", encoding="utf-8"), indent=2)
        print(f"Successfully updated {updated_count} stops in {p}!")
    else:
        print(f"Path not found: {p}")
