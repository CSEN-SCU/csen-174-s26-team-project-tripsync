const SESSION_KEY = 'tripsync_session_id'

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
    throw new Error(payload.error || 'Request failed')
  }

  return response.json()
}

export const getSessionId = () => window.localStorage.getItem(SESSION_KEY)

export const setSessionId = (sessionId) => {
  window.localStorage.setItem(SESSION_KEY, sessionId)
}

export const clearSessionId = () => {
  window.localStorage.removeItem(SESSION_KEY)
}

export const resetDemo = async () => {
  await request('/api/reset', { method: 'POST' })
  clearSessionId()
}

export const createSession = async ({ interests, alertMode }) => {
  const payload = await request('/api/session', {
    method: 'POST',
    body: JSON.stringify({ interests, alertMode }),
  })
  setSessionId(payload.sessionId)
  return payload.sessionId
}

export const fetchSuggestions = async (sessionId, location) => {
  const params = new URLSearchParams({ sessionId })
  if (location?.lat && location?.lng) {
    params.set('lat', String(location.lat))
    params.set('lng', String(location.lng))
  }
  return request(`/api/suggestions?${params.toString()}`)
}

export const toggleSavedPlace = async ({ sessionId, place }) =>
  request('/api/saved/toggle', {
    method: 'POST',
    body: JSON.stringify({ sessionId, place }),
  })

export const fetchSavedPlaces = async (sessionId) =>
  request(`/api/saved?sessionId=${encodeURIComponent(sessionId)}`)
