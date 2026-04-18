import { useEffect, useRef, useState } from "react";
import {
  Circle,
  MapContainer,
  Marker,
  Popup,
  TileLayer,
  Tooltip,
  useMap,
  useMapEvents,
} from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { interestColor, poiInterestTheme } from "../lib/interests.js";

const DARK_TILES =
  "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png";
const DARK_ATTR =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>';

const dotIconCache = new Map();
function getDotIcon(color, dim = false) {
  const key = `${color}:${dim ? 1 : 0}`;
  if (!dotIconCache.has(key)) {
    const op = dim ? 0.45 : 1;
    const size = dim ? 11 : 14;
    dotIconCache.set(
      key,
      L.divIcon({
        className: "",
        html: `<div style="
      width:${size}px;height:${size}px;border-radius:50%;
      background:${color};
      opacity:${op};
      border:2px solid rgba(255,255,255,${dim ? 0.25 : 0.4});
      box-shadow:0 0 8px ${color}55;
    "></div>`,
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      })
    );
  }
  return dotIconCache.get(key);
}

const starIconCache = new Map();
function getStarIcon(color) {
  if (!starIconCache.has(color)) {
    starIconCache.set(
      color,
      L.divIcon({
        className: "",
        html: `<div style="
      width:26px;height:26px;border-radius:50%;
      background:${color}22;
      border:2px solid ${color};
      display:flex;align-items:center;justify-content:center;
      font-size:13px;line-height:1;color:${color};
      box-shadow:0 0 12px ${color}66;
    ">★</div>`,
        iconSize: [26, 26],
        iconAnchor: [13, 13],
      })
    );
  }
  return starIconCache.get(color);
}

const userIcon = L.divIcon({
  className: "",
  html: `<div style="
    width:20px;height:20px;border-radius:50%;
    background:#f1f5f9;
    border:3px solid #38bdf8;
    box-shadow:0 0 12px #38bdf899;
  "></div>`,
  iconSize: [20, 20],
  iconAnchor: [10, 10],
});

function Recenter({ lat, lng, zoom }) {
  const map = useMap();
  const prev = useRef(null);
  useEffect(() => {
    const p = prev.current;
    if (!p) {
      prev.current = { lat, lng };
      map.setView([lat, lng], zoom, { animate: false });
      return;
    }
    const moved =
      Math.abs(p.lat - lat) > 1e-5 || Math.abs(p.lng - lng) > 1e-5;
    prev.current = { lat, lng };
    if (!moved) return;
    map.setView([lat, lng], zoom, { animate: true });
  }, [lat, lng, zoom, map]);
  return null;
}

