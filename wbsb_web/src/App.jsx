import React, { useState, useEffect, useRef, useMemo } from 'react';
import { db, auth, isFirebaseConfigured } from './firebase';
import { signInAnonymously } from 'firebase/auth';
import { collection, doc, onSnapshot, setDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { 
  Search, 
  MapPin, 
  Navigation, 
  Clock, 
  Users, 
  CheckCircle, 
  AlertTriangle, 
  ArrowRightLeft, 
  ChevronLeft, 
  Play, 
  Pause, 
  UserPlus, 
  Info,
  Compass,
  FileText,
  SlidersHorizontal,
  Bus
} from 'lucide-react';

// --- MAPLIBRE GL JS COMPATIBILITY SHIM FOR LEAFLET ---
function createGeoJSONCircle(center, radiusInMeters, points = 64) {
  const [lat, lng] = center;
  const km = radiusInMeters / 1000;
  const ret = [];
  const distanceX = km / (111.32 * Math.cos(lat * Math.PI / 180));
  const distanceY = km / 110.57;

  for (let i = 0; i < points; i++) {
    const theta = (i / points) * (2 * Math.PI);
    const x = distanceX * Math.cos(theta);
    const y = distanceY * Math.sin(theta);
    ret.push([lng + x, lat + y]);
  }
  ret.push(ret[0]); // Close the polygon

  return {
    type: 'Feature',
    geometry: {
      type: 'Polygon',
      coordinates: [ret]
    }
  };
}

class MapLibreMarkerWrapper {
  constructor(latlng, options) {
    this.latlng = latlng;
    this.options = options || {};
    this.id = 'marker-' + Math.random().toString(36).substr(2, 9);
    
    // Create HTML container for marker content
    this.element = document.createElement('div');
    this.element.style.position = 'relative';
    
    let htmlContent = null;
    let iconSize = null;
    let iconAnchor = null;
    let className = '';
    
    if (this.options.icon && this.options.icon.options) {
      htmlContent = this.options.icon.options.html;
      iconSize = this.options.icon.options.iconSize;
      iconAnchor = this.options.icon.options.iconAnchor;
      className = this.options.icon.options.className || '';
    }
    
    if (className) {
      this.element.className = className;
    }
    
    if (iconSize) {
      this.element.style.width = iconSize[0] + 'px';
      this.element.style.height = iconSize[1] + 'px';
    }
    
    if (htmlContent) {
      if (typeof htmlContent === 'string') {
        this.element.innerHTML = htmlContent;
      } else if (htmlContent instanceof HTMLElement) {
        this.element.appendChild(htmlContent);
      }
    }
    
    // Determine the anchor and offset for MapLibre Marker to avoid shifting/drifting on zoom
    // Determine the anchor and offset for MapLibre Marker to avoid shifting/drifting on zoom
    let anchor = 'center';
    let offset = [0, 0];
    
    if (iconSize && iconAnchor) {
      anchor = 'center';
      const w = iconSize[0];
      const h = iconSize[1];
      const anchorX = iconAnchor[0];
      const anchorY = iconAnchor[1];
      // Offset relative to element center so center of marker is locked to LngLat
      offset = [w / 2 - anchorX, h / 2 - anchorY];
    } else if (iconSize) {
      anchor = 'center';
      offset = [0, 0];
    } else if (iconAnchor) {
      anchor = 'center';
      offset = [0, 0];
    }
    
    this.marker = new window.maplibregl.Marker({
      element: this.element,
      anchor: anchor,
      offset: offset
    });
  }

  addTo(mapWrapper) {
    this.mapWrapper = mapWrapper;
    const map = mapWrapper._nativeMap || mapWrapper;
    this.marker.setLngLat([this.latlng[1], this.latlng[0]]).addTo(map);
    
    // Add popups/tooltips if bound before addTo
    if (this.popupText) {
      this.bindPopup(this.popupText);
    }
    if (this.tooltipText) {
      this.bindTooltip(this.tooltipText, this.tooltipOptions);
    }
    return this;
  }

  setLatLng(latlng) {
    this.latlng = latlng;
    this.marker.setLngLat([latlng[1], latlng[0]]);
    return this;
  }

  bindPopup(html) {
    this.popupText = html;
    const popup = new window.maplibregl.Popup({ offset: 15, closeButton: false })
      .setHTML(html);
    this.marker.setPopup(popup);
    return this;
  }

  bindTooltip(content, options) {
    this.tooltipText = content;
    this.tooltipOptions = options;
    
    const tooltipPopup = new window.maplibregl.Popup({
      offset: 15,
      closeButton: false,
      closeOnClick: false,
      className: 'custom-stop-tooltip-popup'
    }).setText(content);

    const el = this.marker.getElement();
    
    // Hover event listener
    const onMouseEnter = () => {
      const map = this.mapWrapper ? (this.mapWrapper._nativeMap || this.mapWrapper) : window.mapInstance?.current?._nativeMap;
      if (map) {
        tooltipPopup.setLngLat(this.marker.getLngLat()).addTo(map);
      }
    };
    const onMouseLeave = () => {
      tooltipPopup.remove();
    };

    el.addEventListener('mouseenter', onMouseEnter);
    el.addEventListener('mouseleave', onMouseLeave);
    
    if (options && options.permanent) {
      // If permanent, add it immediately after map is loaded
      setTimeout(() => {
        const map = this.mapWrapper ? (this.mapWrapper._nativeMap || this.mapWrapper) : window.mapInstance?.current?._nativeMap;
        if (map) {
          tooltipPopup.setLngLat(this.marker.getLngLat()).addTo(map);
        }
      }, 300);
    }
    
    // Save listeners to clean up
    this._cleanupTooltip = () => {
      el.removeEventListener('mouseenter', onMouseEnter);
      el.removeEventListener('mouseleave', onMouseLeave);
      tooltipPopup.remove();
    };
    return this;
  }

  remove() {
    if (this._cleanupTooltip) {
      this._cleanupTooltip();
    }
    this.marker.remove();
    return this;
  }
}

class MapLibrePolylineWrapper {
  constructor(latlngs, options) {
    this.latlngs = latlngs;
    this.options = options || {};
    this.id = 'polyline-' + Math.random().toString(36).substr(2, 9);
    this.added = false;
  }

  addTo(mapWrapper) {
    this.mapWrapper = mapWrapper;
    const map = mapWrapper._nativeMap || mapWrapper;
    const coordinates = this.latlngs.map(pt => [pt[1], pt[0]]);
    
    map.addSource(this.id, {
      type: 'geojson',
      data: {
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates: coordinates
        }
      }
    });

    map.addLayer({
      id: this.id + '-layer',
      type: 'line',
      source: this.id,
      layout: {
        'line-join': 'round',
        'line-cap': this.options.lineCap || 'round'
      },
      paint: {
        'line-color': this.options.color || '#1a73e8',
        'line-width': this.options.weight || 5,
        'line-opacity': this.options.opacity || 0.95,
        ...(this.options.dashArray ? { 'line-dasharray': [2, 4] } : {})
      }
    });

    this.added = true;
    return this;
  }

  remove() {
    if (this.added && this.mapWrapper) {
      const map = this.mapWrapper._nativeMap || this.mapWrapper;
      try {
        if (map.getLayer(this.id + '-layer')) map.removeLayer(this.id + '-layer');
        if (map.getSource(this.id)) map.removeSource(this.id);
      } catch (e) {
        console.warn("Error removing polyline layer:", e);
      }
      this.added = false;
    }
    return this;
  }
}

class MapLibreCircleWrapper {
  constructor(latlng, options) {
    this.latlng = latlng;
    this.radius = options.radius || 0;
    this.options = options || {};
    this.id = 'circle-' + Math.random().toString(36).substr(2, 9);
    this.added = false;
  }

  addTo(mapWrapper) {
    this.mapWrapper = mapWrapper;
    const map = mapWrapper._nativeMap || mapWrapper;
    const geojson = createGeoJSONCircle(this.latlng, this.radius);
    
    map.addSource(this.id, {
      type: 'geojson',
      data: geojson
    });

    map.addLayer({
      id: this.id + '-fill',
      type: 'fill',
      source: this.id,
      paint: {
        'fill-color': this.options.fillColor || '#1a73e8',
        'fill-opacity': this.options.fillOpacity || 0.15
      }
    });

    map.addLayer({
      id: this.id + '-stroke',
      type: 'line',
      source: this.id,
      paint: {
        'line-color': this.options.color || '#1a73e8',
        'line-width': this.options.weight || 1
      }
    });

    this.added = true;
    return this;
  }

  setLatLng(latlng) {
    this.latlng = latlng;
    if (this.added && this.mapWrapper) {
      const map = this.mapWrapper._nativeMap || this.mapWrapper;
      const geojson = createGeoJSONCircle(this.latlng, this.radius);
      const source = map.getSource(this.id);
      if (source) source.setData(geojson);
    }
    return this;
  }

  setRadius(radius) {
    this.radius = radius;
    if (this.added && this.mapWrapper) {
      const map = this.mapWrapper._nativeMap || this.mapWrapper;
      const geojson = createGeoJSONCircle(this.latlng, this.radius);
      const source = map.getSource(this.id);
      if (source) source.setData(geojson);
    }
    return this;
  }

  remove() {
    if (this.added && this.mapWrapper) {
      const map = this.mapWrapper._nativeMap || this.mapWrapper;
      try {
        if (map.getLayer(this.id + '-fill')) map.removeLayer(this.id + '-fill');
        if (map.getLayer(this.id + '-stroke')) map.removeLayer(this.id + '-stroke');
        if (map.getSource(this.id)) map.removeSource(this.id);
      } catch (e) {
        console.warn("Error removing circle layers:", e);
      }
      this.added = false;
    }
    return this;
  }
}

