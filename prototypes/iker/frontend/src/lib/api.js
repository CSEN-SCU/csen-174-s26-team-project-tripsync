// Thin client wrapper around the Orbit Together FastAPI backend.
// The Vite dev server proxies /api → http://127.0.0.1:8030 so we just use
// relative URLs here. Override with VITE_API_BASE_URL for deployed demos.

const BASE = (import.meta.env.VITE_API_BASE_URL || "").replace(/\/$/, "");

async function req(path, { method = "GET", body } = {}) {
  const url = `${BASE}${path}`;
  const opts = {
    method,
    headers: { "Content-Type": "application/json" },
  };
  if (body !== undefined) opts.body = JSON.stringify(body);
  const res = await fetch(url, opts);
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    const err = new Error(`${method} ${path} → ${res.status} ${res.statusText}`);
    err.status = res.status;
    err.body = text;
    throw err;
  }
  if (res.status === 204) return null;
  return res.json();
}

export const api = {
  health: () => req("/api/health"),
  createSession: ({ city, centerLat, centerLng } = {}) =>
    req("/api/sessions", {
      method: "POST",
      body: {
        city: city ?? "Lisbon",
        center_lat: centerLat ?? null,
        center_lng: centerLng ?? null,
      },
    }),
  getState: (code) => req(`/api/sessions/${code}/state`),
  join: (code, { name, avatar, interests, vibe, lat, lng }) =>
    req(`/api/sessions/${code}/join`, {
      method: "POST",
      body: {
        name,
        avatar: avatar || "🙂",
        interests: interests || [],
        vibe: vibe || "",
        lat: lat ?? null,
        lng: lng ?? null,
      },
    }),
  updateMember: (memberId, patch) =>
    req(`/api/members/${memberId}`, { method: "PATCH", body: patch }),
  recommend: (code) => req(`/api/sessions/${code}/recommend`, { method: "POST" }),
  react: ({ poiId, memberId, kind }) =>
    req(`/api/reactions`, {
      method: "POST",
      body: { poi_id: poiId, member_id: memberId, kind },
    }),
  pick: (code, poiId) =>
    req(`/api/sessions/${code}/pick`, { method: "POST", body: { poi_id: poiId } }),
  softReset: (code) => req(`/api/sessions/${code}/reset`, { method: "POST" }),
  nuke: (code) => req(`/api/sessions/${code}`, { method: "DELETE" }),
};
