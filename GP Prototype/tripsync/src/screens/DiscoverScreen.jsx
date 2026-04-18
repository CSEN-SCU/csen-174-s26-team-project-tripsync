import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { clearSessionId, fetchSuggestions, getInterests, getSessionId, resetDemo } from '../lib/api'

const SF_CENTER = { lat: 37.7749, lng: -122.4194 }

const fallbackImage = 'https://placehold.co/800x500/161616/00e5a0?text=TripSync'

function LoadingCards() {
  return (
    <div className="cards-list">
      {Array.from({ length: 5 }).map((_, idx) => (
        <article key={`skeleton-${idx}`} className="place-card skeleton-card">
          <div className="skeleton-image" />
          <div className="skeleton-line skeleton-title" />
          <div className="skeleton-line skeleton-pill" />
          <div className="skeleton-line skeleton-copy" />
          <div className="skeleton-line skeleton-copy short" />
        </article>
      ))}
    </div>
  )
}

function DiscoverScreen() {
  const navigate = useNavigate()
  const mapRef = useRef(null)
  const mapContainerRef = useRef(null)
  const markerRef = useRef(null)

  const [sessionId, setSessionId] = useState('')
  const [interests, setInterestsState] = useState([])
  const [sessionReady, setSessionReady] = useState(false)
  const [pinLocation, setPinLocation] = useState(SF_CENTER)
  const [places, setPlaces] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState('')
  const [dataMode, setDataMode] = useState('demo')

  useEffect(() => {
    const storedSessionId = getSessionId()
    if (!storedSessionId || !storedSessionId.trim() || storedSessionId === 'missing-session') {
      navigate('/onboarding', {
        replace: true,
        state: { message: 'Session expired, please start again' },
      })
      return
    }
    setSessionId(storedSessionId)
    setInterestsState(getInterests())
    setSessionReady(true)
  }, [navigate])

  useEffect(() => {
    if (!sessionReady || !sessionId) return

    if (!window.L || mapRef.current || !mapContainerRef.current) return

    const map = window.L.map(mapContainerRef.current).setView([SF_CENTER.lat, SF_CENTER.lng], 14)
    window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(map)

    const marker = window.L.marker([SF_CENTER.lat, SF_CENTER.lng]).addTo(map)

    map.on('click', (event) => {
      const nextLocation = { lat: event.latlng.lat, lng: event.latlng.lng }
      marker.setLatLng(event.latlng)
      setPinLocation(nextLocation)
    })

    mapRef.current = map
    markerRef.current = marker
  }, [sessionReady, sessionId])

  useEffect(() => {
    if (!sessionReady || !sessionId) return
    let cancelled = false

    const loadPlaces = async () => {
      try {
        setIsLoading(true)
        console.log('Session ID from localStorage:', sessionId)
        const payload = await fetchSuggestions(sessionId, pinLocation)
        if (cancelled) return
        setPlaces(payload.places || [])
        setDataMode(payload.data_mode === 'live' ? 'live' : 'demo')
        setError('')
      } catch (error) {
        if (cancelled) return
        if (error?.status === 400 && String(error.message).includes('Session not found')) {
          clearSessionId()
          navigate('/onboarding', {
            replace: true,
            state: { message: 'Session expired, please start again' },
          })
          return
        }
        setError('Could not fetch curated places right now.')
      } finally {
        if (!cancelled) setIsLoading(false)
      }
    }

    loadPlaces()
    return () => {
      cancelled = true
    }
  }, [navigate, pinLocation, sessionId, sessionReady])

  if (!sessionReady) {
    return (
      <main className="screen discover-screen">
        <header className="discover-topbar">
          <h1>TripSync</h1>
        </header>
      </main>
    )
  }

  return (
    <main className="screen discover-screen">
      <header className="discover-topbar">
        <h1>TripSync</h1>
        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          <button
            type="button"
            className="btn-ghost"
            style={{ width: 'auto', height: '36px', padding: '0 14px', fontSize: '13px' }}
            onClick={() => {
              clearSessionId()
              navigate('/onboarding', { replace: true })
            }}
          >
            Start Over
          </button>
          <button
            type="button"
            className="btn-primary"
            style={{ width: 'auto', height: '36px', padding: '0 14px', fontSize: '13px' }}
            onClick={async () => {
              await resetDemo()
              navigate('/', { replace: true })
            }}
          >
            Reset Demo
          </button>
        </div>
        <div className="interest-row">
          {interests.map((interest) => (
            <span key={interest} className="pill">
              {interest}
            </span>
          ))}
        </div>
      </header>

      <section className="discover-layout">
        <div className="map-column">
          <div ref={mapContainerRef} className="map-shell" />
          <p className="map-hint">Click anywhere on the map to set your location pin.</p>
        </div>
        <div className="cards-column">
          <div className={`data-mode-badge ${dataMode === 'live' ? 'live' : 'demo'}`}>
            {dataMode === 'live' ? 'Live data' : 'Demo mode'}
          </div>
          {isLoading ? <LoadingCards /> : null}
          {!isLoading && error ? <div className="card error-card">{error}</div> : null}
          {!isLoading && !error ? (
            <div className="cards-list">
              {places.map((place) => (
                <article key={place.id || `${place.name}-${place.lat}-${place.lon}`} className="place-card">
                  <img
                    src={place.photo_url || fallbackImage}
                    alt={place.name}
                    className="place-photo"
                    onError={(event) => {
                      event.currentTarget.src = fallbackImage
                    }}
                  />
                  <div className="place-body">
                    <h2>{place.name}</h2>
                    <div className="place-meta">
                      <span className="category-pill">{place.type}</span>
                      <span className="distance-copy">{Math.round(place.distance_m || 0)}m away</span>
                    </div>
                    <p className="why-copy">{place.why_youll_love_it}</p>
                  </div>
                </article>
              ))}
            </div>
          ) : null}
        </div>
      </section>
    </main>
  )
}

export default DiscoverScreen