const L = {
  map: function(el, options) {
    const map = new window.maplibregl.Map({
      container: el,
      style: {
        version: 8,
        sources: {
          'google-tiles': {
            type: 'raster',
            tiles: [
              'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'
            ],
            tileSize: 256,
            attribution: '&copy; Google Maps'
          }
        },
        layers: [
          {
            id: 'google-tiles-layer',
            type: 'raster',
            source: 'google-tiles',
            minzoom: 0,
            maxzoom: 20
          }
        ]
      },
      center: [88.3529, 22.5626], // [longitude, latitude]
      zoom: 8,
      bearing: 0,
      pitch: 0,
      maxPitch: 0,
      minPitch: 0,
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false,
      attributionControl: false
    });
    
    // Disable rotation completely so scrolling and dragging ONLY pan and zoom the map
    if (map.touchZoomRotate) {
      map.touchZoomRotate.disableRotation();
    }
    if (map.dragRotate) {
      map.dragRotate.disable();
    }
    
    // Add Google Maps style navigation controls
    map.addControl(new window.maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    
    const mapWrapper = {
      _nativeMap: map,
      setView: function(latlng, zoom) {
        this._nativeMap.jumpTo({
          center: [latlng[1], latlng[0]],
          zoom: zoom,
          bearing: 0,
          pitch: 0
        });
        return this;
      },
      panTo: function(latlng) {
        this._nativeMap.panTo([latlng[1], latlng[0]], { bearing: 0, pitch: 0 });
        return this;
      },
      fitBounds: function(bounds, options) {
        const paddingVal = options && options.padding ? (Array.isArray(options.padding) ? options.padding[0] : options.padding) : 50;
        this._nativeMap.fitBounds(bounds, { padding: paddingVal, duration: 1200, bearing: 0, pitch: 0 });
        return this;
      },
      on: function(event, callback) {
        if (event === 'click') {
          this._nativeMap.on('click', (e) => {
            callback({
              latlng: {
                lat: e.lngLat.lat,
                lng: e.lngLat.lng
              }
            });
          });
        } else {
          this._nativeMap.on(event, callback);
        }
        return this;
      }
    };
    
    return mapWrapper;
  },
  tileLayer: function() {
    return {
      addTo: function() { return this; }
    };
  },
  control: {
    attribution: function() {
      return {
        addTo: function() { return this; }
      };
    }
  },
  divIcon: function(options) {
    return { options };
  },
  marker: function(latlng, options) {
    return new MapLibreMarkerWrapper(latlng, options);
  },
  polyline: function(latlngs, options) {
    return new MapLibrePolylineWrapper(latlngs, options);
  },
  circle: function(latlng, options) {
    return new MapLibreCircleWrapper(latlng, options);
  },
  latLngBounds: function(latlngs) {
    const bounds = new window.maplibregl.LngLatBounds();
    latlngs.forEach(coord => {
      bounds.extend([coord[1], coord[0]]);
    });
    return bounds;
  }
};

// --- GEOGRAPHIC UTILITIES ---
const EARTH_RADIUS_KM = 6371.0;

function degToRad(deg) {
  return deg * (Math.PI / 180.0);
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const dLat = degToRad(lat2 - lat1);
  const dLon = degToRad(lon2 - lon1);
  const a = 
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(degToRad(lat1)) *
      Math.cos(degToRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return EARTH_RADIUS_KM * c;
}

// Snaps a 2D lat/lng point onto the closest segment of a polyline line string.
// Guarantees stop circle marker center is 100% attached to the road curve line.
function snapPointToPolyline(lat, lng, polyline) {
  if (!polyline || polyline.length === 0) return [lat, lng];
  if (polyline.length === 1) return polyline[0];

  let minDist = Infinity;
  let snapped = [lat, lng];

  for (let i = 0; i < polyline.length - 1; i++) {
    const a = polyline[i];
    const b = polyline[i + 1];

    const latA = a[0], lngA = a[1];
    const latB = b[0], lngB = b[1];

    const dLat = latB - latA;
    const dLng = lngB - lngA;

    if (dLat === 0 && dLng === 0) {
      const d = haversineKm(lat, lng, latA, lngA);
      if (d < minDist) {
        minDist = d;
        snapped = [latA, lngA];
      }
      continue;
    }

    let t = ((lat - latA) * dLat + (lng - lngA) * dLng) / (dLat * dLat + dLng * dLng);
    t = Math.max(0, Math.min(1, t));

    const projLat = latA + t * dLat;
    const projLng = lngA + t * dLng;

    const d = haversineKm(lat, lng, projLat, projLng);
    if (d < minDist) {
      minDist = d;
      snapped = [projLat, projLng];
    }
  }

  return snapped;
}

function estimatePositionFromHistory(historyData, elapsedSeconds, coordStops, selectedBus) {
  if (!historyData || historyData.length === 0) return null;
  
  // Sort history by sequence
  const sortedHistory = [...historyData].sort((a, b) => a.sequence - b.sequence);
  
  // Find all stops with valid elapsedSeconds
  const knownPoints = sortedHistory.filter(s => s.elapsedSeconds !== null && s.elapsedSeconds !== undefined);
  if (knownPoints.length === 0) return null;
  
  // Calculate a global average speed for fallback extrapolation (km per second)
  let globalAvgSpeedKmS = 35 / 3600; // default 35 km/h
  const lastKnown = knownPoints[knownPoints.length - 1];
  const firstKnown = knownPoints[0];
  const timeDiff = lastKnown.elapsedSeconds - firstKnown.elapsedSeconds;
  const distDiff = lastKnown.cumulativeDistanceKm - firstKnown.cumulativeDistanceKm;
  if (timeDiff > 0 && distDiff > 0) {
    globalAvgSpeedKmS = distDiff / timeDiff;
  }
  
  // Fully populate history with interpolated/extrapolated values
  const fullyPopulatedHistory = sortedHistory.map((s) => {
    if (s.elapsedSeconds !== null && s.elapsedSeconds !== undefined) {
      return { ...s };
    }
    
    // Find nearest previous known stop
    const prevKnown = [...knownPoints].reverse().find(kp => kp.sequence < s.sequence);
    // Find nearest next known stop
    const nextKnown = knownPoints.find(kp => kp.sequence > s.sequence);
    
    let estElapsed = 0;
    if (prevKnown && nextKnown) {
      // Interpolate between prevKnown and nextKnown
      const segmentDist = nextKnown.cumulativeDistanceKm - prevKnown.cumulativeDistanceKm;
      const segmentTime = nextKnown.elapsedSeconds - prevKnown.elapsedSeconds;
      const segSpeed = segmentDist > 0 && segmentTime > 0 ? segmentDist / segmentTime : globalAvgSpeedKmS;
      
      const distFromPrev = s.cumulativeDistanceKm - prevKnown.cumulativeDistanceKm;
      estElapsed = prevKnown.elapsedSeconds + (distFromPrev / segSpeed);
    } else if (prevKnown) {
      // Extrapolate forward from prevKnown
      const distFromPrev = s.cumulativeDistanceKm - prevKnown.cumulativeDistanceKm;
      estElapsed = prevKnown.elapsedSeconds + (distFromPrev / globalAvgSpeedKmS);
    } else if (nextKnown) {
      // Extrapolate backward from nextKnown
      const distToNext = nextKnown.cumulativeDistanceKm - s.cumulativeDistanceKm;
      estElapsed = nextKnown.elapsedSeconds - (distToNext / globalAvgSpeedKmS);
    }
    
    return {
      ...s,
      elapsedSeconds: Math.max(0, Math.round(estElapsed))
    };
  });
  
  // Enforce strict monotonic increase of elapsedSeconds to prevent backward jumping or overlap
  for (let i = 1; i < fullyPopulatedHistory.length; i++) {
    if (fullyPopulatedHistory[i].elapsedSeconds <= fullyPopulatedHistory[i-1].elapsedSeconds) {
      fullyPopulatedHistory[i].elapsedSeconds = fullyPopulatedHistory[i-1].elapsedSeconds + 2;
    }
  }
  
  const lastIndex = fullyPopulatedHistory.length - 1;
  const totalDuration = fullyPopulatedHistory[lastIndex].elapsedSeconds;
  
  // Calculate current interpolated position
  let latitude = 0;
  let longitude = 0;
  let currentStopName = "";
  let nextStopName = "";
  let nextSequence = 0;
  let tripCompleted = false;
  
  if (elapsedSeconds >= totalDuration) {
    const lastStop = fullyPopulatedHistory[lastIndex];
    latitude = lastStop.latitude;
    longitude = lastStop.longitude;
    tripCompleted = true;
    currentStopName = lastStop.stopName;
    nextStopName = null;
    nextSequence = lastStop.sequence;
  } else {
    // Find the segment
    let segStart = fullyPopulatedHistory[0];
    let segEnd = fullyPopulatedHistory[lastIndex];
    
    for (let i = 0; i < fullyPopulatedHistory.length - 1; i++) {
      if (elapsedSeconds >= fullyPopulatedHistory[i].elapsedSeconds && elapsedSeconds < fullyPopulatedHistory[i+1].elapsedSeconds) {
        segStart = fullyPopulatedHistory[i];
        segEnd = fullyPopulatedHistory[i+1];
        break;
      }
    }
    
    const segDuration = segEnd.elapsedSeconds - segStart.elapsedSeconds;
    const progressFraction = segDuration > 0 ? (elapsedSeconds - segStart.elapsedSeconds) / segDuration : 0;
    
    latitude = segStart.latitude + (segEnd.latitude - segStart.latitude) * progressFraction;
    longitude = segStart.longitude + (segEnd.longitude - segStart.longitude) * progressFraction;
    currentStopName = segStart.stopName;
    nextStopName = segEnd.stopName;
    nextSequence = segEnd.sequence;
  }
  
  // Calculate remaining distance in kilometers
  let remainingDistanceKm = 0;
  if (!tripCompleted) {
    // Distance from current position to next stop
    const nextStopIndex = coordStops.findIndex(s => s.sequence === nextSequence);
    if (nextStopIndex !== -1) {
      const nextStop = coordStops[nextStopIndex];
      remainingDistanceKm = haversineKm(latitude, longitude, nextStop.latitude, nextStop.longitude);
      // Distance from next stop to the end of the route
      for (let i = nextStopIndex; i < coordStops.length - 1; i++) {
        remainingDistanceKm += haversineKm(
          coordStops[i].latitude,
          coordStops[i].longitude,
          coordStops[i+1].latitude,
          coordStops[i+1].longitude
        );
      }
    }
  }
  
  // --- REAL-WORLD TIME ESTIMATION ---
  // The simulation clock (elapsedSeconds) is accelerated compared to real-world travel time.
  // To show the CORRECT real-world remaining time (ETA) in minutes:
  // 1. We compute the real-world average speed of this bus from its timetable schedules (if available).
  // 2. Or, we fall back to a realistic West Bengal bus traffic average speed of 35 km/h.
  let scheduledSpeedKmh = 35; // Default fallback
  
  if (selectedBus && selectedBus.routeStops) {
    const stopsWithSchedule = selectedBus.routeStops.filter(s => s.upTime);
    if (stopsWithSchedule.length >= 2) {
      const parseTimeToMinutes = (timeStr) => {
        if (!timeStr) return null;
        const parts = timeStr.split(':');
        if (parts.length !== 2) return null;
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
      };
      
      const firstTime = parseTimeToMinutes(stopsWithSchedule[0].upTime);
      const lastTime = parseTimeToMinutes(stopsWithSchedule[stopsWithSchedule.length - 1].upTime);
      
      if (firstTime !== null && lastTime !== null && lastTime > firstTime) {
        const totalScheduledDurationMinutes = lastTime - firstTime;
        // Total distance along route stops
        let totalRouteDistKm = 0;
        for (let i = 0; i < coordStops.length - 1; i++) {
          totalRouteDistKm += haversineKm(
            coordStops[i].latitude,
            coordStops[i].longitude,
            coordStops[i+1].latitude,
            coordStops[i+1].longitude
          );
        }
        if (totalRouteDistKm > 0) {
          scheduledSpeedKmh = (totalRouteDistKm / totalScheduledDurationMinutes) * 60;
        }
      }
    }
  }
  
  // Ensure scheduledSpeedKmh is in a realistic range (15 to 70 km/h)
  if (scheduledSpeedKmh < 15 || scheduledSpeedKmh > 70) {
    scheduledSpeedKmh = 35;
  }
  
  const etaMinutes = tripCompleted ? 0 : Math.max(1, Math.round((remainingDistanceKm / scheduledSpeedKmh) * 60));
  
  // Calculate simulated bearing/heading
  let headingDegrees = 0;
  if (!tripCompleted) {
    const nextStopIndex = coordStops.findIndex(s => s.sequence === nextSequence);
    if (nextStopIndex !== -1) {
      const nextStop = coordStops[nextStopIndex];
      const dLon = degToRad(nextStop.longitude - longitude);
      const y = Math.sin(dLon) * Math.cos(degToRad(nextStop.latitude));
      const x = Math.cos(degToRad(latitude)) * Math.sin(degToRad(nextStop.latitude)) -
                Math.sin(degToRad(latitude)) * Math.cos(degToRad(nextStop.latitude)) * Math.cos(dLon);
      headingDegrees = ((Math.atan2(y, x) * 180 / Math.PI) + 360) % 360;
    }
  }
  
  const speedKmh = tripCompleted ? 0 : 35;
  
  return {
    latitude,
    longitude,
    speedKmh,
    headingDegrees,
    tripCompleted,
    currentStopName,
    nextStopName,
    remainingDistanceKm,
    etaMinutes,
    nextSequence
  };
}

// --- FUZZY MATCH UTILITIES ---
function levenshtein(a, b) {
  if (a === b) return 0;
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  const dp = Array.from({ length: a.length + 1 }, () => Array(b.length + 1).fill(0));

  for (let i = 0; i <= a.length; i++) dp[i][0] = i;
  for (let j = 0; j <= b.length; j++) dp[0][j] = j;

  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1, // deletion
        dp[i][j - 1] + 1, // insertion
        dp[i - 1][j - 1] + cost // substitution
      );
    }
  }
  return dp[a.length][b.length];
}

function fuzzyContains(haystack, needle) {
  if (!haystack) return false;
  const h = haystack.toLowerCase().trim();
  const n = needle.toLowerCase().trim();
  if (n === '') return true;
  if (h.includes(n)) return true;

  // Alphanumeric clean match for registration numbers (e.g. WB34A1234 matches WB-34-A-1234)
  const hClean = h.replace(/[^a-z0-9]/g, '');
  const nClean = n.replace(/[^a-z0-9]/g, '');
  if (nClean !== '' && hClean.includes(nClean)) return true;

  // Typo tolerance: compare needle against each token
  const words = h.split(/[\s,()]+/).filter(Boolean);
  const maxAllowedDistance = n.length <= 4 ? 1 : 2;
  
  for (const w of words) {
    if (levenshtein(w, n) <= maxAllowedDistance) return true;
    if (w.length >= n.length && levenshtein(w.substring(0, n.length), n) <= maxAllowedDistance) {
      return true;
    }
  }
  return false;
}

// Given a bus and a source/destination search term, return only the slice of
// routeStops between the matched boarding stop and matched alighting stop.
// Falls back to the full route if there's no source/dest context or no valid match.
function getTripStops(bus, source, dest) {
  if (!bus) return [];
  const stops = bus.routeStops;
  const src = (source || '').trim();
  const dst = (dest || '').trim();
  if (!src && !dst) return stops;

  const sourceStops = src
    ? stops.filter(s => fuzzyContains(s.stopName, src) || fuzzyContains(bus.source, src))
    : [];
  const destStops = dst
    ? stops.filter(s => fuzzyContains(s.stopName, dst) || fuzzyContains(bus.destination, dst))
    : [];

  if (sourceStops.length > 0 && destStops.length > 0) {
    const minSourceSeq = Math.min(...sourceStops.map(s => s.sequence));
    const maxDestSeq = Math.max(...destStops.map(s => s.sequence));
    if (minSourceSeq < maxDestSeq) {
      return stops.filter(s => s.sequence >= minSourceSeq && s.sequence <= maxDestSeq);
    }
  }
  return stops;
}

// --- CORE CROWDSOURCING & RESOLUTION LOGIC ---
const MIN_ACCEPTABLE_ACCURACY = 75; // meters
const MAX_PLAUSIBLE_SPEED_KMH = 130;
const CLUSTER_RADIUS_METERS = 250;

// Resolve multiple rider contributions into a single location
function resolveLiveLocation(busId, contributions) {
  const now = new Date();
  
  // 1. Filter out stale fixes (>90s)
  const fresh = contributions.filter(c => (now - c.updatedAt) <= 90000);
  
  // 2. Filter out poor accuracy (>75m)
  const accurateEnough = fresh.filter(c => c.accuracyMeters <= MIN_ACCEPTABLE_ACCURACY);
  
  // 3. Filter out implausible speed (>130kmh)
  const speedValid = accurateEnough.filter(c => c.speedKmh === null || c.speedKmh <= MAX_PLAUSIBLE_SPEED_KMH);
  
  if (speedValid.length === 0) return null;
  
  // 4. Find the largest cluster within 250m
  const cluster = findLargestCluster(speedValid);
  
  // If 2 or more active contributors agree on a cluster, compute weighted average
  if (cluster.length >= 2) {
    const averaged = weightedAverageLatLng(cluster);
    const combinedAccuracy = combinedAccuracyMeters(cluster);
    
    // Average speed and heading
    const speeds = cluster.map(c => c.speedKmh).filter(s => s !== null && s !== undefined);
    const avgSpeed = speeds.length > 0 ? speeds.reduce((a, b) => a + b, 0) / speeds.length : null;
    
    const headings = cluster.map(c => c.headingDegrees).filter(h => h !== null && h !== undefined);
    const avgHeading = headings.length > 0 ? headings.reduce((a, b) => a + b, 0) / headings.length : null;
    
    const latestUpdate = new Date(Math.max(...cluster.map(c => c.updatedAt)));
    
    return {
      busId,
      latitude: averaged[0],
      longitude: averaged[1],
      accuracyMeters: combinedAccuracy,
      speedKmh: avgSpeed,
      headingDegrees: avgHeading,
      updatedAt: latestUpdate,
      contributorCount: speedValid.length,
      clusteredContributorCount: cluster.length,
      confidenceScore: calculateConfidenceScore(cluster.length, combinedAccuracy)
    };
  }
  
  // Fallback to the single most recent accurate fix
  const sorted = [...speedValid].sort((a, b) => b.updatedAt - a.updatedAt);
  const best = sorted[0];
  
  return {
    busId,
    latitude: best.latitude,
    longitude: best.longitude,
    accuracyMeters: best.accuracyMeters,
    speedKmh: best.speedKmh,
    headingDegrees: best.headingDegrees,
    updatedAt: best.updatedAt,
    contributorCount: speedValid.length,
    clusteredContributorCount: 1,
    confidenceScore: calculateConfidenceScore(1, best.accuracyMeters)
  };
}

function findLargestCluster(pool) {
  let best = [];
  for (const seed of pool) {
    const group = pool.filter(c => {
      const distKm = haversineKm(seed.latitude, seed.longitude, c.latitude, c.longitude);
      return distKm * 1000 <= CLUSTER_RADIUS_METERS;
    });
    if (group.length > best.length) {
      best = group;
    }
  }
  return best;
}

