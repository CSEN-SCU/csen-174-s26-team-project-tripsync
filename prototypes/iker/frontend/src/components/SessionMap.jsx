import { useEffect, useMemo, useRef } from "react";
import {
  MapContainer,
  TileLayer,
  Marker,
  Tooltip,
  useMap,
} from "react-leaflet";
import L from "leaflet";

// Use divIcons so we can match the rest of the UI (avatars + numbered pins)
// without shipping image assets.
function memberIcon(emoji) {
  return L.divIcon({
    className: "",
    html: `<div class="member-dot">${emoji || "🙂"}</div>`,
    iconSize: [32, 32],
    iconAnchor: [16, 16],
  });
}

function poiIcon(index, picked) {
  const cls = picked ? "poi-pin picked" : "poi-pin";
  return L.divIcon({
    className: "",
    html: `<div class="${cls}"><span>${index}</span></div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 28],
  });
}

// Helper component: fit bounds whenever members/POIs change meaningfully.
function FitToContent({ points }) {
  const map = useMap();
  const prev = useRef("");
  useEffect(() => {
    if (!points.length) return;
    const key = points.map((p) => `${p[0].toFixed(4)},${p[1].toFixed(4)}`).join("|");
    if (key === prev.current) return;
    prev.current = key;
    const bounds = L.latLngBounds(points);
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 16 });
  }, [points, map]);
  return null;
}

export default function SessionMap({ state, me }) {
  const center = useMemo(
    () => [state.center.lat, state.center.lng],
    [state.center.lat, state.center.lng]
  );

  const points = useMemo(() => {
    const pts = [];
    for (const m of state.members) {
      if (m.lat != null && m.lng != null) pts.push([m.lat, m.lng]);
    }
    for (const p of state.pois) pts.push([p.lat, p.lng]);
    if (!pts.length) pts.push(center);
    return pts;
  }, [state.members, state.pois, center]);

  return (
    <div className="map-wrap">
      <MapContainer
        center={center}
        zoom={15}
        scrollWheelZoom
        style={{ height: "100%", width: "100%" }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitToContent points={points} />

        {state.members.map((m) =>
          m.lat != null && m.lng != null ? (
            <Marker
              key={`m-${m.id}`}
              position={[m.lat, m.lng]}
              icon={memberIcon(m.avatar)}
            >
              <Tooltip direction="top" offset={[0, -8]}>
                <strong>{m.name}</strong>
                {me && me.id === m.id ? " (you)" : ""}
                {m.interests?.length ? ` · ${m.interests.join(", ")}` : ""}
              </Tooltip>
            </Marker>
          ) : null
        )}

        {state.pois.map((p, idx) => {
          const picked = state.destination && state.destination.id === p.id;
          return (
            <Marker
              key={`p-${p.id}`}
              position={[p.lat, p.lng]}
              icon={poiIcon(idx + 1, !!picked)}
            >
              <Tooltip direction="top" offset={[0, -28]}>
                <strong>{p.name}</strong>
                <br />
                {p.walk_minutes} min walk · {p.category}
              </Tooltip>
            </Marker>
          );
        })}
      </MapContainer>
    </div>
  );
}
