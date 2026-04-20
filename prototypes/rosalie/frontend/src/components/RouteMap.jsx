import { useEffect } from "react";
import { MapContainer, Marker, Polyline, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";

import "leaflet/dist/leaflet.css";

const DefaultIcon = L.icon({
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
  iconSize: [25, 41],
  iconAnchor: [12, 41],
});

L.Marker.prototype.options.icon = DefaultIcon;

function FitBounds({ a, b }) {
  const map = useMap();
  useEffect(() => {
    if (!a || !b) return;
    const bounds = L.latLngBounds([a, b]);
    map.fitBounds(bounds, { padding: [36, 36], maxZoom: 16 });
  }, [map, a, b]);
  return null;
}

export default function RouteMap({ userLat, userLng, placeLat, placeLng }) {
  const center = [(userLat + placeLat) / 2, (userLng + placeLng) / 2];
  return (
    <div className="map-panel">
      <MapContainer center={center} zoom={15} scrollWheelZoom style={{ height: 240, width: "100%" }}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitBounds a={[userLat, userLng]} b={[placeLat, placeLng]} />
        <Marker position={[userLat, userLng]} />
        <Marker position={[placeLat, placeLng]} />
        <Polyline positions={[[userLat, userLng], [placeLat, placeLng]]} pathOptions={{ color: "#c9a227", weight: 4 }} />
      </MapContainer>
    </div>
  );
}