function weightedAverageLatLng(cluster) {
  let sumLatW = 0, sumLngW = 0, sumW = 0;
  for (const c of cluster) {
    const w = 1 / (c.accuracyMeters * c.accuracyMeters);
    sumLatW += c.latitude * w;
    sumLngW += c.longitude * w;
    sumW += w;
  }
  return [sumLatW / sumW, sumLngW / sumW];
}

function combinedAccuracyMeters(cluster) {
  let sumInverseVariance = 0;
  for (const c of cluster) {
    sumInverseVariance += 1 / (c.accuracyMeters * c.accuracyMeters);
  }
  if (sumInverseVariance <= 0) return cluster[0].accuracyMeters;
  return Math.sqrt(1 / sumInverseVariance);
}

function calculateConfidenceScore(clusterSize, accuracyMeters) {
  const accuracyScore = Math.max(0, Math.min(1, 1 - (accuracyMeters / MIN_ACCEPTABLE_ACCURACY)));
  const agreementBoost = (clusterSize - 1) * 0.15;
  return Math.max(0, Math.min(1, accuracyScore + agreementBoost));
}

// Compute trip progress along stops path
function calculateTripProgress(bus, location) {
  const stopsWithCoords = bus.routeStops
    .filter(s => s.latitude !== null && s.latitude !== undefined)
    .sort((a, b) => a.sequence - b.sequence);
    
  if (stopsWithCoords.length < 2) {
    return { hasSufficientData: false };
  }
  
  // Find nearest stop with coordinates
  let nearest = stopsWithCoords[0];
  let nearestDistKm = haversineKm(location.latitude, location.longitude, nearest.latitude, nearest.longitude);
  
  for (let i = 1; i < stopsWithCoords.length; i++) {
    const stop = stopsWithCoords[i];
    const d = haversineKm(location.latitude, location.longitude, stop.latitude, stop.longitude);
    if (d < nearestDistKm) {
      nearest = stop;
      nearestDistKm = d;
    }
  }
  
  const nearestIndex = stopsWithCoords.indexOf(nearest);
  const isLastCoordStop = nearestIndex === stopsWithCoords.length - 1;
  
  // Trip completion: within 300m of last sequence stop
  const finalStop = bus.routeStops.reduce((a, b) => a.sequence > b.sequence ? a : b);
  const tripCompleted = nearest.sequence === finalStop.sequence && nearestDistKm <= 0.3;
  
  const nextStop = isLastCoordStop ? null : stopsWithCoords[nearestIndex + 1];
  
  const remainingStopsCount = bus.routeStops.filter(s => s.sequence > nearest.sequence).length;
  
  // Remaining distance: sum of distance to nearest stop, plus hop distances for remaining path
  let remainingDistanceKm = nearestDistKm;
  for (let i = nearestIndex; i < stopsWithCoords.length - 1; i++) {
    remainingDistanceKm += haversineKm(
      stopsWithCoords[i].latitude,
      stopsWithCoords[i].longitude,
      stopsWithCoords[i + 1].latitude,
      stopsWithCoords[i + 1].longitude
    );
  }
  
  // Speed estimation
  const speedForEta = (location.speedKmh !== null && location.speedKmh >= 10 && location.speedKmh <= 80)
    ? location.speedKmh
    : 30; // default 30kmh
    
  const etaMinutes = tripCompleted ? 0 : Math.round((remainingDistanceKm / speedForEta) * 60);
  
  // Compute delay against scheduled up_time
  const delayMinutes = computeDelayMinutes(nearest, location.updatedAt);
  
  return {
    hasSufficientData: true,
    currentStopName: nearest.stopName,
    nextStopName: nextStop ? nextStop.stopName : null,
    remainingStopsCount,
    remainingDistanceKm,
    etaMinutes,
    delayMinutes,
    tripCompleted
  };
}

function computeDelayMinutes(nearest, observedAt) {
  const scheduled = nearest.upTime;
  if (!scheduled) return null;
  const parts = scheduled.split(':');
  if (parts.length !== 2) return null;
  const schedH = parseInt(parts[0], 10);
  const schedM = parseInt(parts[1], 10);
  if (isNaN(schedH) || isNaN(schedM)) return null;
  
  const scheduledMinutes = schedH * 60 + schedM;
  const actualMinutes = observedAt.getHours() * 60 + observedAt.getMinutes();
  return actualMinutes - scheduledMinutes;
}

// Exact road-following router using OSRM through ALL consecutive bus stops (like Google Maps)
async function fetchRoadRoute(coordStops) {
  if (!coordStops || coordStops.length < 2) return [];

  // Deduplicate nearby coordinates (rounding to 5 decimal places is ~1.1 meters)
  const uniqueStops = [];
  const seenCoords = new Set();
  coordStops.forEach(stop => {
    const latKey = parseFloat(stop.latitude).toFixed(5);
    const lngKey = parseFloat(stop.longitude).toFixed(5);
    const key = `${latKey},${lngKey}`;
    if (!seenCoords.has(key)) {
      seenCoords.add(key);
      uniqueStops.push(stop);
    }
  });

  if (uniqueStops.length < 2) return [];

  // 1. Try full multi-waypoint OSRM driving route first for a seamless real-world road path like Google Maps
  try {
    const coordsString = uniqueStops.map(s => `${s.longitude},${s.latitude}`).join(';');
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsString}?overview=full&geometries=geojson`;
    const res = await fetch(url);
    if (res.ok) {
      const data = await res.json();
      if (data.code === 'Ok' && data.routes && data.routes.length > 0) {
        const roadCoords = data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);
        if (roadCoords && roadCoords.length > 0) {
          return roadCoords;
        }
      }
    }
  } catch (err) {
    console.warn("Full multi-waypoint OSRM query failed, falling back to leg-by-leg routing:", err);
  }

  // 2. Fallback: leg-by-leg OSRM routing between consecutive stop pairs
  const queryOSRMLeg = async (s1, s2) => {
    const url = `https://router.project-osrm.org/route/v1/driving/${s1.longitude},${s1.latitude};${s2.longitude},${s2.latitude}?overview=full&geometries=geojson`;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`OSRM HTTP error ${res.status}`);
    const data = await res.json();
    if (data.code !== 'Ok' || !data.routes || data.routes.length === 0) {
      throw new Error(`OSRM routing failed with code ${data.code}`);
    }
    return data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]); // [lat, lng]
  };

  const allRoadPoints = [];

  for (let i = 0; i < uniqueStops.length - 1; i++) {
    const a = uniqueStops[i];
    const b = uniqueStops[i + 1];

    let legPoints = null;
    try {
      legPoints = await queryOSRMLeg(a, b);
    } catch (err) {
      console.warn(`Leg routing ${a.stopName || a.stop_name} -> ${b.stopName || b.stop_name} failed:`, err);
    }

    if (!legPoints || legPoints.length === 0) {
      legPoints = [[a.latitude, a.longitude], [b.latitude, b.longitude]];
    }

    if (allRoadPoints.length > 0 &&
        legPoints[0][0] === allRoadPoints[allRoadPoints.length - 1][0] &&
        legPoints[0][1] === allRoadPoints[allRoadPoints.length - 1][1]) {
      legPoints = legPoints.slice(1);
    }
    allRoadPoints.push(...legPoints);
  }

  return allRoadPoints.length > 0 ? allRoadPoints : uniqueStops.map(s => [s.latitude, s.longitude]);
}

