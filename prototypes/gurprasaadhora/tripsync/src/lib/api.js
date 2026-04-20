const SESSION_KEY = 'tripsync_session_id'
const INTERESTS_KEY = 'tripsync_interests'
const PROFILE_KEY = 'tripsync_profile'

const request = async (path, options = {}) => {
  const response = await fetch(path, {
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
    ...options,
  })

  if (!response.ok) {
    const payload = await response.json().catch(() => ({}))
    const error = new Error(payload.error || 'Request failed')
    error.status = response.status
    error.payload = payload
    throw error
  }

  return response.json()
}

export const getSessionId = () => window.localStorage.getItem(SESSION_KEY)

export const setSessionId = (sessionId) => {
  window.localStorage.setItem(SESSION_KEY, sessionId)
}

export const getProfile = () => {
  try {
    const raw = window.localStorage.getItem(PROFILE_KEY)
    if (!raw) return null
    const p = JSON.parse(raw)
    if (!p || typeof p !== 'object' || !Array.isArray(p.interests)) return null
    return p
  } catch (_error) {
    return null
  }
}

export const setProfile = (profile) => {
  window.localStorage.setItem(PROFILE_KEY, JSON.stringify(profile))
}

export const clearSessionId = () => {
  window.localStorage.removeItem(SESSION_KEY)
  window.localStorage.removeItem(INTERESTS_KEY)
  window.localStorage.removeItem(PROFILE_KEY)
}

export const setInterests = (interests) => {
  const prev = getProfile() || {}
  setProfile({
    ...prev,
    v: 1,
    interests,
    energy: prev.energy || 'balanced',
    pace: prev.pace || 'mix',
    avoid_chains: prev.avoid_chains !== false,
    note: prev.note || '',
  })
}

export const getInterests = () => {
  const p = getProfile()
  if (p?.interests?.length && Array.isArray(p.interests)) return p.interests
  try {
    const raw = window.localStorage.getItem(INTERESTS_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed.filter(Boolean) : []
  } catch (_error) {
    return []
  }
}

export const resetDemo = async () => {
  await request('/api/reset')
  clearSessionId()
}

export const onboard = async ({ sessionId, profile }) =>
  request('/api/onboard', {
    method: 'POST',
    body: JSON.stringify({ session_id: sessionId, profile }),
  })

export const fetchSuggestions = async (sessionId, location) => {
  const params = new URLSearchParams({ session_id: sessionId })
  const la = Number(location?.lat)
  const lo = Number(location?.lng)
  if (Number.isFinite(la) && Number.isFinite(lo)) {
    params.set('lat', String(la))
    params.set('lng', String(lo))
  }
  const requestPath = `/api/discover?${params.toString()}`
  console.log('Discover request path:', requestPath)
  return request(requestPath)
}
