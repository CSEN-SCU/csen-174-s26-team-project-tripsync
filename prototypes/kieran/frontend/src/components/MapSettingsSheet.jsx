import { useMemo } from "react";
import {
  INTEREST_COLORS,
  INTEREST_ORDER,
  interestColor,
  poiInterestTheme,
} from "../lib/interests.js";

function toRad(d) {
  return (d * Math.PI) / 180;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const r = 6371;
  const dlat = toRad(lat2 - lat1);
  const dlng = toRad(lng2 - lng1);
  const a =
    Math.sin(dlat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dlng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function MiniPoiList({ title, hint, items, onPick, onClose }) {
  return (
    <div style={{ marginBottom: 14 }}>
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--text)" }}>{title}</div>
      <div style={{ fontSize: 11, color: "var(--muted)", marginBottom: 6 }}>{hint}</div>
      <ul style={{ listStyle: "none", margin: 0, padding: 0, maxHeight: 140, overflow: "auto" }}>
        {items.map((p) => {
          const theme = poiInterestTheme(p);
          const c = interestColor(theme);
          return (
            <li key={p.id}>
              <button
                type="button"
                onClick={() => {
                  onPick(p);
                  onClose();
                }}
                style={{
                  width: "100%",
                  textAlign: "left",
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 6px",
                  border: "none",
                  borderBottom: "1px solid rgba(255,255,255,0.06)",
                  background: "transparent",
                  color: "var(--text)",
                  cursor: "pointer",
                  fontSize: 12,
                }}
              >
                <span
                  style={{
                    width: 7,
                    height: 7,
                    borderRadius: "50%",
                    background: c,
                    flexShrink: 0,
                  }}
                />
                <span style={{ flex: 1, minWidth: 0 }}>
                  <span style={{ fontWeight: 600 }}>{p.name}</span>
                  <span style={{ color: "var(--muted)", marginLeft: 6 }}>
                    {p.distance_km} km
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
      {items.length === 0 && (
        <div style={{ fontSize: 11, color: "var(--muted)" }}>None in this fetch.</div>
      )}
    </div>
  );
}

export default function MapSettingsSheet({
  open,
  onClose,
  interests,
  onToggleInterest,
  passiveMode,
  onTogglePassive,
  onGeolocate,
  onSimulate,
  simulating,
  insideRingPois,
  outsideRingPois,
  ringRadiusM,
  lastPoiFetchAt,
  onSelectPoi,
  noInterests,
  wishlistGroups,
  wishlistItems,
  userLat,
  userLng,
  passiveKm,
  onStartWishDrop,
  onAddWishlistGroup,
  onRemoveWishlistGroup,
  onRemoveWishlistItem,
  onUpdateWishlistItem,
  visibleWishGroupIds,
  onToggleWishGroupMapVisible,
  onSetAllWishGroupsMapVisible,
}) {
  const groupsById = useMemo(
    () => new Map(wishlistGroups.map((g) => [g.id, g])),
    [wishlistGroups]
  );

  const wishRows = useMemo(() => {
    return wishlistItems
      .map((item) => {
        const g = groupsById.get(item.groupId) || wishlistGroups[0];
        const d = haversineKm(userLat, userLng, item.lat, item.lng);
        return {
          ...item,
          group: g,
          distance_km: Math.round(d * 1000) / 1000,
          inRing: d < passiveKm,
        };
      })
      .sort((a, b) => a.distance_km - b.distance_km);
  }, [wishlistItems, groupsById, wishlistGroups, userLat, userLng, passiveKm]);

  if (!open) return null;

  return (
    <>
      <button
        type="button"
        aria-label="Close filters"
        onClick={onClose}
        style={{
          position: "fixed",
          inset: 0,
          zIndex: 899,
          border: "none",
          background: "rgba(0,0,0,0.45)",
          cursor: "pointer",
        }}
      />
      <div
        role="dialog"
        aria-modal="true"
        style={{
          position: "fixed",
          top: 0,
          right: 0,
          bottom: 0,
          width: "min(360px, 92vw)",
          zIndex: 900,
          background: "var(--panel)",
          borderLeft: "1px solid var(--border)",
          boxShadow: "-12px 0 40px rgba(0,0,0,0.4)",
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            padding: "14px 16px",
            borderBottom: "1px solid var(--border)",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <span style={{ fontWeight: 700, fontSize: 16 }}>Filters & places</span>
          <button
            type="button"
            onClick={onClose}
            style={{
              border: "none",
              background: "rgba(255,255,255,0.08)",
              color: "var(--text)",
              borderRadius: 8,
              padding: "6px 12px",
              cursor: "pointer",
              fontSize: 13,
            }}
          >
            Done
          </button>
        </div>

        <div style={{ flex: 1, overflow: "auto", padding: "14px 16px" }}>
          {noInterests && (
            <div
              style={{
                padding: 10,
                marginBottom: 12,
                borderRadius: 8,
                border: "1px solid rgba(244,185,66,0.35)",
                background: "rgba(244,185,66,0.08)",
                fontSize: 12,
              }}
            >
              Pick at least one interest so the map can show pins.
            </div>
          )}

          <div style={{ fontSize: 11, color: "var(--muted)", marginBottom: 8 }}>
            Interests (map pins)
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 6, marginBottom: 14 }}>
            {INTEREST_ORDER.map((key) => {
              const on = interests.includes(key);
              const c = INTEREST_COLORS[key];
              return (
                <button
                  key={key}
                  type="button"
                  onClick={() => onToggleInterest(key)}
                  style={{
                    borderRadius: 999,
                    padding: "5px 10px",
                    fontSize: 11,
                    border: on ? `2px solid ${c}` : `1px solid ${c}44`,
                    background: on ? `${c}22` : "transparent",
                    color: on ? c : "var(--muted)",
                    cursor: "pointer",
                  }}
                >
                  {key}
                </button>
              );
            })}
          </div>

          <label
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8,
              marginBottom: 12,
              fontSize: 13,
              color: "var(--text)",
            }}
          >
            <input
              type="checkbox"
              checked={passiveMode}
              onChange={(e) => onTogglePassive(e.target.checked)}
            />
            Passive heads-up (~{Math.round(ringRadiusM)} m ring)
          </label>

          <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
            <button type="button" onClick={onGeolocate} style={btnSecondary}>
              Use my location
            </button>
            <button
              type="button"
              onClick={onSimulate}
              style={{
                ...btnSecondary,
                borderColor: simulating ? "var(--accent)" : "var(--border)",
                color: simulating ? "var(--accent)" : "var(--muted)",
              }}
            >
              {simulating ? "Stop sim" : "Simulate walk"}
            </button>
          </div>

          {lastPoiFetchAt != null && (
            <div style={{ fontSize: 10, color: "var(--muted)", marginBottom: 14 }}>
              Data refreshed {new Date(lastPoiFetchAt).toLocaleTimeString()}
            </div>
          )}

          <MiniPoiList
            title="Inside ring (OSM)"
            hint="Matches filters; in passive ring"
            items={insideRingPois}
            onPick={onSelectPoi}
            onClose={onClose}
          />
          <MiniPoiList
            title="Wider area (OSM)"
            hint="Dimmer on map — outside ring"
            items={outsideRingPois}
            onPick={onSelectPoi}
            onClose={onClose}
          />

          <div style={{ marginTop: 8, marginBottom: 10, borderTop: "1px solid var(--border)", paddingTop: 14 }}>
            <div style={{ fontSize: 12, fontWeight: 600, color: "var(--text)", marginBottom: 4 }}>
              Itineraries on the map
            </div>
            <div style={{ fontSize: 11, color: "var(--muted)", marginBottom: 10, lineHeight: 1.45 }}>
              Turn itineraries on or off to show or hide their star pins. Visible plans inside the ring still join{" "}
              <strong style={{ color: "var(--text)" }}>Next</strong> / passive rotation.
            </div>

            <div
              style={{
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                gap: 8,
                marginBottom: 8,
              }}
            >
              <div style={{ fontSize: 11, color: "var(--muted)" }}>Show on map</div>
              <div style={{ display: "flex", gap: 6 }}>
                <button type="button" onClick={() => onSetAllWishGroupsMapVisible(true)} style={btnTiny}>
                  All
                </button>
                <button type="button" onClick={() => onSetAllWishGroupsMapVisible(false)} style={btnTiny}>
                  None
                </button>
              </div>
            </div>
            <ul style={{ listStyle: "none", margin: 0, padding: 0, marginBottom: 10 }}>
              {wishlistGroups.map((g) => {
                const onMap = visibleWishGroupIds.includes(g.id);
                return (
                  <li
                    key={g.id}
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: 8,
                      padding: "6px 0",
                      borderBottom: "1px solid rgba(255,255,255,0.06)",
                      fontSize: 12,
                    }}
                  >
                    <label
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        cursor: "pointer",
                        flexShrink: 0,
                      }}
                      title="Show this itinerary’s pins on the map"
                    >
                      <input
                        type="checkbox"
                        checked={onMap}
                        onChange={() => onToggleWishGroupMapVisible(g.id)}
                      />
                    </label>
                    <span
                      style={{
                        width: 10,
                        height: 10,
                        borderRadius: "50%",
                        background: g.color,
                        flexShrink: 0,
                        opacity: onMap ? 1 : 0.35,
                      }}
                    />
                    <span
                      style={{
                        flex: 1,
                        minWidth: 0,
                        fontWeight: 600,
                        opacity: onMap ? 1 : 0.55,
                      }}
                    >
                      {g.name}
                    </span>
                    <button
                      type="button"
                      onClick={() => onStartWishDrop(g.id)}
                      style={{ ...btnTiny, flexShrink: 0 }}
                    >
                      Drop pin
                    </button>
                    {wishlistGroups.length > 1 && (
                      <button
                        type="button"
                        onClick={() => onRemoveWishlistGroup(g.id)}
                        style={{ ...btnTiny, color: "var(--danger)", borderColor: "rgba(248,113,113,0.35)" }}
                      >
                        Remove
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
            <button
              type="button"
              onClick={() => {
                const n = window.prompt("New group name:");
                if (n?.trim()) onAddWishlistGroup(n.trim());
              }}
              style={{ ...btnSecondary, width: "100%", marginBottom: 14 }}
            >
              + Add group
            </button>

            <div style={{ fontSize: 11, color: "var(--muted)", marginBottom: 6 }}>Items</div>
            <ul style={{ listStyle: "none", margin: 0, padding: 0, maxHeight: 200, overflow: "auto" }}>
              {wishRows.map((row) => (
                <li
                  key={row.id}
                  style={{
                    padding: "8px 0",
                    borderBottom: "1px solid rgba(255,255,255,0.06)",
                    fontSize: 12,
                  }}
                >
                  <div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
                    <span style={{ fontSize: 14, color: row.group.color, flexShrink: 0 }}>★</span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 600 }}>{row.name}</div>
                      <div style={{ fontSize: 10, color: "var(--muted)", marginTop: 2 }}>
                        {row.distance_km} km · {row.inRing ? "in ring" : "outside ring"} · {row.group.name}
                      </div>
                      <select
                        value={row.groupId}
                        onChange={(e) =>
                          onUpdateWishlistItem(row.id, { groupId: e.target.value })
                        }
                        style={{
                          marginTop: 6,
                          fontSize: 11,
                          borderRadius: 6,
                          border: "1px solid var(--border)",
                          background: "#121a30",
                          color: "var(--text)",
                          padding: "4px 6px",
                          maxWidth: "100%",
                        }}
                      >
                        {wishlistGroups.map((g) => (
                          <option key={g.id} value={g.id}>
                            {g.name}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div style={{ display: "flex", flexDirection: "column", gap: 4, flexShrink: 0 }}>
                      <button
                        type="button"
                        onClick={() => {
                          const desc = row.note?.trim()
                            ? row.note.trim()
                            : `On your ${row.group.name} list — something you want to do here.`;
                          const p = {
                            id: `wish-${row.id}`,
                            name: row.name,
                            lat: row.lat,
                            lng: row.lng,
                            category: row.group.name,
                            short_description: desc,
                            tags: ["wishlist"],
                            distance_km: row.distance_km,
                          };
                          onSelectPoi(p);
                          onClose();
                        }}
                        style={btnTiny}
                      >
                        Listen
                      </button>
                      <button
                        type="button"
                        onClick={() => onRemoveWishlistItem(row.id)}
                        style={{ ...btnTiny, color: "var(--danger)", borderColor: "rgba(248,113,113,0.35)" }}
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
            {wishRows.length === 0 && (
              <div style={{ fontSize: 11, color: "var(--muted)" }}>No saved plans yet. Use Drop pin on a group.</div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}

const btnSecondary = {
  borderRadius: 8,
  padding: "7px 12px",
  fontSize: 12,
  border: "1px solid var(--border)",
  background: "transparent",
  color: "var(--text)",
  cursor: "pointer",
};

const btnTiny = {
  borderRadius: 6,
  padding: "4px 8px",
  fontSize: 10,
  border: "1px solid var(--border)",
  background: "rgba(255,255,255,0.06)",
  color: "var(--text)",
  cursor: "pointer",
};