// --- MAIN REACT COMPONENT ---
function App() {
  const [busesData, setBusesData] = useState([]);
  const [routesData, setRoutesData] = useState({});
  const [stopsData, setStopsData] = useState({});
  const [timetableData, setTimetableData] = useState({});
  const [operatorsData, setOperatorsData] = useState([]);
  const [agenciesData, setAgenciesData] = useState([]);
  
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [sourceFilter, setSourceFilter] = useState('');
  const [destFilter, setDestFilter] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  
  const [selectedBus, setSelectedBus] = useState(null);

  // Parse general query for route indicators (like source to destination)
  const parsedQueryRoute = useMemo(() => {
    const q = searchQuery.trim();
    if (!q) return null;
    const splitters = [/\s+to\s+/i, /\s*->\s*/, /\s*-\s*/, /\s*↔\s*/];
    for (const regex of splitters) {
      if (regex.test(q)) {
        const parts = q.split(regex);
        if (parts.length === 2 && parts[0].trim() && parts[1].trim()) {
          return { source: parts[0].trim(), dest: parts[1].trim() };
        }
      }
    }
    const words = q.split(/\s+/).filter(Boolean);
    if (words.length === 2) {
      return { source: words[0], dest: words[1] };
    }
    return null;
  }, [searchQuery]);

  const effectiveSource = sourceFilter.trim() !== '' ? sourceFilter : (parsedQueryRoute ? parsedQueryRoute.source : '');
  const effectiveDest = destFilter.trim() !== '' ? destFilter : (parsedQueryRoute ? parsedQueryRoute.dest : '');

  // The stops between YOUR searched source and destination for the selected bus
  // (trimmed from the bus's full end-to-end route) — used for the timeline & map display.
  const tripStops = useMemo(
    () => getTripStops(selectedBus, effectiveSource, effectiveDest),
    [selectedBus, effectiveSource, effectiveDest]
  );
  
  // Startup Geolocation & Navigation State
  const [userStartupCoords, setUserStartupCoords] = useState(null);
  
  // History tracking and GPS loss fallback states
  const [stopArrivalTimes, setStopArrivalTimes] = useState({}); // { sequence: elapsedSeconds }
  const [tripElapsedSeconds, setTripElapsedSeconds] = useState(0);
  const [loseGpsSignal, setLoseGpsSignal] = useState(false);
  const [simulateGpsOutage, setSimulateGpsOutage] = useState(false);
  const [hasHistoryData, setHasHistoryData] = useState(false);
  
  // Crowdsourcing simulated states
  const [isTracking, setIsTracking] = useState(false);
  const [useSimulation, setUseSimulation] = useState(false); // only live data, no simulation
  const [realCoords, setRealCoords] = useState(null); // holds real device GPS coordinates
  const [myLocationIndex, setMyLocationIndex] = useState(0); // Index along the coordinates array of route stops
  const [myLocationOffset, setMyLocationOffset] = useState(0); // Interpolation factor (0 to 1) between current and next stop
  const [simSpeedMultiplier, setSimSpeedMultiplier] = useState(1); // 1x, 2x, 5x, 10x
  const [myAccuracy, setMyAccuracy] = useState(25); // 10m to 100m
  const [addRiders, setAddRiders] = useState(false); // disable simulated virtual riders by default
  const [ridersAccuracy, setRidersAccuracy] = useState(40); // virtual riders error
  
  // Resolved dynamic values
  const [contributions, setContributions] = useState([]);
  const [resolvedLoc, setResolvedLoc] = useState(null);
  const [progress, setProgress] = useState(null);
  const [isPlaying, setIsPlaying] = useState(true);
  
  // Firebase Live Sync States
  const [firebaseSync, setFirebaseSync] = useState(isFirebaseConfigured);
  const [firebaseError, setFirebaseError] = useState(null);
  const [mySessionId, setMySessionId] = useState(null);
  const [remoteContributions, setRemoteContributions] = useState([]);
  const [userCoords, setUserCoords] = useState(null);
  
  // Leaflet refs
  const mapRef = useRef(null);
  const mapInstance = useRef(null);
  const mapMarkers = useRef({});
  const routePolyline = useRef(null);
  const routePolylineBorder = useRef(null);
  const roadRoutePointsRef = useRef([]);
  const resolvedBusAnimRef = useRef(null);
  
  // Startup Geolocation Permission Request
  const requestStartupLocation = () => {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const { latitude, longitude } = position.coords;
          console.log("Startup location access granted:", latitude, longitude);
          setUserStartupCoords({ latitude, longitude });
        },
        (error) => {
          console.warn("Startup location access denied or failed:", error.message);
        },
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
      );
    }
  };

  useEffect(() => {
    requestStartupLocation();
  }, []);

  // Update map view and add user location pin when startup location is loaded
  useEffect(() => {
    if (mapInstance.current && userStartupCoords) {
      if (!selectedBus) {
        mapInstance.current.setView([userStartupCoords.latitude, userStartupCoords.longitude], 12);
      }
      
      // Clean up previous startup pin if any
      if (mapMarkers.current['startup_user_pin']) {
        mapMarkers.current['startup_user_pin'].remove();
      }
      
      // Create user marker
      const userDivIcon = L.divIcon({
        className: 'custom-div-icon',
        html: '<div class="marker-pin marker-user"></div>',
        iconSize: [30, 42],
        iconAnchor: [15, 42]
      });
      
      const pin = L.marker([userStartupCoords.latitude, userStartupCoords.longitude], { icon: userDivIcon })
        .addTo(mapInstance.current)
        .bindPopup("Your Current Location");
        
      mapMarkers.current['startup_user_pin'] = pin;
    }
  }, [userStartupCoords, selectedBus]);

  // Fetch initial datasets
  useEffect(() => {
    async function loadDatasets() {
      try {
        const v = Date.now();
        const [busesRes, routesRes, stopsRes, timetableRes, operatorsRes, agenciesRes] = await Promise.all([
          fetch(`/data/buses.json?v=${v}`).then(r => r.json()),
          fetch(`/data/routes.json?v=${v}`).then(r => r.json()),
          fetch(`/data/stops.json?v=${v}`).then(r => r.json()),
          fetch(`/data/timetable.json?v=${v}`).then(r => r.json()),
          fetch(`/data/operators.json?v=${v}`).then(r => r.json()),
          fetch(`/data/agencies.json?v=${v}`).then(r => r.json())
        ]);
        
        // Parse into mapping dictionaries
        const stopsMap = {};
        stopsRes.stops.forEach(s => {
          stopsMap[s.stop_id] = s;
        });
        
        const routesMap = {};
        routesRes.routes.forEach(r => {
          routesMap[r.route_id] = r;
        });
        
        const timetableMap = {};
        timetableRes.timetable.forEach(t => {
          if (!timetableMap[t.bus_id]) timetableMap[t.bus_id] = [];
          timetableMap[t.bus_id].push(t);
        });
        
        // Sort timetables by sequence
        Object.keys(timetableMap).forEach(busId => {
          timetableMap[busId].sort((a, b) => a.sequence - b.sequence);
        });
        
        // Hydrate buses
        const hydratedBuses = busesRes.buses.map(bus => {
          const timetableEntries = timetableMap[bus.bus_id] || [];
          const routeStops = timetableEntries.map(entry => {
            const stop = stopsMap[entry.stop_id];
            return {
              sequence: entry.sequence,
              stopId: entry.stop_id,
              stopName: stop ? stop.stop_name : 'Unknown Stop',
              latitude: stop ? stop.latitude : null,
              longitude: stop ? stop.longitude : null,
              upTime: entry.up_time,
              downTime: entry.down_time
            };
          });
          
          return {
            ...bus,
            routeStops
          };
        });
        
        setBusesData(hydratedBuses);
        setRoutesData(routesMap);
        setStopsData(stopsMap);
        setTimetableData(timetableMap);
        setOperatorsData(operatorsRes.operators);
        setAgenciesData(agenciesRes.agencies);
        
        setLoading(false);
      } catch (err) {
        console.error("Error loading json files:", err);
      }
    }
    loadDatasets();
  }, []);
  
  // Leaflet Map Initialization
  useEffect(() => {
    let resizeObserver = null;
    if (!loading && mapRef.current && !mapInstance.current) {
      // Centered on West Bengal (Kolkata region)
      mapInstance.current = L.map(mapRef.current, {
        zoomControl: true,
        attributionControl: false
      }).setView([22.5626, 88.3529], 8);
      
      L.tileLayer('https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png', {
        maxZoom: 19
      }).addTo(mapInstance.current);
      
      L.control.attribution({ prefix: false }).addTo(mapInstance.current);

      // Add ResizeObserver to handle container resizing automatically.
      // This solves the issue of lines (polylines) and markers shifting/drifting on zoom
      // due to canvas size mismatches with its CSS container dimensions.
      const nativeMap = mapInstance.current._nativeMap;
      if (nativeMap) {
        resizeObserver = new ResizeObserver(() => {
          nativeMap.resize();
        });
        resizeObserver.observe(mapRef.current);
      }
    }

    return () => {
      if (resizeObserver) {
        resizeObserver.disconnect();
      }
    };
  }, [loading]);
  
  // Firebase Anonymous Auth Setup
  useEffect(() => {
    if (isFirebaseConfigured && auth) {
      signInAnonymously(auth)
        .then((cred) => {
          setMySessionId(cred.user.uid);
          console.log("Authenticated anonymously with UID:", cred.user.uid);
          setFirebaseError(null);
        })
        .catch((err) => {
          console.error("Anonymous authentication failed:", err);
          setFirebaseError("Auth failed: " + err.message);
          setFirebaseSync(false);
        });
    }
  }, []);

  // Firebase Firestore Real-time Listener for Active Contributions
  useEffect(() => {
    if (!selectedBus || !firebaseSync || !db) {
      setRemoteContributions([]);
      return;
    }

    const activeCol = collection(db, 'ride_sessions', selectedBus.bus_id, 'active');
    const unsubscribe = onSnapshot(activeCol, (snapshot) => {
      const remote = [];
      snapshot.forEach((doc) => {
        const data = doc.data();
        const docId = doc.id;
        
        // Skip our own session to avoid jitter since we update our local position instantly
        if (docId === mySessionId) return;

        let updatedAt = new Date();
        if (data.updatedAt) {
          if (typeof data.updatedAt.toDate === 'function') {
            updatedAt = data.updatedAt.toDate();
          } else {
            updatedAt = new Date(data.updatedAt);
          }
        }

        remote.push({
          sessionId: docId,
          latitude: Number(data.latitude),
          longitude: Number(data.longitude),
          accuracyMeters: Number(data.accuracyMeters),
          speedKmh: data.speedKmh !== undefined ? Number(data.speedKmh) : null,
          headingDegrees: data.headingDegrees !== undefined ? Number(data.headingDegrees) : null,
          updatedAt: updatedAt
        });
      });
      setRemoteContributions(remote);
      setFirebaseError(null);
    }, (error) => {
      console.error("Firestore real-time sync failed:", error);
      setFirebaseError("Firestore sync failed: " + error.message);
    });

    return () => unsubscribe();
  }, [selectedBus, firebaseSync, mySessionId]);

  // Delete user contribution from Firestore when tracking stops
  useEffect(() => {
    if (!isTracking && selectedBus && db && mySessionId && firebaseSync) {
      const userDoc = doc(db, 'ride_sessions', selectedBus.bus_id, 'active', mySessionId);
      deleteDoc(userDoc).catch((err) => {
        console.error("Failed to delete user contribution on stop:", err);
      });
    }
  }, [isTracking, selectedBus, mySessionId, firebaseSync]);
  
  // Handle Bus Selection Change - update map viewport and markers
  useEffect(() => {
    if (!mapInstance.current) return;
    const nativeMap = mapInstance.current._nativeMap || mapInstance.current;
    
    let isCurrent = true;
    
    // Clear old WebGL layers if present
    try {
      if (nativeMap.getLayer('wbsb-stops-label')) nativeMap.removeLayer('wbsb-stops-label');
      if (nativeMap.getLayer('wbsb-stops-inner')) nativeMap.removeLayer('wbsb-stops-inner');
      if (nativeMap.getLayer('wbsb-stops-outer')) nativeMap.removeLayer('wbsb-stops-outer');
      if (nativeMap.getSource('wbsb-stops-source')) nativeMap.removeSource('wbsb-stops-source');
    } catch (e) {
      console.warn("WebGL layer cleanup:", e);
    }
    
    // Clear old map markers
    Object.values(mapMarkers.current).forEach(m => m.remove());
    mapMarkers.current = {};
    if (routePolyline.current) {
      routePolyline.current.remove();
      routePolyline.current = null;
    }
    if (routePolylineBorder.current) {
      routePolylineBorder.current.remove();
      routePolylineBorder.current = null;
    }
    
    if (!selectedBus) return;
    
    // Filter stops on route that have coordinates (trimmed to the searched source→destination segment)
    const coordStops = tripStops.filter(s => s.latitude !== null && s.longitude !== null);
    
    if (coordStops.length > 0) {
      const latlngs = coordStops.map(s => [s.latitude, s.longitude]);

      // WebGL native renderer: renders small circles directly inside WebGL pass locked on the curve line
      const renderWebGLStops = (currentPolyline) => {
        // Clear previous stop label markers
        Object.values(mapMarkers.current).forEach(m => m.remove());
        mapMarkers.current = {};

        const features = coordStops.map((stop, index) => {
          const snapped = snapPointToPolyline(stop.latitude, stop.longitude, currentPolyline);
          const letterLabel = String.fromCharCode(65 + (index % 26)) + (index >= 26 ? Math.floor(index / 26) : '');
          
          // Add stop name label badge right beside the circle node
          const labelDiv = document.createElement('div');
          labelDiv.className = 'custom-stop-label-badge';
          labelDiv.style.display = 'inline-flex';
          labelDiv.style.alignItems = 'center';
          labelDiv.style.gap = '4px';
          labelDiv.style.background = 'rgba(15, 23, 42, 0.9)';
          labelDiv.style.color = '#ffffff';
          labelDiv.style.padding = '2px 6px';
          labelDiv.style.borderRadius = '6px';
          labelDiv.style.fontSize = '11px';
          labelDiv.style.fontWeight = '600';
          labelDiv.style.fontFamily = 'Inter, system-ui, sans-serif';
          labelDiv.style.whiteSpace = 'nowrap';
          labelDiv.style.boxShadow = '0 2px 6px rgba(0,0,0,0.3)';
          labelDiv.style.border = '1px solid rgba(255,255,255,0.2)';
          labelDiv.style.pointerEvents = 'auto';

          labelDiv.innerHTML = `<span style="background: #f59e0b; color: #0f172a; padding: 0 4px; border-radius: 3px; font-weight: 800; font-size: 10px;">${letterLabel}</span> <span>${stop.stopName}</span>`;

          const labelIcon = L.divIcon({
            className: 'custom-stop-label-wrapper',
            html: labelDiv,
            iconSize: [0, 0],
            iconAnchor: [-10, 8] // Positioned right beside the small circle node
          });

          const marker = L.marker(snapped, { icon: labelIcon })
            .addTo(mapInstance.current)
            .bindPopup(`<strong>Stop ${letterLabel}: ${stop.stopName}</strong><br/>Sequence: ${stop.sequence}${stop.upTime ? `<br/>Scheduled: ${stop.upTime}` : ''}`);

          mapMarkers.current[`stop_${stop.stopId}`] = marker;

          return {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [snapped[1], snapped[0]] // [lng, lat]
            },
            properties: {
              stopId: stop.stopId,
              stopName: stop.stopName,
              label: letterLabel,
              sequence: stop.sequence,
              upTime: stop.upTime || ''
            }
          };
        });

        const geojson = {
          type: 'FeatureCollection',
          features: features
        };

        const source = nativeMap.getSource('wbsb-stops-source');
        if (source) {
          source.setData(geojson);
        } else {
          nativeMap.addSource('wbsb-stops-source', {
            type: 'geojson',
            data: geojson
          });

          // Outer circle (white background with dark border centered on curve line)
          nativeMap.addLayer({
            id: 'wbsb-stops-outer',
            type: 'circle',
            source: 'wbsb-stops-source',
            paint: {
              'circle-radius': 7,
              'circle-color': '#ffffff',
              'circle-stroke-color': '#0f172a',
              'circle-stroke-width': 2.5
            }
          });

          // Inner solid circle dot
          nativeMap.addLayer({
            id: 'wbsb-stops-inner',
            type: 'circle',
            source: 'wbsb-stops-source',
            paint: {
              'circle-radius': 2.5,
              'circle-color': '#0f172a'
            }
          });
        }
      };

      // Draw initial fallback polyline and WebGL stop circles
      routePolyline.current = L.polyline(latlngs, {
        color: '#d97706',
        weight: 4,
        dashArray: '5, 10',
        opacity: 0.85
      }).addTo(mapInstance.current);

      renderWebGLStops(latlngs);

      // Reset roadRoutePointsRef
      roadRoutePointsRef.current = [];

      // Fetch exact road geometry from OSRM and update WebGL line & stop circles
      fetchRoadRoute(coordStops)
        .then(roadLatLngs => {
          if (!isCurrent) return;

          if (roadLatLngs && roadLatLngs.length > 0) {
            roadRoutePointsRef.current = roadLatLngs;

            if (routePolyline.current) routePolyline.current.remove();
            if (routePolylineBorder.current) routePolylineBorder.current.remove();

            // Outline border and main blue road path
            routePolylineBorder.current = L.polyline(roadLatLngs, {
              color: '#1558b0',
              weight: 8,
              opacity: 0.65,
              lineCap: 'round',
              lineJoin: 'round'
            }).addTo(mapInstance.current);

            routePolyline.current = L.polyline(roadLatLngs, {
              color: '#1a73e8',
              weight: 5,
              opacity: 0.95,
              lineCap: 'round',
              lineJoin: 'round'
            }).addTo(mapInstance.current);

            // Re-render WebGL stop circles snapped 100% on top of exact road curve line
            renderWebGLStops(roadLatLngs);
          }
        })
        .catch(err => {
          console.warn("OSRM routing service failed:", err);
        });

      // Fit bounds to route
      const bounds = L.latLngBounds(latlngs);
      mapInstance.current.fitBounds(bounds, { padding: [50, 50] });
    }
    
    // Reset simulation tracking index when changing bus
    setIsTracking(false);
    setMyLocationIndex(0);
    setMyLocationOffset(0);
    setContributions([]);
    setResolvedLoc(null);
    setProgress(null);
    setStopArrivalTimes({});
    setTripElapsedSeconds(0);
    setLoseGpsSignal(false);
    setSimulateGpsOutage(false);
    
    if (selectedBus) {
      try {
        const savedHistory = localStorage.getItem(`wbsb_history_${selectedBus.bus_id}`);
        setHasHistoryData(!!savedHistory);
      } catch (err) {
        console.error("Error reading history from localStorage:", err);
        setHasHistoryData(false);
      }
    } else {
      setHasHistoryData(false);
    }
    
    return () => {
      isCurrent = false;
    };
  }, [selectedBus, tripStops]);
  
  // Real GPS Device Watcher Effect
  useEffect(() => {
    if (!isTracking || useSimulation) {
      setRealCoords(null);
      return;
    }

    if (!navigator.geolocation) {
      alert("Geolocation is not supported by your browser. Falling back to Simulation Mode.");
      setUseSimulation(true);
      return;
    }

    const handleSuccess = (position) => {
      const { latitude, longitude, accuracy, speed, heading } = position.coords;
      setRealCoords({
        latitude,
        longitude,
        accuracyMeters: accuracy || 10,
        speedKmh: speed ? speed * 3.6 : 0, // convert m/s to km/h
        headingDegrees: heading || 0,
        updatedAt: new Date(position.timestamp)
      });
      // Automatically recover GPS signal if fresh data arrives
      if (!simulateGpsOutage) {
        setLoseGpsSignal(false);
      }
    };

    const handleError = (error) => {
      console.warn("Geolocation watch error:", error.message);
      if (hasHistoryData) {
        console.warn("Auto switching to history fallback due to GPS error:", error.message);
        setLoseGpsSignal(true);
      }
    };

    const watchId = navigator.geolocation.watchPosition(handleSuccess, handleError, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 0
    });

    return () => navigator.geolocation.clearWatch(watchId);
  }, [isTracking, useSimulation]);

  // Handle simulation mode signal loss mapping
  useEffect(() => {
    if (useSimulation) {
      setLoseGpsSignal(simulateGpsOutage);
    }
  }, [useSimulation, simulateGpsOutage]);

  // Monitor Real GPS signal health & automatically trigger fallback on loss
  useEffect(() => {
    if (!isTracking || useSimulation) return;
    if (!hasHistoryData) return;

    const interval = setInterval(() => {
      if (simulateGpsOutage) {
        setLoseGpsSignal(true);
        return;
      }

      const now = Date.now();
      const lastUpdate = realCoords ? new Date(realCoords.updatedAt).getTime() : 0;
      
      if (!realCoords) {
        // If tracking is active but we got no coordinate update for 6 seconds on startup
        if (tripElapsedSeconds > 6) {
          console.warn("GPS signal not received on startup. Auto switching to history fallback.");
          setLoseGpsSignal(true);
        }
      } else if (now - lastUpdate > 8000) {
        // Stale coordinates: no update within 8 seconds
        console.warn("GPS signal lost (stale). Auto switching to history fallback.");
        setLoseGpsSignal(true);
      }
    }, 2000);

    return () => clearInterval(interval);
  }, [isTracking, useSimulation, realCoords, tripElapsedSeconds, hasHistoryData, simulateGpsOutage]);

  // Simulation & Time Loop Effect: Updates user position and increments elapsed time
  useEffect(() => {
    if (!selectedBus || !isTracking || !isPlaying) return;
    
    const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
    if (coordStops.length < 2) return;
    
    const intervalTime = 1000; // tick every 1 second
    
    const timer = setInterval(() => {
      // Increment elapsed trip time based on simulation speed
      setTripElapsedSeconds(prev => prev + 1 * simSpeedMultiplier);
      
      if (useSimulation && !loseGpsSignal) {
        setMyLocationOffset(offset => {
          let nextOffset = offset + (0.05 * simSpeedMultiplier);
          if (nextOffset >= 1.0) {
            // Move to next leg
            let finished = false;
            setMyLocationIndex(idx => {
              const nextIdx = idx + 1;
              if (nextIdx >= coordStops.length - 1) {
                finished = true;
                return coordStops.length - 1;
              }
              return nextIdx;
            });
            if (finished) {
              setIsPlaying(false);
              return 0;
            }
            return 0;
          }
          return nextOffset;
        });
      }
    }, intervalTime);
    
    return () => clearInterval(timer);
  }, [selectedBus, isTracking, simSpeedMultiplier, isPlaying, useSimulation, loseGpsSignal]);
  
  // 1. Compute user position and update local state
  useEffect(() => {
    if (!selectedBus || !isTracking) {
      setUserCoords(null);
      return;
    }
    
    const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
    if (coordStops.length < 2) return;
    
    // GPS Signal Lost Fallback Logic
    if (loseGpsSignal) {
      try {
        const savedHistory = localStorage.getItem(`wbsb_history_${selectedBus.bus_id}`);
        let historyData = null;
        if (savedHistory) {
          historyData = JSON.parse(savedHistory);
        } else {
          // Generate default mock history so fallback works for all buses even if no prior run
          let cumulativeDistanceKm = 0;
          historyData = coordStops.map((s, idx) => {
            if (idx > 0) {
              cumulativeDistanceKm += haversineKm(
                coordStops[idx - 1].latitude,
                coordStops[idx - 1].longitude,
                s.latitude,
                s.longitude
              );
            }
            return {
              sequence: s.sequence,
              stopId: s.stopId,
              stopName: s.stopName,
              latitude: s.latitude,
              longitude: s.longitude,
              cumulativeDistanceKm,
              elapsedSeconds: idx * 25 // 25 seconds per stop in simulation
            };
          });
        }
        
        if (historyData) {
          const est = estimatePositionFromHistory(historyData, tripElapsedSeconds, coordStops, selectedBus);
          if (est) {
            setUserCoords({
              latitude: est.latitude,
              longitude: est.longitude,
              accuracyMeters: 50,
              speedKmh: est.speedKmh,
              headingDegrees: est.headingDegrees,
              updatedAt: new Date(),
              isEstimated: true,
              tripCompleted: est.tripCompleted,
              currentStopName: est.currentStopName,
              nextStopName: est.nextStopName,
              remainingDistanceKm: est.remainingDistanceKm,
              etaMinutes: est.etaMinutes,
              nextSequence: est.nextSequence
            });
            
            // Sync simulation state for accurate timeline and map visualization
            const startStopIdx = coordStops.findIndex(s => s.stopName === est.currentStopName);
            if (startStopIdx !== -1) {
              setMyLocationIndex(startStopIdx);
              
              const segStart = historyData.find(h => h.stopName === est.currentStopName);
              const segEnd = historyData.find(h => h.stopName === est.nextStopName);
              if (segStart && segEnd) {
                const segmentDuration = segEnd.elapsedSeconds - segStart.elapsedSeconds;
                const elapsed = tripElapsedSeconds - segStart.elapsedSeconds;
                const offset = segmentDuration > 0 ? elapsed / segmentDuration : 0;
                setMyLocationOffset(Math.max(0, Math.min(1, offset)));
              } else {
                setMyLocationOffset(0);
              }
            }
            
            // Auto pause if reached terminus via historical fallback
            if (est.tripCompleted) {
              setIsPlaying(false);
            }
            return;
          }
        }
      } catch (err) {
        console.error("Error calculating position from history:", err);
      }
      
      // Fallback if estimation fails completely
      setUserCoords(null);
      return;
    }
    
    // Standard GPS Mode (simulation or real device navigator.geolocation)
    let userLat = 0;
    let userLng = 0;
    let userAccuracy = myAccuracy;
    let userSpeed = 35;
    let userHeading = 0;
    let timestamp = new Date();

    const currentStop = coordStops[myLocationIndex];
    const nextStop = coordStops[Math.min(myLocationIndex + 1, coordStops.length - 1)];
    const dLon = degToRad(nextStop.longitude - currentStop.longitude);
    const y = Math.sin(dLon) * Math.cos(degToRad(nextStop.latitude));
    const x = Math.cos(degToRad(currentStop.latitude)) * Math.sin(degToRad(nextStop.latitude)) -
              Math.sin(degToRad(currentStop.latitude)) * Math.cos(degToRad(nextStop.latitude)) * Math.cos(dLon);
    const defaultHeading = ((Math.atan2(y, x) * 180 / Math.PI) + 360) % 360;

    if (useSimulation) {
      // Find road points for this leg if roadRoutePointsRef.current is populated
      const roadPoints = roadRoutePointsRef.current;
      if (roadPoints && roadPoints.length > 0) {
        // Find indices in roadPoints closest to currentStop and nextStop
        const findClosestIndex = (stop) => {
          let minD = Infinity;
          let idx = 0;
          for (let i = 0; i < roadPoints.length; i++) {
            const dy = roadPoints[i][0] - stop.latitude;
            const dx = roadPoints[i][1] - stop.longitude;
            const d = dy * dy + dx * dx;
            if (d < minD) {
              minD = d;
              idx = i;
            }
          }
          return idx;
        };

        const idxA = findClosestIndex(currentStop);
        const idxB = findClosestIndex(nextStop);

        if (idxA !== idxB) {
          // Calculate overall offset along the road subset
          const totalPointsInLeg = Math.abs(idxB - idxA);
          const rawOffset = totalPointsInLeg * myLocationOffset;
          const pointOffset = Math.floor(rawOffset);
          const remainder = rawOffset - pointOffset;

          const step = idxA < idxB ? 1 : -1;
          const currentPointIdx = idxA + pointOffset * step;
          const nextPointIdx = Math.max(0, Math.min(roadPoints.length - 1, currentPointIdx + step));

          const ptA = roadPoints[currentPointIdx];
          const ptB = roadPoints[nextPointIdx];

          userLat = ptA[0] + (ptB[0] - ptA[0]) * remainder;
          userLng = ptA[1] + (ptB[1] - ptA[1]) * remainder;

          // Heading along road curve
          const dL = degToRad(ptB[1] - ptA[1]);
          const yH = Math.sin(dL) * Math.cos(degToRad(ptB[0]));
          const xH = Math.cos(degToRad(ptA[0])) * Math.sin(degToRad(ptB[0])) -
                    Math.sin(degToRad(ptA[0])) * Math.cos(degToRad(ptB[0])) * Math.cos(dL);
          userHeading = ((Math.atan2(yH, xH) * 180 / Math.PI) + 360) % 360;
        } else {
          userLat = currentStop.latitude + (nextStop.latitude - currentStop.latitude) * myLocationOffset;
          userLng = currentStop.longitude + (nextStop.longitude - currentStop.longitude) * myLocationOffset;
          userHeading = defaultHeading;
        }
      } else {
        userLat = currentStop.latitude + (nextStop.latitude - currentStop.latitude) * myLocationOffset;
        userLng = currentStop.longitude + (nextStop.longitude - currentStop.longitude) * myLocationOffset;
        userHeading = defaultHeading;
      }
      userAccuracy = myAccuracy;
      userSpeed = 35;
    } else {
      if (realCoords) {
        userLat = realCoords.latitude;
        userLng = realCoords.longitude;
        userAccuracy = realCoords.accuracyMeters;
        userSpeed = realCoords.speedKmh;
        userHeading = realCoords.headingDegrees;
        timestamp = realCoords.updatedAt;
      } else {
        // Fallback to the first stop's coordinates while real GPS is initializing
        userLat = coordStops[0].latitude;
        userLng = coordStops[0].longitude;
        userAccuracy = 15;
        userSpeed = 0;
        userHeading = 0;
      }
    }
    
    setUserCoords({
      latitude: userLat,
      longitude: userLng,
      accuracyMeters: userAccuracy,
      speedKmh: userSpeed,
      headingDegrees: userHeading,
      updatedAt: timestamp,
      isEstimated: false
    });
  }, [selectedBus, isTracking, useSimulation, realCoords, myLocationIndex, myLocationOffset, myAccuracy, loseGpsSignal, tripElapsedSeconds]);

  // 2. Push our location updates to Firebase Firestore in real-time
  useEffect(() => {
    if (firebaseSync && db && mySessionId && isTracking && selectedBus && userCoords) {
      const userDoc = doc(db, 'ride_sessions', selectedBus.bus_id, 'active', mySessionId);
      setDoc(userDoc, {
        latitude: userCoords.latitude,
        longitude: userCoords.longitude,
        accuracyMeters: userCoords.accuracyMeters,
        speedKmh: userCoords.speedKmh,
        headingDegrees: userCoords.headingDegrees,
        updatedAt: serverTimestamp()
      }).catch((err) => {
        console.error("Error writing position to Firestore:", err);
      });
    }
  }, [userCoords, firebaseSync, mySessionId, isTracking, selectedBus]);

  // 3. Merge contributions, resolve live location, and compute progress
  useEffect(() => {
    if (!selectedBus || !isTracking || !userCoords) return;

    // Direct historical estimation bypass
    if (userCoords.isEstimated) {
      setContributions([userCoords]);
      setResolvedLoc({
        busId: selectedBus.bus_id,
        latitude: userCoords.latitude,
        longitude: userCoords.longitude,
        accuracyMeters: userCoords.accuracyMeters,
        speedKmh: userCoords.speedKmh,
        headingDegrees: userCoords.headingDegrees,
        updatedAt: userCoords.updatedAt,
        contributorCount: 0,
        clusteredContributorCount: 0,
        confidenceScore: 0.5
      });
      setProgress({
        hasSufficientData: true,
        currentStopName: userCoords.currentStopName,
        nextStopName: userCoords.nextStopName,
        remainingStopsCount: selectedBus.routeStops.filter(s => s.sequence > userCoords.nextSequence).length,
        remainingDistanceKm: userCoords.remainingDistanceKm,
        etaMinutes: userCoords.etaMinutes,
        delayMinutes: 0,
        tripCompleted: userCoords.tripCompleted
      });
      return;
    }

    const sessionKey = mySessionId || 'user_session';
    const userContribution = {
      sessionId: sessionKey,
      ...userCoords
    };

    let activeRiders = [userContribution];

    if (firebaseSync) {
      // Filter out our own session from remote contributions to avoid duplicates
      const filteredRemote = remoteContributions.filter(c => c.sessionId !== sessionKey);
      activeRiders = [...activeRiders, ...filteredRemote];
    }
    
    // Simulate other riders if option selected
    if (addRiders) {
      const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
      if (coordStops.length >= 2) {
        const currentStop = coordStops[myLocationIndex] || coordStops[0];
        
        // Rider 2: close cluster with stable offset
        activeRiders.push({
          sessionId: 'rider_session_2',
          latitude: userCoords.latitude + 0.0003, 
          longitude: userCoords.longitude + 0.0003,
          accuracyMeters: ridersAccuracy,
          speedKmh: userCoords.speedKmh > 5 ? userCoords.speedKmh * 0.98 : 34,
          headingDegrees: (userCoords.headingDegrees + 2) % 360,
          updatedAt: new Date(userCoords.updatedAt.getTime() - 2000)
        });
        
        // Rider 3: close cluster with stable offset
        activeRiders.push({
          sessionId: 'rider_session_3',
          latitude: userCoords.latitude - 0.0004, 
          longitude: userCoords.longitude - 0.0002,
          accuracyMeters: ridersAccuracy + 15,
          speedKmh: userCoords.speedKmh > 5 ? userCoords.speedKmh * 1.01 : 33,
          headingDegrees: (userCoords.headingDegrees - 3 + 360) % 360,
          updatedAt: new Date(userCoords.updatedAt.getTime() - 5000)
        });
        
        // Rider 4: bad outlier (stable, e.g. someone walking at previous stop or fake spoof)
        activeRiders.push({
          sessionId: 'rider_session_4',
          latitude: currentStop.latitude - 0.004, 
          longitude: currentStop.longitude - 0.004,
          accuracyMeters: 90,
          speedKmh: 5,
          headingDegrees: 180,
          updatedAt: new Date(userCoords.updatedAt.getTime() - 25000)
        });
      }
    }
    
    setContributions(activeRiders);
    
    // Resolve Live Location using inverse-variance algorithm!
    const resolved = resolveLiveLocation(selectedBus.bus_id, activeRiders);
    setResolvedLoc(resolved);
    
    if (resolved) {
      // Calculate progress details
      const prog = calculateTripProgress(selectedBus, resolved);
      setProgress(prog);
    }
  }, [selectedBus, isTracking, userCoords, addRiders, ridersAccuracy, firebaseSync, mySessionId, remoteContributions, myLocationIndex]);
  
  // Track stop arrival times (in elapsed seconds) for historical analysis
  useEffect(() => {
    if (!selectedBus || !isTracking || loseGpsSignal || !resolvedLoc) return;
    
    const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
    
    coordStops.forEach(stop => {
      const dist = haversineKm(resolvedLoc.latitude, resolvedLoc.longitude, stop.latitude, stop.longitude);
      if (dist <= 0.3) { // 300 meters
        setStopArrivalTimes(prev => {
          if (prev[stop.sequence] !== undefined) return prev;
          console.log(`Stop reached: ${stop.stopName} at ${tripElapsedSeconds}s`);
          return { ...prev, [stop.sequence]: tripElapsedSeconds };
        });
      }
    });
  }, [resolvedLoc, isTracking, loseGpsSignal, selectedBus, tripElapsedSeconds]);

  // Save route tracking history to localStorage
  useEffect(() => {
    if (!selectedBus || !isTracking || Object.keys(stopArrivalTimes).length === 0) return;
    
    const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
    if (coordStops.length < 2) return;
    
    const firstSequence = coordStops[0].sequence;
    
    let cumulativeDistanceKm = 0;
    const historyData = coordStops.map((s, idx) => {
      if (idx > 0) {
        cumulativeDistanceKm += haversineKm(
          coordStops[idx - 1].latitude,
          coordStops[idx - 1].longitude,
          s.latitude,
          s.longitude
        );
      }
      
      const elapsedSeconds = stopArrivalTimes[s.sequence];
      
      return {
        sequence: s.sequence,
        stopId: s.stopId,
        stopName: s.stopName,
        latitude: s.latitude,
        longitude: s.longitude,
        cumulativeDistanceKm,
        elapsedSeconds: elapsedSeconds !== undefined ? elapsedSeconds : null
      };
    });
    
    const hasActualData = historyData.some(h => h.sequence > firstSequence && h.elapsedSeconds !== null);
    if (hasActualData) {
      localStorage.setItem(`wbsb_history_${selectedBus.bus_id}`, JSON.stringify(historyData));
      setHasHistoryData(true);
    }
  }, [stopArrivalTimes, selectedBus, isTracking]);

  // Failsafe: Auto-pause simulation and lock index when trip is completed
  useEffect(() => {
    if (progress && progress.tripCompleted && isTracking && isPlaying) {
      setIsPlaying(false);
      if (useSimulation && !loseGpsSignal && selectedBus) {
        const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
        if (coordStops.length > 0) {
          setMyLocationIndex(coordStops.length - 1);
          setMyLocationOffset(0);
        }
      }
    }
  }, [progress, isTracking, isPlaying, useSimulation, loseGpsSignal, selectedBus]);
  
  // Render resolved locations on the map dynamically
  useEffect(() => {
    if (!mapInstance.current || !selectedBus) return;
    
    // Render My Location marker
    if (isTracking && contributions.length > 0) {
      const userFix = contributions.find(c => c.sessionId === 'user_session' || c.sessionId === mySessionId);
      if (userFix) {
        // Draw accuracy circle
        if (mapMarkers.current['user_accuracy']) {
          mapMarkers.current['user_accuracy'].setLatLng([userFix.latitude, userFix.longitude]);
          mapMarkers.current['user_accuracy'].setRadius(userFix.accuracyMeters);
        } else {
          mapMarkers.current['user_accuracy'] = L.circle([userFix.latitude, userFix.longitude], {
            radius: userFix.accuracyMeters,
            fillColor: '#3b82f6',
            fillOpacity: 0.15,
            color: '#3b82f6',
            weight: 1.5,
            dashArray: '4, 4'
          }).addTo(mapInstance.current);
        }
        
        // Draw user pin
        const userEl = document.createElement('div');
        userEl.className = 'marker-pin marker-user';
        userEl.style.backgroundColor = '#3b82f6';
        
        const userDivIcon = L.divIcon({
          className: 'custom-div-icon',
          html: userEl,
          iconSize: [30, 30],
          iconAnchor: [15, 30]
        });
        
        if (mapMarkers.current['user_pin']) {
          mapMarkers.current['user_pin'].setLatLng([userFix.latitude, userFix.longitude]);
        } else {
          mapMarkers.current['user_pin'] = L.marker([userFix.latitude, userFix.longitude], { icon: userDivIcon })
            .addTo(mapInstance.current)
            .bindPopup(`<strong>You (${useSimulation ? 'Simulated' : 'Live'} GPS)</strong>`);
        }
      }
      
      // Draw other riders (remote and/or simulated)
      const otherRiders = contributions.filter(c => c.sessionId !== 'user_session' && c.sessionId !== mySessionId);
      const activeRiderKeys = new Set();
      
      otherRiders.forEach(rider => {
        const isSimulatedRider = typeof rider.sessionId === 'string' && rider.sessionId.startsWith('rider_session');
        const key = `rider_${rider.sessionId}`;
        activeRiderKeys.add(key);
        
        const riderEl = document.createElement('div');
        riderEl.className = 'marker-pin marker-rider';
        
        if (rider.sessionId === 'rider_session_4') {
          riderEl.style.backgroundColor = '#ef4444'; // Red for rejected outlier
        } else if (isSimulatedRider) {
          riderEl.style.backgroundColor = '#eab308'; // Amber for simulated rider
        } else {
          riderEl.style.backgroundColor = '#a855f7'; // Purple/violet for real remote rider
        }
        
        const riderIcon = L.divIcon({
          className: 'custom-div-icon',
          html: riderEl,
          iconSize: [24, 24],
          iconAnchor: [12, 24]
        });
        
        const label = isSimulatedRider 
          ? (rider.sessionId === 'rider_session_4' ? 'Simulated Outlier' : 'Simulated Rider') 
          : 'Live Remote Rider';
          
        if (mapMarkers.current[key]) {
          mapMarkers.current[key].setLatLng([rider.latitude, rider.longitude]);
        } else {
          mapMarkers.current[key] = L.marker([rider.latitude, rider.longitude], { icon: riderIcon })
            .addTo(mapInstance.current)
            .bindPopup(`<strong>${label}</strong><br/>Accuracy: ${Math.round(rider.accuracyMeters)}m<br/>Status: ${rider.sessionId === 'rider_session_4' ? 'Rejected (Outlier)' : 'Accepted'}`);
        }
      });
      
      // Remove any rider markers that are no longer active
      Object.keys(mapMarkers.current).forEach(k => {
        if (k.startsWith('rider_') && !activeRiderKeys.has(k)) {
          mapMarkers.current[k].remove();
          delete mapMarkers.current[k];
        }
      });
    } else {
      // Clear tracking markers if not tracking
      ['user_accuracy', 'user_pin'].forEach(k => {
        if (mapMarkers.current[k]) {
          mapMarkers.current[k].remove();
          delete mapMarkers.current[k];
        }
      });
      Object.keys(mapMarkers.current).forEach(k => {
        if (k.startsWith('rider_')) {
          mapMarkers.current[k].remove();
          delete mapMarkers.current[k];
        }
      });
    }
    
    // Draw Resolved Bus Location
    if (resolvedLoc) {
      const targetLat = resolvedLoc.latitude;
      const targetLng = resolvedLoc.longitude;
      const targetHead = resolvedLoc.headingDegrees || 0;
      
      const anim = resolvedBusAnimRef.current;
      
      if (!anim || anim.selectedBusId !== selectedBus.id) {
        // Initialize animation state
        if (anim && anim.frameId) {
          cancelAnimationFrame(anim.frameId);
        }
        
        // Custom DOM chevron element
        const busEl = document.createElement('div');
        busEl.className = 'custom-bus-chevron';
        busEl.innerHTML = `<svg viewBox="0 0 24 24" width="32" height="32" style="transform: rotate(${targetHead}deg); transition: transform 0.1s ease-out; filter: drop-shadow(0px 2px 4px rgba(0,0,0,0.35));"><path d="M12,2L4.5,20.29L5.21,21L12,18L18.79,21L19.5,20.29L12,2Z" fill="${resolvedLoc.isStale ? '#ef4444' : '#22c55e'}" stroke="#ffffff" stroke-width="1.5"/></svg>`;
        
        const busDivIcon = L.divIcon({
          className: 'custom-div-icon',
          html: busEl,
          iconSize: [32, 32],
          iconAnchor: [16, 16]
        });
        
        if (mapMarkers.current['resolved_bus']) {
          mapMarkers.current['resolved_bus'].remove();
        }
        
        const marker = L.marker([targetLat, targetLng], { icon: busDivIcon })
          .addTo(mapInstance.current)
          .bindPopup(`<strong>Resolved Bus Location</strong><br/>Confidence: ${Math.round(resolvedLoc.confidenceScore * 100)}%<br/>Contributors: ${resolvedLoc.clusteredContributorCount}/${resolvedLoc.contributorCount}`);
        
        mapMarkers.current['resolved_bus'] = marker;
        
        resolvedBusAnimRef.current = {
          lat: targetLat,
          lng: targetLng,
          head: targetHead,
          selectedBusId: selectedBus.id,
          element: busEl.firstElementChild,
          frameId: null
        };
        
        if (isTracking && isPlaying) {
          mapInstance.current.panTo([targetLat, targetLng]);
        }
      } else {
        // Run LERP animation to target coords
        const duration = 1000; // 1s lerp transition
        const startTime = performance.now();
        
        const startLat = anim.lat;
        const startLng = anim.lng;
        const startHead = anim.head;
        
        // Handle heading interpolation across 0/360 boundary
        let diff = targetHead - startHead;
        while (diff < -180) diff += 360;
        while (diff > 180) diff -= 360;
        const targetHeadAdjusted = startHead + diff;
        
        if (anim.frameId) {
          cancelAnimationFrame(anim.frameId);
        }
        
        const animate = (now) => {
          const elapsed = now - startTime;
          const t = Math.min(1, elapsed / duration);
          
          const currentLat = startLat + (targetLat - startLat) * t;
          const currentLng = startLng + (targetLng - startLng) * t;
          const currentHead = (startHead + (targetHeadAdjusted - startHead) * t + 360) % 360;
          
          anim.lat = currentLat;
          anim.lng = currentLng;
          anim.head = currentHead;
          
          if (mapMarkers.current['resolved_bus']) {
            mapMarkers.current['resolved_bus'].setLatLng([currentLat, currentLng]);
          }
          if (anim.element) {
            anim.element.style.transform = `rotate(${currentHead}deg)`;
            anim.element.querySelector('path').setAttribute('fill', resolvedLoc.isStale ? '#ef4444' : '#22c55e');
          }
          
          // Camera follow
          if (isTracking && isPlaying) {
            mapInstance.current.panTo([currentLat, currentLng]);
          }
          
          if (t < 1) {
            anim.frameId = requestAnimationFrame(animate);
          } else {
            anim.frameId = null;
          }
        };
        
        anim.frameId = requestAnimationFrame(animate);
      }
    } else {
      if (mapMarkers.current['resolved_bus']) {
        mapMarkers.current['resolved_bus'].remove();
        delete mapMarkers.current['resolved_bus'];
      }
      if (resolvedBusAnimRef.current) {
        if (resolvedBusAnimRef.current.frameId) {
          cancelAnimationFrame(resolvedBusAnimRef.current.frameId);
        }
        resolvedBusAnimRef.current = null;
      }
    }

    return () => {
      if (resolvedBusAnimRef.current && resolvedBusAnimRef.current.frameId) {
        cancelAnimationFrame(resolvedBusAnimRef.current.frameId);
      }
    };
  }, [resolvedLoc, isTracking, contributions, addRiders, mySessionId, useSimulation, isPlaying, selectedBus]);
  
  const popularSearches = [
    { label: "Kolkata ↔ Digha", source: "Kolkata", dest: "Digha" },
    { label: "Asansol ↔ Digha", source: "Asansol", dest: "Digha" },
    { label: "Bankura ↔ Kolkata", source: "Bankura", dest: "Kolkata" },
    { label: "Siliguri ↔ Kolkata", source: "Siliguri", dest: "Kolkata" },
    { label: "Bardhaman ↔ Kharagpur", source: "Bardhaman", dest: "Kharagpur" },
    { label: "Purulia ↔ Bankura", source: "Purulia", dest: "Bankura" }
  ];

  const isSearching = searchQuery.trim() !== '' || sourceFilter.trim() !== '' || destFilter.trim() !== '';

  // Filtering logic for list of buses
  const filteredBuses = !isSearching ? [] : busesData.filter(bus => {
    if (effectiveSource !== '' || effectiveDest !== '') {
      let matchesSource = effectiveSource === '';
      let matchesDest = effectiveDest === '';
      
      const sourceStops = bus.routeStops.filter(stop => fuzzyContains(stop.stopName, effectiveSource) || fuzzyContains(bus.source, effectiveSource));
      const destStops = bus.routeStops.filter(stop => fuzzyContains(stop.stopName, effectiveDest) || fuzzyContains(bus.destination, effectiveDest));
      
      if (effectiveSource !== '' && effectiveDest !== '') {
        const sourceMatch = sourceStops.length > 0;
        const destMatch = destStops.length > 0;
        
        if (sourceMatch && destMatch) {
          const minSourceSeq = Math.min(...sourceStops.map(s => s.sequence));
          const maxDestSeq = Math.max(...destStops.map(s => s.sequence));
          if (minSourceSeq < maxDestSeq) {
            matchesSource = true;
            matchesDest = true;
          }
        }
      } else if (effectiveSource !== '') {
        matchesSource = sourceStops.length > 0;
      } else if (effectiveDest !== '') {
        matchesDest = destStops.length > 0;
      }
      
      return matchesSource && matchesDest;
    }

    // 1. General search query fallback
    return searchQuery === '' || 
      fuzzyContains(bus.bus_name, searchQuery) ||
      fuzzyContains(bus.alternate_name || '', searchQuery) ||
      fuzzyContains(bus.registration_number || '', searchQuery) ||
      fuzzyContains(bus.operator || '', searchQuery) ||
      fuzzyContains(bus.agency || '', searchQuery) ||
      fuzzyContains(bus.source, searchQuery) ||
      fuzzyContains(bus.destination, searchQuery) ||
      bus.routeStops.some(stop => fuzzyContains(stop.stopName, searchQuery));
  });
  
  const connectingRoutes = useMemo(() => {
    if (!isSearching || effectiveSource.trim() === '' || effectiveDest.trim() === '' || filteredBuses.length > 0) {
      return [];
    }

    const results = [];
    const maxRoutes = 5;

    // Find all starting buses matching effectiveSource
    const startBuses = busesData.map(bus => {
      const sourceStops = bus.routeStops.filter(stop => fuzzyContains(stop.stopName, effectiveSource) || fuzzyContains(bus.source, effectiveSource));
      if (sourceStops.length === 0) return null;
      const minSeq = Math.min(...sourceStops.map(s => s.sequence));
      return { bus, minSeq, stops: bus.routeStops.filter(s => s.sequence > minSeq) };
    }).filter(Boolean);

    // Find all ending buses matching effectiveDest
    const endBuses = busesData.map(bus => {
      const destStops = bus.routeStops.filter(stop => fuzzyContains(stop.stopName, effectiveDest) || fuzzyContains(bus.destination, effectiveDest));
      if (destStops.length === 0) return null;
      const maxSeq = Math.max(...destStops.map(s => s.sequence));
      return { bus, maxSeq, stops: bus.routeStops.filter(s => s.sequence < maxSeq) };
    }).filter(Boolean);

    // Intersection
    for (const b1 of startBuses) {
      for (const b2 of endBuses) {
        if (b1.bus.bus_id === b2.bus.bus_id) continue;

        for (const stop1 of b1.stops) {
          for (const stop2 of b2.stops) {
            if (stop1.stopName.toLowerCase().trim() === stop2.stopName.toLowerCase().trim()) {
              results.push({
                bus1: b1.bus,
                bus2: b2.bus,
                connectionStop: stop1.stopName,
                key: `${b1.bus.bus_id}_${b2.bus.bus_id}_${stop1.stopName}`
              });
              if (results.length >= maxRoutes) return results;
            }
          }
        }
      }
    }
    return results;
  }, [busesData, effectiveSource, effectiveDest, filteredBuses, isSearching]);

  const swapSourceDest = () => {
    const temp = sourceFilter;
    setSourceFilter(destFilter);
    setDestFilter(temp);
  };

  const clearSearch = () => {
    setSearchQuery('');
    setSourceFilter('');
    setDestFilter('');
    setShowFilters(false);
  };
  
  // Confidence styling helpers
  const getConfidenceLevel = (score) => {
    if (score >= 0.75) return 'high';
    if (score >= 0.4) return 'med';
    return 'low';
  };
  
  return (
    <div className="app-container">
      {/* Top Header */}
      <header className="header">
        <div className="header-brand">
          <img 
            src="/logo.jpg" 
            alt="WBBus Go" 
            style={{ 
              width: '40px', 
              height: '40px', 
              borderRadius: '8px', 
              border: '2px solid var(--accent)',
              objectFit: 'cover'
            }} 
          />
          <div>
            <span className="header-logo">WBBus Go</span>
            <div className="header-subtitle">Real-time Passenger Crowdsourcing</div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.85rem' }}>
            <span style={{ 
              width: '8px', 
              height: '8px', 
              borderRadius: '50%', 
              backgroundColor: isTracking ? '#22c55e' : '#64748b',
              boxShadow: isTracking ? '0 0 8px #22c55e' : 'none'
            }} />
            <span style={{ color: 'rgba(255, 255, 255, 0.8)' }}>
              {isTracking ? 'Streaming GPS Fixes' : 'Offline / Standard View'}
            </span>
          </div>
        </div>
      </header>
      
      {/* Main Content */}
      <main className="main-content">
        
        {/* Left Sidebar */}
        <div className="sidebar">
          {loading ? (
            <div className="no-results" style={{ marginTop: '5rem' }}>
              <div className="pulse-marker" style={{ margin: '0 auto 1.5rem', width: '20px', height: '20px' }}></div>
              <p style={{ fontFamily: 'var(--font-heading)', fontWeight: 600 }}>Loading WBBus Go Datasets...</p>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>Hydrating schedule models from cache</p>
            </div>
          ) : !selectedBus ? (
            // Search Mode
            <>
              <div className="search-panel">
                <div className="search-title">
                  <Search size={18} className="text-accent" />
                  <span>Find Your Bus Route</span>
                </div>
                
                <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', width: '100%' }}>
                  {isSearching && (
                    <button 
                      onClick={clearSearch}
                      style={{
                        background: 'var(--secondary-bg)',
                        border: '1px solid var(--border)',
                        color: 'var(--accent)',
                        cursor: 'pointer',
                        padding: '0.45rem',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        borderRadius: '50%',
                        transition: 'all 0.2s ease',
                        boxShadow: 'var(--shadow-sm)'
                      }}
                      title="Back to Home"
                    >
                      <ChevronLeft size={18} />
                    </button>
                  )}
                  <div className="search-input-wrapper" style={{ flex: 1, margin: 0 }}>
                    <Search size={16} className="search-icon" />
                    <input 
                      type="text" 
                      className="input-field" 
                      placeholder="Search by bus name, reg no, stop town..." 
                      value={searchQuery}
                      onChange={e => setSearchQuery(e.target.value)}
                    />
                  </div>
                </div>

                <div style={{ display: 'flex', justifyContent: 'flex-start', margin: '0.25rem 0 0.5rem' }}>
                  <button 
                    onClick={() => setShowFilters(!showFilters)}
                    style={{
                      background: 'transparent',
                      border: 'none',
                      color: showFilters ? 'var(--text-muted)' : 'var(--accent)',
                      fontSize: '0.75rem',
                      fontWeight: 600,
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.3rem',
                      padding: '0.2rem 0'
                    }}
                  >
                    <SlidersHorizontal size={11} />
                    <span>{showFilters ? "Hide Boarding/Destination Filters" : "Filter by Boarding & Destination"}</span>
                  </button>
                </div>
                
                {showFilters && (
                  <>
                    <div style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)', margin: '0.5rem 0 0.25rem' }}>
                      FILTER BY BOARDING & DESTINATION
                    </div>
                    
                    <div className="route-selector" style={{ marginBottom: '0.25rem' }}>
                      <input 
                        type="text" 
                        className="input-field" 
                        style={{ paddingLeft: '0.75rem' }}
                        placeholder="From: e.g. Kolkata" 
                        value={sourceFilter}
                        onChange={e => setSourceFilter(e.target.value)}
                      />
                      <button className="route-swap-btn" onClick={swapSourceDest}>
                        <ArrowRightLeft size={14} />
                      </button>
                      <input 
                        type="text" 
                        className="input-field" 
                        style={{ paddingLeft: '0.75rem' }}
                        placeholder="To: e.g. Purulia" 
                        value={destFilter}
                        onChange={e => setDestFilter(e.target.value)}
                      />
                    </div>
                  </>
                )}

                {/* Startup Location Status Card */}
                {userStartupCoords ? (
                  <div style={{
                    marginTop: '0.75rem',
                    background: 'var(--secondary-bg)',
                    border: '1px solid rgba(37, 99, 235, 0.2)',
                    padding: '0.65rem 0.85rem',
                    borderRadius: 'var(--radius-md)',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '0.2rem',
                    fontSize: '0.8rem',
                    boxShadow: 'var(--shadow-sm)'
                  }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.35rem', fontWeight: 700, color: 'var(--secondary)' }}>
                      <CheckCircle size={14} />
                      <span>Your Current Location (GPS)</span>
                    </div>
                    <div style={{ fontFamily: 'monospace', color: 'var(--text-title)' }}>
                      Lat: {userStartupCoords.latitude.toFixed(5)} | Lng: {userStartupCoords.longitude.toFixed(5)}
                    </div>
                  </div>
                ) : (
                  <div 
                    onClick={requestStartupLocation}
                    style={{
                      marginTop: '0.75rem',
                      background: 'rgba(245, 158, 11, 0.08)',
                      border: '1px solid rgba(245, 158, 11, 0.2)',
                      padding: '0.65rem 0.85rem',
                      borderRadius: 'var(--radius-md)',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.5rem',
                      fontSize: '0.8rem',
                      color: 'var(--warning)',
                      cursor: 'pointer',
                      boxShadow: 'var(--shadow-sm)'
                    }}
                  >
                    <AlertTriangle size={14} style={{ flexShrink: 0 }} />
                    <span>Location access not granted. Tap here to request/retry.</span>
                  </div>
                )}
              </div>
              
              <div className="list-container">
                {!isSearching ? (
                  <div className="search-guide-panel" style={{
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    textAlign: 'center',
                    padding: '2rem 1.25rem',
                    gap: '1.25rem',
                    background: 'var(--secondary-bg)',
                    borderRadius: 'var(--radius-lg)',
                    border: '1px dashed var(--border)',
                    marginTop: '0.5rem'
                  }}>
                    <div style={{
                      width: '56px',
                      height: '56px',
                      borderRadius: '50%',
                      background: 'rgba(37, 99, 235, 0.1)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: 'var(--accent)'
                    }}>
                      <Bus size={28} />
                    </div>
                    <div>
                      <h3 style={{ fontSize: '1.05rem', fontWeight: 700, margin: '0 0 0.4rem 0', color: 'var(--text-title)' }}>
                        Find Your Bus
                      </h3>
                      <p style={{ fontSize: '0.8rem', color: 'var(--text-muted)', margin: 0, lineHeight: 1.45 }}>
                        Search by bus name, operator, boarding stop, or tap "Filter by Boarding & Destination" above to view live schedules.
                      </p>
                    </div>
                    
                    <div style={{ width: '100%', textAlign: 'left', borderTop: '1px solid var(--border)', paddingTop: '1rem', marginTop: '0.25rem' }}>
                      <span style={{ fontSize: '0.7rem', fontWeight: 700, color: 'var(--text-muted)', letterSpacing: '0.05em', textTransform: 'uppercase' }}>
                        Popular Route Searches
                      </span>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.4rem', marginTop: '0.6rem' }}>
                        {popularSearches.map((route, i) => (
                          <button
                            key={i}
                            onClick={() => {
                              setSourceFilter(route.source);
                              setDestFilter(route.dest);
                              setShowFilters(true);
                            }}
                            className="popular-route-tag"
                            style={{
                              padding: '0.35rem 0.7rem',
                              fontSize: '0.75rem',
                              background: 'var(--card-bg)',
                              border: '1px solid var(--border)',
                              borderRadius: '16px',
                              color: 'var(--text-title)',
                              cursor: 'pointer',
                              fontWeight: 500,
                              display: 'flex',
                              alignItems: 'center',
                              gap: '0.25rem',
                              transition: 'all 0.15s ease'
                            }}
                          >
                            <Compass size={11} className="text-accent" />
                            <span>{route.label}</span>
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>
                ) : (
                  <>
                    <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: 'var(--text-muted)', marginBottom: '0.75rem' }}>
                      <span>FOUND {filteredBuses.length} SERVICES</span>
                      <span>OCR VERIFIED DATASET</span>
                    </div>
                    
                    <div className="bus-list">
                      {filteredBuses.map(bus => (
                        <div 
                          key={bus.bus_id} 
                          className="bus-card"
                          onClick={() => setSelectedBus(bus)}
                        >
                          <div className="bus-card-header">
                            <div className="bus-name-group">
                              <span className="bus-name">
                                {bus.bus_name} 
                                {bus.alternate_name && <span className="bus-alternate">({bus.alternate_name})</span>}
                              </span>
                              <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                                Operator: {bus.operator}
                              </span>
                            </div>
                            {bus.registration_number && (
                              <span className="bus-reg">{bus.registration_number}</span>
                            )}
                          </div>
                          
                          <div className="bus-meta">
                            <span className={`badge ${bus.bus_type.includes('Government') ? 'badge-gov' : 'badge-pvt'}`}>
                              {bus.bus_type}
                            </span>
                            {bus.agency && (
                              <span style={{ color: 'var(--text-muted)', fontStyle: 'italic' }}>
                                {bus.agency}
                              </span>
                            )}
                          </div>
                          
                          <div className="bus-route">
                            <MapPin size={14} className="text-accent" />
                            <span>{bus.source}</span>
                            <span style={{ color: 'var(--text-muted)' }}>→</span>
                            <span>{bus.destination}</span>
                          </div>
                          
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.75rem', borderTop: '1px solid var(--border)', paddingTop: '0.5rem', fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                            <span>Stops: {bus.routeStops.length}</span>
                            {bus.routeStops[0]?.upTime && (
                              <span>Starts: {bus.routeStops[0].upTime}</span>
                            )}
                          </div>
                        </div>
                      ))}
                      
                      {filteredBuses.length === 0 && connectingRoutes.length > 0 && (
                        <div className="connecting-routes-container">
                          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.75rem', color: 'var(--text-accent)' }}>
                            <Compass size={16} />
                            <h4 style={{ margin: 0, fontSize: '0.8rem', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
                              Connecting Services Found
                            </h4>
                          </div>
                          {connectingRoutes.map(conn => (
                            <div 
                              key={conn.key} 
                              className="bus-card"
                              style={{ borderLeft: '3px solid var(--text-accent)' }}
                            >
                              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: '0.7rem', fontWeight: 600, color: 'var(--text-accent)', marginBottom: '0.4rem' }}>
                                <span>1-STOP TRANSFER</span>
                                <span style={{ padding: '2px 6px', background: 'rgba(37, 99, 235, 0.1)', borderRadius: '4px' }}>VIA {conn.connectionStop.toUpperCase()}</span>
                              </div>
                              
                              <div 
                                style={{ cursor: 'pointer', padding: '0.25rem 0', borderBottom: '1px dashed var(--border)' }}
                                onClick={() => setSelectedBus(conn.bus1)}
                              >
                                <div style={{ fontWeight: 600, fontSize: '0.75rem', color: 'var(--text)' }}>
                                  1. {conn.bus1.bus_name} <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>({conn.bus1.operator})</span>
                                </div>
                                <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                                  {conn.bus1.source} &rarr; {conn.bus1.destination}
                                </div>
                              </div>

                              <div 
                                style={{ cursor: 'pointer', padding: '0.25rem 0' }}
                                onClick={() => setSelectedBus(conn.bus2)}
                              >
                                <div style={{ fontWeight: 600, fontSize: '0.75rem', color: 'var(--text)', marginTop: '0.25rem' }}>
                                  2. {conn.bus2.bus_name} <span style={{ fontWeight: 400, color: 'var(--text-muted)' }}>({conn.bus2.operator})</span>
                                </div>
                                <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                                  {conn.bus2.source} &rarr; {conn.bus2.destination}
                                </div>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                      
                      {filteredBuses.length === 0 && connectingRoutes.length === 0 && (
                        <div className="no-results">
                          <AlertTriangle style={{ margin: '0 auto 0.75rem' }} size={24} className="text-muted" />
                          <p style={{ fontWeight: 600 }}>No Buses Match Filters</p>
                          <p style={{ fontSize: '0.8rem' }}>Try clearing spelling variations or stop keywords.</p>
                        </div>
                      )}
                    </div>
                  </>
                )}
              </div>
            </>
          ) : (
            // Bus Details Mode
            <div className="details-panel">
              {progress && progress.tripCompleted && (
                <div className="reached-banner">
                  <CheckCircle size={20} />
                  <span>Reached Destination!</span>
                </div>
              )}
              <div className="details-header">
                <button className="back-btn" onClick={() => setSelectedBus(null)}>
                  <ChevronLeft size={16} />
                  <span>Back to Search</span>
                </button>
                
                <h2 style={{ fontFamily: 'var(--font-heading)', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                  {selectedBus.bus_name} 
                  {selectedBus.alternate_name && <span className="bus-alternate">({selectedBus.alternate_name})</span>}
                </h2>
                
                <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', margin: '0.4rem 0' }}>
                  <span className={`badge ${selectedBus.bus_type.includes('Government') ? 'badge-gov' : 'badge-pvt'}`}>
                    {selectedBus.bus_type}
                  </span>
                  {selectedBus.registration_number && (
                    <span className="bus-reg">{selectedBus.registration_number}</span>
                  )}
                </div>
                
                <div className="details-route-flow">
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.8rem', color: 'var(--text-title)', fontWeight: 600 }}>
                    <span>{tripStops[0]?.stopName ?? selectedBus.source}</span>
                    <span>{tripStops[tripStops.length - 1]?.stopName ?? selectedBus.destination}</span>
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                    <span>Your Boarding Stop</span>
                    <span>Your Alighting Stop</span>
                  </div>
                </div>
              </div>
              
              <div className="details-scrollable-content" style={{ flex: 1, overflowY: 'auto', paddingBottom: '2.5rem' }}>
                {/* Crowdsourcing GPS activation panel */}
                <div className="tracking-card">
                  <div className="tracking-title">
                    <Navigation size={16} className="text-accent" />
                    <span>Commuter GPS Broadcast</span>
                  </div>
                  
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-main)' }}>
                    Riding this bus? Tap "I'm On This Bus" to broadcast your real-time device coordinates. Your location will help other commuters track this service live.
                  </p>
                  
                  {isTracking ? (
                    <button 
                      className="tracking-button btn-stop-tracking"
                      onClick={() => setIsTracking(false)}
                      style={{
                        backgroundColor: 'var(--danger)',
                        color: 'white',
                        border: 'none',
                        cursor: 'pointer',
                        padding: '0.6rem 1rem',
                        borderRadius: 'var(--radius-md)',
                        fontWeight: 600,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: '0.5rem',
                        width: '100%',
                        transition: 'background 0.2s'
                      }}
                    >
                      <Pause size={16} />
                      <span>Stop Broadcast (End Ride)</span>
                    </button>
                  ) : (
                    <button 
                      className="tracking-button btn-start-tracking"
                      onClick={() => {
                        setIsTracking(true);
                        setUseSimulation(false);
                        setMyLocationIndex(0);
                        setMyLocationOffset(0);
                        setIsPlaying(false);
                        setTripElapsedSeconds(0);
                        setLoseGpsSignal(false);
                        
                        const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
                        if (coordStops.length > 0) {
                          setStopArrivalTimes({ [coordStops[0].sequence]: 0 });
                        } else {
                          setStopArrivalTimes({});
                        }
                      }}
                      style={{
                        backgroundColor: 'var(--accent)',
                        color: 'white',
                        border: 'none',
                        cursor: 'pointer',
                        padding: '0.6rem 1rem',
                        borderRadius: 'var(--radius-md)',
                        fontWeight: 600,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: '0.5rem',
                        width: '100%',
                        transition: 'background 0.2s'
                      }}
                    >
                      <Play size={16} />
                      <span>I'm On This Bus</span>
                    </button>
                  )}

                {/* Firebase Status Badge */}
                <div className="firebase-status-bar" style={{
                  marginTop: '0.75rem',
                  padding: '0.6rem 0.75rem',
                  borderRadius: 'var(--radius-sm)',
                  background: 'rgba(255, 255, 255, 0.03)',
                  border: '1px solid var(--border)',
                  fontSize: '0.75rem',
                  display: 'flex',
                  flexDirection: 'column',
                  gap: '0.35rem'
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Firebase Sync:</span>
                    {isFirebaseConfigured ? (
                      firebaseSync ? (
                        <span style={{ color: '#22c55e', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                          <span className="pulse-marker" style={{ width: '6px', height: '6px', backgroundColor: '#22c55e', position: 'static', display: 'inline-block', boxShadow: '0 0 6px #22c55e' }} />
                          Live Connected
                        </span>
                      ) : (
                        <span style={{ color: '#ef4444', fontWeight: 600 }}>Sync Paused</span>
                      )
                    ) : (
                      <span style={{ color: '#eab308', fontWeight: 600 }}>Demo Mode (No Firebase)</span>
                    )}
                  </div>
                  
                  {!isFirebaseConfigured && (
                    <div style={{ color: 'var(--text-muted)', fontSize: '0.7rem', marginTop: '0.25rem', lineHeight: '1.3' }}>
                      To enable live cloud sync, rename <code style={{color: 'var(--accent)'}}>.env.example</code> to <code style={{color: 'var(--accent)'}}>.env</code> and enter your Firebase web credentials.
                    </div>
                  )}

                  {isFirebaseConfigured && (
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.25rem', borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '0.35rem' }}>
                      <label htmlFor="firebaseSyncCheck" style={{ cursor: 'pointer', fontSize: '0.7rem', color: 'var(--text-main)' }}>
                        Enable real-time cloud sync
                      </label>
                      <input 
                        type="checkbox" 
                        id="firebaseSyncCheck" 
                        checked={firebaseSync} 
                        onChange={e => setFirebaseSync(e.target.checked)} 
                        style={{ width: '12px', height: '12px', cursor: 'pointer' }}
                      />
                    </div>
                  )}
                  
                  {firebaseError && (
                    <div style={{ color: '#ef4444', fontSize: '0.7rem', marginTop: '0.25rem', display: 'flex', gap: '0.25rem', alignItems: 'center', borderTop: '1px solid rgba(255,255,255,0.05)', paddingTop: '0.35rem' }}>
                      <AlertTriangle size={12} />
                      <span>{firebaseError}</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Mobile-only Stats & Controls (hidden on desktop via CSS) */}
              <div className="mobile-only-controls">
                {resolvedLoc && progress && (
                  <div className="mobile-stats-card">
                    <div className="mobile-card-title">
                      <Clock size={14} className="text-accent" />
                      <span>Resolved Live Statistics</span>
                    </div>
                    <div className="stat-row">
                      <span className="stat-label">Confidence Score</span>
                      {loseGpsSignal ? (
                        <span className="confidence-indicator confidence-med" style={{ backgroundColor: 'rgba(217, 119, 6, 0.15)', color: 'var(--accent)', fontSize: '0.75rem', padding: '0.1rem 0.4rem', borderRadius: '4px' }}>
                          <span className="confidence-dot" style={{ backgroundColor: 'var(--accent)' }} />
                          Historical Estimate
                        </span>
                      ) : (
                        <span className={`confidence-indicator confidence-${getConfidenceLevel(resolvedLoc.confidenceScore)}`} style={{ fontSize: '0.75rem' }}>
                          <span className={`confidence-dot confidence-${getConfidenceLevel(resolvedLoc.confidenceScore)}-dot`} />
                          {Math.round(resolvedLoc.confidenceScore * 100)}%
                        </span>
                      )}
                    </div>
                    <div className="stat-row">
                      <span className="stat-label">Active Contributors</span>
                      <span className="stat-value">
                        {loseGpsSignal ? 'None (Offline Fallback)' : `${resolvedLoc.clusteredContributorCount} in cluster (${resolvedLoc.contributorCount} total)`}
                      </span>
                    </div>
                    <div className="stat-row">
                      <span className="stat-label">Nearest Stop</span>
                      <span className="stat-value" style={{ maxWidth: '160px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {progress.currentStopName || 'Loading...'}
                      </span>
                    </div>
                    <div className="stat-row">
                      <span className="stat-label">Next Stop</span>
                      <span className="stat-value" style={{ color: 'var(--accent-light)', maxWidth: '160px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {progress.nextStopName || 'Terminus'}
                      </span>
                    </div>
                    <div className="stat-row">
                      <span className="stat-label">Remaining Distance</span>
                      <span className="stat-value">{progress.remainingDistanceKm?.toFixed(2)} km</span>
                    </div>
                    {progress.tripCompleted ? (
                      <div style={{
                        backgroundColor: 'var(--success-bg)',
                        border: '1px solid var(--success)',
                        color: 'var(--success)',
                        padding: '0.35rem',
                        borderRadius: 'var(--radius-sm)',
                        textAlign: 'center',
                        fontWeight: 700,
                        fontSize: '0.8rem',
                        marginTop: '0.25rem',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        gap: '0.3rem'
                      }}>
                        <CheckCircle size={12} />
                        <span>Reached Destination</span>
                      </div>
                    ) : (
                      <div className="stat-row">
                        <span className="stat-label">ETA to Terminus</span>
                        <span className="stat-value" style={{ color: '#eab308' }}>{progress.etaMinutes} mins</span>
                      </div>
                    )}
                  </div>
                )}

                {isTracking && (
                  <div className="mobile-simulator-cardText" style={{ marginTop: '0.75rem' }}>
                    <div className="mobile-card-title">
                      <Compass size={14} className="text-secondary" />
                      <span>Commuter GPS Broadcast</span>
                    </div>

                    {/* Unified Coordinates & Status Card (Mobile) */}
                    <div style={{ 
                      background: 'var(--secondary-bg)', 
                      padding: '0.75rem', 
                      borderRadius: 'var(--radius-md)', 
                      border: '1px solid rgba(37, 99, 235, 0.2)', 
                      fontSize: '0.85rem', 
                      marginTop: '0.5rem',
                      boxShadow: 'var(--shadow-sm)'
                    }}>
                      <div style={{ 
                        display: 'flex', 
                        alignItems: 'center', 
                        gap: '0.4rem', 
                        fontWeight: 700, 
                        color: 'var(--secondary)', 
                        marginBottom: '0.35rem' 
                      }}>
                        <CheckCircle size={14} />
                        <span>Broadcasting Live Device GPS</span>
                      </div>
                      {userCoords ? (
                        <div style={{ fontSize: '0.8rem', color: 'var(--text-main)', display: 'flex', flexDirection: 'column', gap: '0.2rem', fontFamily: 'monospace' }}>
                          <div>Lat: {userCoords.latitude.toFixed(5)}</div>
                          <div>Lng: {userCoords.longitude.toFixed(5)}</div>
                          <div style={{ color: 'var(--text-muted)', fontFamily: 'var(--font-sans)', fontSize: '0.75rem', marginTop: '0.15rem' }}>
                            Accuracy: {Math.round(userCoords.accuracyMeters)}m
                          </div>
                        </div>
                      ) : (
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>
                          Waiting for device GPS lock...
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
              
              {/* Stops Timeline */}
              <div style={{ padding: '0 1.25rem', fontSize: '0.8rem', fontWeight: 700, color: 'var(--text-muted)' }}>
                STOPS PATH & SCHEDULES
              </div>
              
              <div className="timeline">
                {tripStops.map((stop, index) => {
                  const hasCoords = stop.latitude !== null && stop.longitude !== null;
                  
                  // Compute timeline class based on tracking index
                  let timelineClass = '';
                  if (isTracking && resolvedLoc) {
                    const coordStops = selectedBus.routeStops.filter(s => s.latitude !== null && s.longitude !== null);
                    const nearestStop = coordStops[myLocationIndex];
                    
                    if (stop.sequence < nearestStop.sequence) {
                      timelineClass = 'passed';
                    } else if (stop.sequence === nearestStop.sequence) {
                      timelineClass = 'current';
                    } else if (coordStops[myLocationIndex + 1] && stop.sequence === coordStops[myLocationIndex + 1].sequence) {
                      timelineClass = 'next';
                    }
                  }
                  
                  return (
                    <div key={stop.stopId} className={`timeline-item ${timelineClass} ${hasCoords ? 'has-coords' : ''}`}>
                      <div className="timeline-connector" />
                      <div className="timeline-dot">
                        {stop.sequence}
                      </div>
                      
                      <div className="timeline-content">
                        <div>
                          <div className="stop-name">{stop.stopName}</div>
                          <div className="stop-name-desc">
                            {hasCoords ? '✓ Has coordinates' : '✗ Coordinates missing (approx. lookup)'}
                          </div>
                        </div>
                        
                        <div className="stop-time-group">
                          {stop.upTime && (
                            <>
                              <span className="stop-time-label">Up Time</span>
                              <span className="stop-time-val">{stop.upTime}</span>
                            </>
                          )}
                          {!stop.upTime && stop.downTime && (
                            <>
                              <span className="stop-time-label">Down Time</span>
                              <span className="stop-time-val">{stop.downTime}</span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
              </div> {/* Close details-scrollable-content */}
            </div>
          )}
        </div>
        
        {/* Right Main Map Container */}
        <div className="map-panel">
          <div id="map" ref={mapRef} />
          
          {/* Active stats panel overlay */}
          {resolvedLoc && progress && (
            <div className="map-overlay-stats">
              <div style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '0.4rem', marginBottom: '0.4rem', fontWeight: 700, fontSize: '0.95rem', fontFamily: 'var(--font-heading)', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <Clock size={16} className="text-accent" />
                <span>Resolved Live Statistics</span>
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Confidence Score</span>
                {loseGpsSignal ? (
                  <span className="confidence-indicator confidence-med" style={{ backgroundColor: 'rgba(217, 119, 6, 0.15)', color: 'var(--accent)' }}>
                    <span className="confidence-dot" style={{ backgroundColor: 'var(--accent)' }} />
                    Historical Estimate
                  </span>
                ) : (
                  <span className={`confidence-indicator confidence-${getConfidenceLevel(resolvedLoc.confidenceScore)}`}>
                    <span className={`confidence-dot confidence-${getConfidenceLevel(resolvedLoc.confidenceScore)}-dot`} />
                    {Math.round(resolvedLoc.confidenceScore * 100)}%
                  </span>
                )}
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Active Contributors</span>
                <span className="stat-value">
                  {loseGpsSignal ? 'None (Offline Fallback)' : `${resolvedLoc.clusteredContributorCount} in cluster (${resolvedLoc.contributorCount} total)`}
                </span>
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Nearest Stop</span>
                <span className="stat-value" style={{ maxWidth: '160px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {progress.currentStopName || 'Loading...'}
                </span>
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Next Stop</span>
                <span className="stat-value" style={{ color: 'var(--accent-light)', maxWidth: '160px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {progress.nextStopName || 'Terminus'}
                </span>
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Estimated Delay</span>
                <span className="stat-value" style={{ color: progress.delayMinutes > 0 ? '#ef4444' : '#22c55e' }}>
                  {loseGpsSignal ? 'N/A' : (progress.delayMinutes === null ? 'Unknown' : 
                   progress.delayMinutes > 0 ? `+${progress.delayMinutes} mins` : 
                   `${progress.delayMinutes} mins`)}
                </span>
              </div>
              
              <div className="stat-row">
                <span className="stat-label">Remaining Distance</span>
                <span className="stat-value">{progress.remainingDistanceKm?.toFixed(2)} km</span>
              </div>
              
              {progress.tripCompleted ? (
                <div style={{
                  backgroundColor: 'var(--success-bg)',
                  border: '1px solid var(--success)',
                  color: 'var(--success)',
                  padding: '0.5rem',
                  borderRadius: 'var(--radius-sm)',
                  textAlign: 'center',
                  fontWeight: 700,
                  fontSize: '0.85rem',
                  marginTop: '0.5rem',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '0.4rem',
                  width: '100%'
                }}>
                  <CheckCircle size={14} />
                  <span>Reached Destination</span>
                </div>
              ) : (
                <div className="stat-row">
                  <span className="stat-label">ETA to Terminus</span>
                  <span className="stat-value" style={{ color: '#eab308' }}>{progress.etaMinutes} mins</span>
                </div>
              )}
            </div>
          )}
          

        </div>
        
      </main>
    </div>
  );
}

export default App;
