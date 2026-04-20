import { useEffect, useRef, useCallback, useState } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

const SCU_CENTER = [37.3496, -121.939];
const INITIAL_ZOOM = 8;

const DARK_TILES = "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";
const DARK_ATTR =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>';

const ROUTE_COORDS = [
  [37.3496, -121.939],
  [37.3350, -121.890],
  [37.2000, -121.760],
  [36.9933, -121.553],
  [36.8578, -121.404],
  [36.6500, -121.200],
  [36.6500, -120.950],
  [36.3300, -120.480],
  [36.1397, -120.360],
  [35.8644, -119.387],
  [35.4300, -118.870],
  [35.1319, -118.528],
  [35.0786, -118.437],
  [35.0594, -118.152],
  [35.0478, -117.825],
  [34.9500, -117.350],
  [34.8480, -117.083],
  [34.9378, -116.955],
  [34.6500, -116.700],
  [34.3312, -116.387],
  [34.2928, -116.389],
  [34.2447, -116.316],
  [34.1573, -116.497],
  [34.1356, -116.313],
  [34.0700, -116.170],
  [34.0125, -116.169],
  [33.9978, -116.050],
  [33.9472, -115.903],
];

const CATEGORY_COLORS = {
  historic: "#f59e0b",
  food: "#ef4444",
  nature: "#22c55e",
  outdoor: "#22c55e",
  landmark: "#3b82f6",
  quirky: "#a855f7",
  roadside: "#f97316",
  art: "#ec4899",
  wildlife: "#14b8a6",
  default: "#6b7280",
};

const PERSON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" width="18" height="18">
  <circle cx="12" cy="4" r="2.5"/>
  <path d="M15.5 22h-2l-1-4.5h-1L10.5 22h-2l1.5-7H9.5a1.5 1.5 0 0 1-1.5-1.5v-4A2.5 2.5 0 0 1 10.5 7h3A2.5 2.5 0 0 1 16 9.5v4a1.5 1.5 0 0 1-1.5 1.5H14z"/>
</svg>`;

function makeDotIcon(color) {
  return L.divIcon({
    className: "",
    html: `<div style="
      width:12px;height:12px;border-radius:50%;
      background:${color};
      border:2px solid rgba(255,255,255,0.3);
      box-shadow:0 0 8px ${color}66;
    "></div>`,
    iconSize: [12, 12],
    iconAnchor: [6, 6],
  });
}

