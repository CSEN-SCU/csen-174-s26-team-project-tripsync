const SESSION_KEY = "orbit_kieran_auth_v1";

/**
 * Persists signed-in user id + email so Friends and sync survive refresh and backend restarts.
 * Password is never stored here.
 */
export function loadStoredSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const o = JSON.parse(raw);
    const userId = Number(o.userId);
    const email = typeof o.email === "string" ? o.email.trim() : "";
    if (!Number.isFinite(userId) || userId <= 0 || !email) return null;
    return { userId, email };
  } catch {
    return null;
  }
}

export function saveSession(userId, email) {
  localStorage.setItem(SESSION_KEY, JSON.stringify({ userId, email }));
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}
