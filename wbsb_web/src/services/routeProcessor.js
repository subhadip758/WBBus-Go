// Reusable Route Processing Service for WBBus Go
// Handles road network route fetching, caching, directional selection, and route quality evaluation.

/**
 * Retrieves pre-computed road LineString geometry for a bus and direction from routes_geometry.json
 */
export function loadCachedRouteGeometry(routesGeometryData, busId, direction = 'UP') {
  if (!routesGeometryData || !routesGeometryData.routes) return null;

  const match = routesGeometryData.routes.find(
    r => r.busId === busId && r.direction === direction && r.geometry && r.geometry.type === 'LineString'
  );

  if (match && match.geometry && match.geometry.coordinates && match.geometry.coordinates.length > 0) {
    // GeoJSON coordinates are [longitude, latitude]
    // Convert to Leaflet [latitude, longitude] format
    const leafletLatLngs = match.geometry.coordinates.map(c => [c[1], c[0]]);
    return {
      leafletLatLngs,
      geoJsonGeometry: match.geometry,
      metadata: match.metadata
    };
  }

  // Fallback to any direction if specific direction is unavailable
  const fallback = routesGeometryData.routes.find(
    r => r.busId === busId && r.geometry && r.geometry.type === 'LineString'
  );

  if (fallback && fallback.geometry && fallback.geometry.coordinates) {
    const leafletLatLngs = fallback.geometry.coordinates.map(c => [c[1], c[0]]);
    if (direction === 'DOWN') leafletLatLngs.reverse();
    return {
      leafletLatLngs,
      geoJsonGeometry: fallback.geometry,
      metadata: fallback.metadata
    };
  }

  return null;
}

/**
 * Dynamic fallback OSRM batch routing for ordered stop coordinates
 */
export async function fetchRoadRouteDynamic(coordStops) {
  if (!coordStops || coordStops.length < 2) return [];

  // Deduplicate consecutive identical coordinates
  const uniqueStops = [];
  const seenKey = new Set();
  coordStops.forEach(stop => {
    const key = `${parseFloat(stop.latitude).toFixed(5)},${parseFloat(stop.longitude).toFixed(5)}`;
    if (!seenKey.has(key)) {
      seenKey.add(key);
      uniqueStops.push(stop);
    }
  });

  if (uniqueStops.length < 2) return [];

  // OSRM expects coordinates as lon,lat;lon,lat...
  const coordsStr = uniqueStops.map(s => `${s.longitude},${s.latitude}`).join(';');
  const url = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=geojson&continue_straight=true`;

  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`OSRM HTTP error ${res.status}`);
    const data = await res.json();
    if (data.code === 'Ok' && data.routes && data.routes.length > 0) {
      const geoJsonCoords = data.routes[0].geometry.coordinates; // [[lon, lat], ...]
      const cleaned = cleanCarriagewayUTurns(geoJsonCoords, uniqueStops);
      return cleaned.map(c => [c[1], c[0]]); // Leaflet [lat, lon]
    }
  } catch (err) {
    console.warn("Dynamic OSRM batch routing failed:", err);
  }

  return [];
}

/**
 * Road-aware cleaning of side-carriageway U-turn spikes
 */
function cleanCarriagewayUTurns(coords, stops) {
  if (!coords || coords.length < 4) return coords;

  const deduped = [coords[0]];
  for (let i = 1; i < coords.length; i++) {
    const last = deduped[deduped.length - 1];
    if (Math.abs(coords[i][0] - last[0]) > 1e-6 || Math.abs(coords[i][1] - last[1]) > 1e-6) {
      deduped.push(coords[i]);
    }
  }

  const result = [deduped[0]];
  let i = 1;
  while (i < deduped.length - 1) {
    const prev = result[result.length - 1];
    const curr = deduped[i];
    const nxt = deduped[i + 1];

    const v1 = [curr[0] - prev[0], curr[1] - prev[1]];
    const v2 = [nxt[0] - curr[0], nxt[1] - curr[1]];
    const m1 = Math.hypot(v1[0], v1[1]);
    const m2 = Math.hypot(v2[0], v2[1]);

    if (m1 > 1e-7 && m2 > 1e-7) {
      const dot = Math.max(-1, Math.min(1, (v1[0] * v2[0] + v1[1] * v2[1]) / (m1 * m2)));
      const angle = (Math.acos(dot) * 180) / Math.PI;

      if (angle > 140) {
        // Sharp turnback detected
        let nearStop = false;
        for (const st of stops) {
          const dLat = (curr[1] - st.latitude) * 111.0;
          const dLon = (curr[0] - st.longitude) * 111.0;
          if (Math.hypot(dLat, dLon) < 0.15) { // 150m
            nearStop = true;
            break;
          }
        }
        if (!nearStop) {
          i++;
          continue;
        }
      }
    }
    result.push(curr);
    i++;
  }
  result.push(deduped[deduped.length - 1]);
  return result;
}
