const SESSION_KEY = 'tripsync_session_id'
const INTERESTS_KEY = 'tripsync_interests'

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

export const clearSessionId = () => {
  window.localStorage.removeItem(SESSION_KEY)
  window.localStorage.removeItem(INTERESTS_KEY)
}

export const setInterests = (interests) => {
  window.localStorage.setItem(INTERESTS_KEY, JSON.stringify(interests))
}

export const getInterests = () => {
  try {
    const raw = window.localStorage.getItem(INTERESTS_KEY)
    return raw ? JSON.parse(raw) : []
  } catch (_error) {
    return []
  }
}

export const resetDemo = async () => {
  await request('/api/reset')
  clearSessionId()
}

export const onboard = async ({ sessionId, interests }) =>
  request('/api/onboard', {
    method: 'POST',
    body: JSON.stringify({ session_id: sessionId, interests }),
  })

export const fetchSuggestions = async (sessionId, location) => {
  const params = new URLSearchParams({ session_id: sessionId })
  if (location?.lat && location?.lng) {
    params.set('lat', String(location.lat))
    params.set('lng', String(location.lng))
  }
  const requestPath = `/api/discover?${params.toString()}`
  console.log('Discover request path:', requestPath)
  return request(requestPath)
}