function MapClickHandler({ onPickRef }) {
  useMapEvents({
    click(e) {
      onPickRef.current?.(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

export default function MapView({
  userLat,
  userLng,
  insideOsmPois,
  outsideOsmPois,
  wishlistMarkers,
  passiveMode,
  passiveRadiusM,
  onPickLocation,
  onSelectPoi,
  simulating,
}) {
  /** Leaflet + React 18 StrictMode double-mount leaves a blank map without a deferred mount. */
  const [mapReady, setMapReady] = useState(false);
  useEffect(() => {
    setMapReady(true);
  }, []);

  const selectRef = useRef(onSelectPoi);
  selectRef.current = onSelectPoi;
  const pickRef = useRef(onPickLocation);
  pickRef.current = onPickLocation;

  const zoom = 14;

  if (!mapReady) {
    return (
      <div
        style={{
          height: "100%",
          width: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          background: "var(--panel)",
          color: "var(--muted)",
          fontSize: 14,
        }}
      >
        Loading map…
      </div>
    );
  }

  return (
    <MapContainer
      center={[userLat, userLng]}
      zoom={zoom}
      style={{ height: "100%", width: "100%", minHeight: 200 }}
      scrollWheelZoom
    >
      <TileLayer attribution={DARK_ATTR} url={DARK_TILES} />
      <Recenter lat={userLat} lng={userLng} zoom={zoom} />
      <MapClickHandler onPickRef={pickRef} />
      {passiveMode && (
        <Circle
          center={[userLat, userLng]}
          radius={passiveRadiusM}
          pathOptions={{
            color: "#f4b942",
            weight: 1,
            fillColor: "#f4b942",
            fillOpacity: 0.08,
          }}
        />
      )}
      {(outsideOsmPois || []).map((p) => {
        const theme = poiInterestTheme(p);
        const color = interestColor(theme);
        return (
          <Marker
            key={p.id}
            position={[p.lat, p.lng]}
            icon={getDotIcon(color, true)}
            eventHandlers={{ click: () => selectRef.current?.(p) }}
          >
            <Tooltip direction="top" offset={[0, -6]} opacity={1}>
              {p.name} · wider area
            </Tooltip>
            <Popup>
              <div style={{ minWidth: 180 }}>
                <strong>{p.name}</strong>
                <div style={{ fontSize: 11, marginTop: 4, opacity: 0.8 }}>
                  Outside guide ring — tap Listen to preview.
                </div>
                <div style={{ fontSize: 12, marginTop: 6, opacity: 0.85 }}>
                  {p.short_description}
                </div>
                <button
                  type="button"
                  style={{
                    marginTop: 10,
                    width: "100%",
                    border: "none",
                    borderRadius: 8,
                    padding: "8px 10px",
                    background: "#1e293b",
                    color: "#f8fafc",
                  }}
                  onClick={() => selectRef.current?.(p)}
                >
                  Listen
                </button>
              </div>
            </Popup>
          </Marker>
        );
      })}
      {(insideOsmPois || []).map((p) => {
        const theme = poiInterestTheme(p);
        const color = interestColor(theme);
        return (
          <Marker
            key={p.id}
            position={[p.lat, p.lng]}
            icon={getDotIcon(color, false)}
            eventHandlers={{ click: () => selectRef.current?.(p) }}
          >
            <Tooltip direction="top" offset={[0, -8]} opacity={1}>
              {p.name}
            </Tooltip>
            <Popup>
              <div style={{ minWidth: 180 }}>
                <strong>{p.name}</strong>
                <div style={{ fontSize: 12, marginTop: 6, opacity: 0.85 }}>
                  {p.short_description}
                </div>
                <button
                  type="button"
                  style={{
                    marginTop: 10,
                    width: "100%",
                    border: "none",
                    borderRadius: 8,
                    padding: "8px 10px",
                    background: "#1e293b",
                    color: "#f8fafc",
                  }}
                  onClick={() => selectRef.current?.(p)}
                >
                  Listen
                </button>
              </div>
            </Popup>
          </Marker>
        );
      })}
      {(wishlistMarkers || []).map((w) => {
        const p = w.poi;
        return (
          <Marker
            key={p.id}
            position={[p.lat, p.lng]}
            icon={getStarIcon(w.groupColor)}
            eventHandlers={{ click: () => selectRef.current?.(p) }}
          >
            <Tooltip direction="top" offset={[0, -10]} opacity={1}>
              ★ {p.name} · {w.groupName}
            </Tooltip>
            <Popup>
              <div style={{ minWidth: 200 }}>
                <div style={{ fontSize: 11, color: "#a78bfa", marginBottom: 4 }}>
                  Your plan · {w.groupName}
                </div>
                <strong>{p.name}</strong>
                <div style={{ fontSize: 12, marginTop: 6, opacity: 0.85 }}>
                  {p.short_description}
                </div>
                <button
                  type="button"
                  style={{
                    marginTop: 10,
                    width: "100%",
                    border: "none",
                    borderRadius: 8,
                    padding: "8px 10px",
                    background: "#1e293b",
                    color: "#f8fafc",
                  }}
                  onClick={() => selectRef.current?.(p)}
                >
                  Listen
                </button>
              </div>
            </Popup>
          </Marker>
        );
      })}
      <Marker position={[userLat, userLng]} icon={userIcon}>
        <Tooltip direction="right" offset={[10, 0]} opacity={1} permanent={false}>
          {simulating ? "Simulated you" : "Your position"}
        </Tooltip>
      </Marker>
    </MapContainer>
  );
}