function makeHighlightIcon() {
  return L.divIcon({
    className: "",
    html: `<div style="
      width:28px;height:28px;border-radius:50%;
      background:#f59e0b;
      border:3px solid white;
      box-shadow:0 0 20px #f59e0b88, 0 0 40px #f59e0b44;
      animation:pulse 2s infinite;
    "></div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
  });
}

const userIcon = L.divIcon({
  className: "",
  html: `<div style="
    width:28px;height:28px;border-radius:50%;
    background:#f59e0b;
    border:2px solid white;
    box-shadow:0 0 12px #f59e0b88;
    cursor:grab;
    display:flex;align-items:center;justify-content:center;
  ">${PERSON_SVG}</div>`,
  iconSize: [28, 28],
  iconAnchor: [14, 14],
});

export default function MapPanel({ onLocationChange, nearbyPois, highlightPoi, onResetDemo }) {
  const mapContainer = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);
  const poiLayerRef = useRef(null);
  const allPoiLayerRef = useRef(null);
  const highlightMarkerRef = useRef(null);
  const callbackRef = useRef(onLocationChange);
  const debounceRef = useRef(null);
  const [allPois, setAllPois] = useState([]);
  const [isDraggingPegman, setIsDraggingPegman] = useState(false);

  callbackRef.current = onLocationChange;

  useEffect(() => {
    fetch("/api/pois")
      .then((res) => res.json())
      .then(setAllPois)
      .catch(console.error);
  }, []);

  useEffect(() => {
    const container = mapContainer.current;
    if (!container) return;

    const map = L.map(container, {
      center: SCU_CENTER,
      zoom: INITIAL_ZOOM,
      zoomControl: false,
    });

    L.tileLayer(DARK_TILES, {
      attribution: DARK_ATTR,
      maxZoom: 19,
    }).addTo(map);

    L.control.zoom({ position: "topleft" }).addTo(map);

    L.polyline(ROUTE_COORDS, {
      color: "#f59e0b",
      weight: 3,
      opacity: 0.35,
      dashArray: "8 6",
      smoothFactor: 1.5,
    }).addTo(map);

    const marker = L.marker(SCU_CENTER, {
      icon: userIcon,
      draggable: true,
    }).addTo(map);

    marker.on("dragend", () => {
      const { lat, lng } = marker.getLatLng();
      if (debounceRef.current) clearTimeout(debounceRef.current);
      debounceRef.current = setTimeout(() => {
        callbackRef.current(lat, lng);
      }, 400);
    });

    const allPoiLayer = L.layerGroup().addTo(map);
    const poiLayer = L.layerGroup().addTo(map);

    mapRef.current = map;
    markerRef.current = marker;
    poiLayerRef.current = poiLayer;
    allPoiLayerRef.current = allPoiLayer;

    return () => {
      map.remove();
      mapRef.current = null;
      markerRef.current = null;
      poiLayerRef.current = null;
      allPoiLayerRef.current = null;
    };
  }, []);

  useEffect(() => {
    const layer = allPoiLayerRef.current;
    if (!layer || allPois.length === 0) return;

    layer.clearLayers();
    allPois.forEach((poi) => {
      const color = CATEGORY_COLORS[poi.category] || CATEGORY_COLORS.default;
      L.marker([poi.lat, poi.lng], { icon: makeDotIcon(color) })
        .bindTooltip(poi.name, { direction: "top", offset: [0, -8] })
        .addTo(layer);
    });
  }, [allPois]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    if (highlightMarkerRef.current) {
      highlightMarkerRef.current.remove();
      highlightMarkerRef.current = null;
    }

    if (highlightPoi) {
      const m = L.marker([highlightPoi.lat, highlightPoi.lng], {
        icon: makeHighlightIcon(),
      }).addTo(map);

      map.flyTo([highlightPoi.lat, highlightPoi.lng], 12, { duration: 1.5 });
      highlightMarkerRef.current = m;
    }
  }, [highlightPoi]);

  const handleRecenter = useCallback(() => {
    if (!mapRef.current || !markerRef.current) return;
    const { lat, lng } = markerRef.current.getLatLng();
    mapRef.current.flyTo([lat, lng], 10, { duration: 0.8 });
  }, []);

  // Pegman drag-and-drop: drop the person anywhere on the map
  const handlePegmanDragStart = useCallback((e) => {
    setIsDraggingPegman(true);
    // Use a transparent drag image so only our cursor styling shows
    const ghost = document.createElement("div");
    ghost.style.opacity = "0";
    document.body.appendChild(ghost);
    e.dataTransfer.setDragImage(ghost, 0, 0);
    e.dataTransfer.effectAllowed = "move";
    // Clean up ghost after drag starts
    requestAnimationFrame(() => ghost.remove());
  }, []);

  const handleMapDragOver = useCallback((e) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  }, []);

  const handleMapDrop = useCallback((e) => {
    e.preventDefault();
    setIsDraggingPegman(false);

    const map = mapRef.current;
    const marker = markerRef.current;
    const container = mapContainer.current;
    if (!map || !marker || !container) return;

    const rect = container.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const latlng = map.containerPointToLatLng(L.point(x, y));

    marker.setLatLng(latlng);
    map.flyTo(latlng, Math.max(map.getZoom(), 12), { duration: 0.6 });

    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      callbackRef.current(latlng.lat, latlng.lng);
    }, 400);
  }, []);

  const handlePegmanDragEnd = useCallback(() => {
    setIsDraggingPegman(false);
  }, []);

  return (
    <div style={{ position: "relative", width: "100%", height: "100%" }}>
      <div
        ref={mapContainer}
        style={{
          width: "100%",
          height: "100%",
          cursor: isDraggingPegman ? "crosshair" : undefined,
        }}
        onDragOver={handleMapDragOver}
        onDrop={handleMapDrop}
      />

      {isDraggingPegman && (
        <div style={styles.dropOverlay}>
          <div style={styles.dropText}>Drop to place your location</div>
        </div>
      )}

      <div style={styles.topBar}>
        <div style={styles.logo}>
          <span style={styles.logoIcon}>◎</span>
          <span style={styles.logoText}>Orbit</span>
        </div>
        <div style={styles.instructions}>Drag the person icon to explore the route</div>
      </div>

      <div style={styles.controls}>
        <div
          draggable
          onDragStart={handlePegmanDragStart}
          onDragEnd={handlePegmanDragEnd}
          style={styles.pegmanBtn}
          title="Drag and drop onto the map to jump to a location"
        >
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#f59e0b" width="22" height="22">
            <circle cx="12" cy="4" r="2.5"/>
            <path d="M15.5 22h-2l-1-4.5h-1L10.5 22h-2l1.5-7H9.5a1.5 1.5 0 0 1-1.5-1.5v-4A2.5 2.5 0 0 1 10.5 7h3A2.5 2.5 0 0 1 16 9.5v4a1.5 1.5 0 0 1-1.5 1.5H14z"/>
          </svg>
        </div>
        <button style={styles.controlBtn} onClick={handleRecenter} title="Re-center on marker">
          ⌖
        </button>
        <button style={styles.controlBtn} onClick={onResetDemo} title="Reset demo">
          ↺
        </button>
      </div>

      <div style={styles.legend}>
        {Object.entries(CATEGORY_COLORS)
          .filter(([k]) => k !== "default")
          .map(([cat, color]) => (
            <div key={cat} style={styles.legendItem}>
              <span style={{ ...styles.legendDot, background: color }} />
              <span>{cat}</span>
            </div>
          ))}
      </div>

      {nearbyPois.length > 0 && (
        <div style={styles.poiCount}>
          {nearbyPois.length} place{nearbyPois.length !== 1 ? "s" : ""} nearby
        </div>
      )}
    </div>
  );
}

