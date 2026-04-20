import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { clearSessionId, fetchSuggestions, getInterests, getSessionId, resetDemo } from '../lib/api'

const SF_CENTER = { lat: 37.7749, lng: -122.4194 }
const FALLBACK_IMAGE = 'https://placehold.co/800x500/10101e/00e5a0?text=TripSync'

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

function PlaceCard({ place, isFlipped, onToggle }) {
  const distance = Math.round(place.distance_m || 0)
  return (
    <div
      className={`card-flipper${isFlipped ? ' flipped' : ''}`}
      onClick={onToggle}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => e.key === 'Enter' && onToggle()}
    >
      <div className="card-inner">

        {/* ── FRONT ── */}
        <div className="card-front">
          <img
            src={place.photo_url || FALLBACK_IMAGE}
            alt={place.name}
            className="place-photo"
            onError={(e) => { e.currentTarget.src = FALLBACK_IMAGE }}
          />
          <div className="place-photo-overlay">
            <div className="place-overlay-content">
              <div className="place-meta">
                <span className="category-pill">{place.type}</span>
                <span className="distance-copy">{distance}m away</span>
              </div>
              <h2 className="place-name">{place.name}</h2>
            </div>
          </div>
        </div>

        {/* ── BACK ── */}
        <div className="card-back">
          <div className="card-back-header">
            <span className="category-pill">{place.type}</span>
            <span className="distance-copy">{distance}m away</span>
          </div>
          <h3 className="card-back-name">{place.name}</h3>
          {place.about
            ? <p className="about-copy">{place.about}</p>
            : null
          }
          <p className="why-copy">✦&nbsp;{place.why_youll_love_it}</p>
          <span className="flip-hint">tap to flip back</span>
        </div>

      </div>
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
  const [cityName, setCityName] = useState('')
  const [expandedId, setExpandedId] = useState(null)

  useEffect(() => {
    const storedSessionId = getSessionId()
    if (!storedSessionId || !storedSessionId.trim() || storedSessionId === 'missing-session') {
      navigate('/onboarding', { replace: true, state: { message: 'Session expired, please start again' } })
      return
    }
    setSessionId(storedSessionId)
    setInterestsState(getInterests())
    setSessionReady(true)
  }, [navigate])

  useEffect(() => {
    if (!sessionReady || !sessionId) return
    if (!window.L || mapRef.current || !mapContainerRef.current) return

    const map = window.L.map(mapContainerRef.current, { zoomControl: true }).setView(
      [SF_CENTER.lat, SF_CENTER.lng],
      14,
    )

    window.L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/">CARTO</a>',
      maxZoom: 19,
    }).addTo(map)

    const pinIcon = window.L.divIcon({
      className: '',
      html: `<div style="
        width: 18px; height: 18px;
        background: #00e5a0;
        border-radius: 50%;
        border: 2.5px solid #fff;
        box-shadow: 0 0 0 4px rgba(0,229,160,0.25), 0 2px 8px rgba(0,0,0,0.5);
      "></div>`,
      iconSize: [18, 18],
      iconAnchor: [9, 9],
    })

    const marker = window.L.marker([SF_CENTER.lat, SF_CENTER.lng], { icon: pinIcon }).addTo(map)

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
        const payload = await fetchSuggestions(sessionId, pinLocation)
        if (cancelled) return
        setPlaces(payload.places || [])
        setDataMode(payload.data_mode === 'live' ? 'live' : 'demo')
        setCityName(payload.city_name || '')
        setError('')
      } catch (err) {
        if (cancelled) return
        if (err?.status === 400 && String(err.message).includes('Session not found')) {
          clearSessionId()
          navigate('/onboarding', { replace: true, state: { message: 'Session expired, please start again' } })
          return
        }
        setError('Could not fetch curated places right now.')
      } finally {
        if (!cancelled) setIsLoading(false)
      }
    }

    loadPlaces()
    return () => { cancelled = true }
  }, [navigate, pinLocation, sessionId, sessionReady])

  if (!sessionReady) {
    return (
      <main className="screen discover-screen">
        <header className="discover-topbar">
          <span className="wordmark">Trip<span>Sync</span></span>
        </header>
      </main>
    )
  }

  return (
    <main className="screen discover-screen route-fade">
      <header className="discover-topbar">
        <span className="wordmark">Trip<span>Sync</span></span>

        <div className="topbar-actions">
          <button
            type="button"
            className="topbar-btn ghost"
            onClick={() => { clearSessionId(); navigate('/onboarding', { replace: true }) }}
          >
            Start Over
          </button>
          <button
            type="button"
            className="topbar-btn accent"
            onClick={async () => { await resetDemo(); navigate('/', { replace: true }) }}
          >
            Reset Demo
          </button>
        </div>

        <div className="interest-row">
          {interests.map((interest) => (
            <span key={interest} className="pill">{interest}</span>
          ))}
        </div>
      </header>

      <section className="discover-layout">
        <div className="map-column">
          <div ref={mapContainerRef} className="map-shell" />
          <p className="map-hint">
            {cityName
              ? <><span className="map-city">Pinned in <strong>{cityName}</strong> — </span>click the map to move your pin</>
              : 'Click anywhere on the map to move your location pin'}
          </p>
        </div>

        <div className="cards-column">
          <div className="cards-header">
            <span className="cards-title">
              {cityName ? `Near you in ${cityName}` : 'Nearby places'}
            </span>
            <div className={`data-mode-badge ${dataMode}`}>
              {dataMode === 'live' ? 'Live data' : 'Demo mode'}
            </div>
          </div>

          {isLoading ? <LoadingCards /> : null}
          {!isLoading && error ? (
            <div className="card" style={{ padding: '20px', color: 'var(--danger)' }}>{error}</div>
          ) : null}
          {!isLoading && !error ? (
            <div className="cards-list">
              {places.map((place) => (
                <PlaceCard
                  key={place.id || `${place.name}-${place.lat}`}
                  place={place}
                  isFlipped={expandedId === (place.id || place.name)}
                  onToggle={() => setExpandedId(
                    expandedId === (place.id || place.name) ? null : (place.id || place.name)
                  )}
                />
              ))}
            </div>
          ) : null}
        </div>
      </section>
    </main>
  )
}

export default DiscoverScreen
