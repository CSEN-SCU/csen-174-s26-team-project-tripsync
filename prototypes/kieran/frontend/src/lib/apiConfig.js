/**
 * Returns the API root for fetch(). Defaults to the local FastAPI instance so sign-up
 * never hits the static server (which returns 404 for /api/...).
 * Set VITE_API_URL in frontend/.env when the API is not on 127.0.0.1:8010 (e.g. production).
 */
export function getApiBase() {
  const env = import.meta.env.VITE_API_URL?.trim();
  if (env) return env.replace(/\/$/, "");
  return "http://127.0.0.1:8010/api";
}