const styles = {
  topBar: {
    position: "absolute",
    top: 16,
    left: "50%",
    transform: "translateX(-50%)",
    display: "flex",
    alignItems: "center",
    gap: 16,
    padding: "10px 20px",
    background: "rgba(10, 12, 16, 0.85)",
    backdropFilter: "blur(12px)",
    borderRadius: "var(--radius-lg)",
    border: "1px solid var(--border)",
    zIndex: 1000,
  },
  logo: {
    display: "flex",
    alignItems: "center",
    gap: 8,
  },
  logoIcon: {
    fontSize: 20,
    color: "var(--accent)",
  },
  logoText: {
    fontFamily: "var(--font-display)",
    fontSize: 20,
    fontWeight: 400,
    color: "var(--text-primary)",
  },
  instructions: {
    fontSize: 13,
    color: "var(--text-muted)",
    borderLeft: "1px solid var(--border)",
    paddingLeft: 16,
  },
  controls: {
    position: "absolute",
    bottom: 24,
    left: 16,
    display: "flex",
    flexDirection: "column",
    gap: 8,
    zIndex: 1000,
  },
  controlBtn: {
    width: 40,
    height: 40,
    borderRadius: "var(--radius-sm)",
    background: "rgba(10, 12, 16, 0.85)",
    backdropFilter: "blur(12px)",
    border: "1px solid var(--border)",
    color: "var(--text-secondary)",
    fontSize: 20,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    transition: "all 0.15s ease",
    cursor: "pointer",
  },
  pegmanBtn: {
    width: 40,
    height: 40,
    borderRadius: "var(--radius-sm)",
    background: "rgba(10, 12, 16, 0.85)",
    backdropFilter: "blur(12px)",
    border: "2px solid #f59e0b55",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "grab",
    transition: "all 0.15s ease",
  },
  dropOverlay: {
    position: "absolute",
    inset: 0,
    background: "rgba(245, 158, 11, 0.08)",
    border: "2px dashed #f59e0b66",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    zIndex: 999,
    pointerEvents: "none",
  },
  dropText: {
    padding: "8px 20px",
    background: "rgba(10, 12, 16, 0.9)",
    borderRadius: "var(--radius-lg)",
    border: "1px solid #f59e0b44",
    color: "#f59e0b",
    fontSize: 14,
    fontWeight: 600,
  },
  legend: {
    position: "absolute",
    bottom: 24,
    right: 16,
    display: "flex",
    flexDirection: "column",
    gap: 4,
    padding: "10px 14px",
    background: "rgba(10, 12, 16, 0.85)",
    backdropFilter: "blur(12px)",
    borderRadius: "var(--radius-md)",
    border: "1px solid var(--border)",
    fontSize: 11,
    color: "var(--text-muted)",
    zIndex: 1000,
  },
  legendItem: {
    display: "flex",
    alignItems: "center",
    gap: 6,
  },
  legendDot: {
    width: 8,
    height: 8,
    borderRadius: "50%",
    flexShrink: 0,
  },
  poiCount: {
    position: "absolute",
    bottom: 24,
    left: "50%",
    transform: "translateX(-50%)",
    padding: "6px 16px",
    background: "rgba(10, 12, 16, 0.85)",
    backdropFilter: "blur(12px)",
    borderRadius: 100,
    border: "1px solid var(--border)",
    fontSize: 12,
    color: "var(--text-secondary)",
    zIndex: 1000,
  },
};
