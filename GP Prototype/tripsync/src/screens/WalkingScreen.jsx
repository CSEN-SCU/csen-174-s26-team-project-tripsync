import { useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { fetchSuggestions, getSessionId, toggleSavedPlace } from '../lib/api'

const getMapPosition = (distanceMeters, bearingDeg) => {
  const radius = Math.min(distanceMeters / 8, 38)
  const radians = ((bearingDeg - 90) * Math.PI) / 180
  return {
    x: Math.round((50 + Math.cos(radians) * radius) * 10) / 10,
    y: Math.round((50 + Math.sin(radians) * radius) * 10) / 10,
  }
}

function WalkingScreen() {
  const location = useLocation()
  const navigate = useNavigate()
  const [places, setPlaces] = useState([])
  const sessionId = location.state?.sessionId || getSessionId()
  const [alertMode, setAlertMode] = useState('voice-visual')
  const [isMuted, setIsMuted] = useState(false)
  const [showToast, setShowToast] = useState(false)
  const [showHero, setShowHero] = useState(false)
  const [poppingBookmarkIds, setPoppingBookmarkIds] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [userLocation, setUserLocation] = useState(null)
  const [locationError, setLocationError] = useState('')
  const [isLocating, setIsLocating] = useState(true)
  const [voiceError, setVoiceError] = useState('')

  const heroPlace = places[0] || null
  const placeView = useMemo(() => places, [places])

  const activeHeroPlace = placeView[0] || heroPlace
  const nearbyPlaces = useMemo(() => placeView.slice(1, 5), [placeView])
  const mapLegendPlaces = useMemo(() => placeView.slice(0, 3), [placeView])

  useEffect(() => {
    const frame = requestAnimationFrame(() => {
      setShowHero(true)
    })

    const toastStart = setTimeout(() => {
      setShowToast(true)
    }, 5000)

    const toastEnd = setTimeout(() => {
      setShowToast(false)
    }, 7600)

    return () => {
      cancelAnimationFrame(frame)
      clearTimeout(toastStart)
      clearTimeout(toastEnd)
    }
  }, [])

  useEffect(() => {
    if (!navigator.geolocation) {
      setLocationError('Geolocation is not supported in this browser.')
      setIsLocating(false)
      return
    }

    const watchId = navigator.geolocation.watchPosition(
      (position) => {
        setUserLocation({
          lat: position.coords.latitude,
          lng: position.coords.longitude,
        })
        setLocationError('')
        setIsLocating(false)
      },
      (error) => {
        setIsLocating(false)
        if (error.code === 1) {
          setLocationError('Location access denied. Allow location to personalize nearby places.')
        } else {
          setLocationError('Unable to get live location. Showing approximate nearby data.')
        }
      },
      {
        enableHighAccuracy: true,
        maximumAge: 10000,
        timeout: 8000,
      },
    )

    return () => {
      navigator.geolocation.clearWatch(watchId)
    }
  }, [])

  useEffect(() => {
    if (!sessionId) {
      navigate('/onboarding', { replace: true })
      return
    }

    let isCancelled = false

    const loadSuggestions = async () => {
      try {
        setIsLoading(true)
        const payload = await fetchSuggestions(sessionId, userLocation || undefined)
        if (isCancelled) return
        const normalized = payload.places.map((place) => {
          const distance = Math.round(Number(place.distance) || 0)
          const bearing = Number.isFinite(Number(place.bearing)) ? Number(place.bearing) : 0
          const map = place.map || getMapPosition(distance, bearing)
          return {
            ...place,
            distance,
            map,
          }
        })
        setPlaces(normalized)
        setAlertMode(payload.session?.alertMode || 'voice-visual')
        setLoadError('')
      } catch (error) {
        if (isCancelled) return
        setLoadError('Could not load nearby places. Start a new session from onboarding.')
      } finally {
        if (!isCancelled) setIsLoading(false)
      }
    }

    loadSuggestions()

    return () => {
      isCancelled = true
    }
  }, [navigate, sessionId, userLocation])

  useEffect(() => {
    if (!activeHeroPlace || isMuted || alertMode === 'visual-only') return

    if (!window.speechSynthesis || typeof window.SpeechSynthesisUtterance !== 'function') {
      setVoiceError('Voice alerts are unavailable in this browser.')
      return
    }

    setVoiceError('')
    const utterance = new window.SpeechSynthesisUtterance(
      `${activeHeroPlace.name}. ${activeHeroPlace.why}`,
    )
    utterance.rate = 1
    utterance.pitch = 1

    window.speechSynthesis.cancel()
    window.speechSynthesis.speak(utterance)
  }, [activeHeroPlace, alertMode, isMuted])

  const toggleSaved = async (placeId) => {
    if (!sessionId) return
    setPoppingBookmarkIds((current) => [...new Set([...current, placeId])])

    const nextPlaces = places.map((place) =>
      place.id === placeId ? { ...place, saved: !place.saved } : place,
    )
    setPlaces(nextPlaces)

    try {
      const placeToSave = nextPlaces.find((place) => place.id === placeId)
      await toggleSavedPlace({ sessionId, place: placeToSave })
    } catch (error) {
      setPlaces(places)
    }

    setTimeout(() => {
      setPoppingBookmarkIds((current) => current.filter((id) => id !== placeId))
    }, 230)
  }

  return (
    <main className="screen" style={{ display: 'flex', flexDirection: 'column', gap: '16px', paddingBottom: '28px' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <p style={{ fontSize: '22px', fontWeight: 700, letterSpacing: '0.02em' }}>TripSync</p>

        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span
              className="live-dot"
              aria-hidden="true"
              style={{
                width: '8px',
                height: '8px',
                borderRadius: '999px',
                backgroundColor: 'var(--accent)',
              }}
            />
            <span style={{ color: 'var(--text-secondary)', fontSize: '13px', fontWeight: 600 }}>Live</span>
          </div>

          <button
            type="button"
            onClick={() =>
              setIsMuted((current) => {
                if (!current && window.speechSynthesis) {
                  window.speechSynthesis.cancel()
                }
                return !current
              })
            }
            aria-label={isMuted ? 'Unmute voice alerts' : 'Mute voice alerts'}
            style={{
              borderRadius: '10px',
              border: '1px solid var(--border-color)',
              background: 'var(--bg-card)',
              color: 'var(--text-primary)',
              width: '36px',
              height: '36px',
              cursor: 'pointer',
              fontSize: '17px',
            }}
          >
            {isMuted ? '🔇' : '🔊'}
          </button>
        </div>
      </header>
      <p style={{ color: 'var(--text-secondary)', fontSize: '12px', marginTop: '-8px' }}>
        {alertMode === 'visual-only' ? 'Visual mode enabled from onboarding.' : isMuted ? 'Voice alerts muted.' : 'Voice alerts live.'}
      </p>
      {voiceError ? <p style={{ color: '#ffb6b6', fontSize: '12px' }}>{voiceError}</p> : null}

      {isLoading ? (
        <section className="card">
          <p style={{ color: 'var(--text-secondary)' }}>Loading your walk feed...</p>
        </section>
      ) : null}

      {loadError ? (
        <section className="card" style={{ borderColor: '#754545' }}>
          <p style={{ color: '#ff9f9f' }}>{loadError}</p>
        </section>
      ) : null}

      {activeHeroPlace ? (
        <>
      <section
        className="card"
        style={{
          borderLeft: '3px solid var(--accent)',
          paddingLeft: '18px',
          position: 'relative',
          opacity: showHero ? 1 : 0,
          transform: showHero ? 'translateY(0px)' : 'translateY(12px)',
          transition: 'opacity 480ms ease, transform 480ms ease',
        }}
      >
        <button
          type="button"
          onClick={() => toggleSaved(activeHeroPlace.id)}
          aria-label={activeHeroPlace.saved ? 'Remove from saved places' : 'Save place'}
          className={poppingBookmarkIds.includes(activeHeroPlace.id) ? 'bookmark-pop' : ''}
          style={{
            position: 'absolute',
            top: '14px',
            right: '14px',
            width: '36px',
            height: '36px',
            borderRadius: '10px',
            border: '1px solid var(--border-color)',
            background: 'var(--bg-primary)',
            color: activeHeroPlace.saved ? 'var(--accent)' : 'var(--text-secondary)',
            cursor: 'pointer',
            fontSize: '18px',
          }}
        >
          {activeHeroPlace.saved ? '★' : '☆'}
        </button>

        <h1 style={{ fontSize: '28px', fontWeight: 700, lineHeight: 1.15, marginBottom: '14px', paddingRight: '44px' }}>
          {activeHeroPlace.name}
        </h1>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '14px' }}>
          <span className="pill">{activeHeroPlace.type}</span>
          <span className="pill" style={{ color: 'var(--accent)', borderColor: 'var(--accent)' }}>
            {activeHeroPlace.distance}m away
          </span>
        </div>

        <p style={{ color: 'var(--text-secondary)', fontSize: '14px', marginBottom: '6px' }}>Why you&apos;ll love it</p>
        <p style={{ color: 'var(--text-primary)', fontSize: '16px', lineHeight: 1.55 }}>{activeHeroPlace.why}</p>
      </section>

      <section className="card" style={{ padding: '16px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
          <p style={{ color: 'var(--text-primary)', fontSize: '14px', fontWeight: 700 }}>
            Live location map
          </p>
          <span
            className="pill"
            style={{
              color: userLocation ? 'var(--accent)' : 'var(--text-secondary)',
              borderColor: userLocation ? 'var(--accent)' : 'var(--border-color)',
            }}
          >
            {userLocation ? 'GPS on' : 'GPS pending'}
          </span>
        </div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '12px', marginBottom: '10px' }}>
          You are centered. Numbered dots are the closest suggestions around your live location.
        </p>
        {isLocating ? (
          <p style={{ color: 'var(--text-secondary)', fontSize: '12px', marginBottom: '8px' }}>Finding your live location...</p>
        ) : null}
        {locationError ? (
          <p style={{ color: '#ffb6b6', fontSize: '12px', marginBottom: '8px' }}>{locationError}</p>
        ) : null}
        <div
          style={{
            borderRadius: '14px',
            border: '1px solid var(--border-color)',
            background: 'var(--bg-primary)',
            height: '220px',
            position: 'relative',
            overflow: 'hidden',
          }}
        >
          {userLocation ? (
            <iframe
              title="Google Maps live location"
              src={`https://maps.google.com/maps?q=${encodeURIComponent(
                `${userLocation.lat},${userLocation.lng}`,
              )}&z=16&output=embed`}
              style={{ width: '100%', height: '100%', border: 0 }}
              loading="lazy"
              referrerPolicy="no-referrer-when-downgrade"
            />
          ) : null}
        </div>
        <div style={{ display: 'grid', gap: '6px', marginTop: '10px' }}>
          {mapLegendPlaces.map((place, index) => (
            <p key={`legend-${place.id}`} style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
              <span style={{ color: 'var(--text-primary)', fontWeight: 700 }}>{index + 1}. {place.name}</span>{' '}
              - {place.distance}m -{' '}
              <a
                href={`https://www.google.com/maps/dir/?api=1&destination=${place.coordinates.lat},${place.coordinates.lng}&travelmode=walking`}
                target="_blank"
                rel="noreferrer"
                style={{ color: 'var(--accent)', textDecoration: 'none' }}
              >
                open route
              </a>
            </p>
          ))}
        </div>
      </section>

      <section style={{ display: 'grid', gap: '10px' }}>
        <p style={{ color: 'var(--text-secondary)', fontSize: '14px', fontWeight: 600 }}>Also nearby</p>
        <div className="nearby-scroll" style={{ display: 'flex', gap: '10px', overflowX: 'auto', paddingBottom: '6px' }}>
          {nearbyPlaces.map((place) => (
            <article
              key={place.id}
              className="card"
              style={{
                minWidth: '210px',
                flex: '0 0 auto',
                display: 'grid',
                gap: '10px',
                padding: '14px',
              }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '10px' }}>
                <h3 style={{ fontSize: '16px', fontWeight: 600, lineHeight: 1.3 }}>{place.name}</h3>
                <button
                  type="button"
                  onClick={() => toggleSaved(place.id)}
                  aria-label={place.saved ? `Unsave ${place.name}` : `Save ${place.name}`}
                  className={poppingBookmarkIds.includes(place.id) ? 'bookmark-pop' : ''}
                  style={{
                    border: 'none',
                    background: 'transparent',
                    color: place.saved ? 'var(--accent)' : 'var(--text-secondary)',
                    cursor: 'pointer',
                    fontSize: '18px',
                    lineHeight: 1,
                  }}
                >
                  {place.saved ? '★' : '☆'}
                </button>
              </div>

              <div style={{ display: 'flex', gap: '8px' }}>
                <span className="pill">{place.type}</span>
                <span className="pill">{place.distance}m</span>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section style={{ marginTop: 'auto', display: 'grid', gap: '10px' }}>
        <button type="button" className="btn-primary" onClick={() => toggleSaved(activeHeroPlace.id)}>
          {activeHeroPlace.saved ? 'Remove saved place' : 'Save this place'}
        </button>
        <button type="button" className="btn-ghost" onClick={() => navigate('/saved')}>
          Saved Places →
        </button>
      </section>
      </>
      ) : null}

      {showToast && (
        <div
          role="status"
          style={{
            position: 'fixed',
            left: '24px',
            right: '24px',
            bottom: '94px',
            border: '1px solid var(--accent)',
            background: 'rgba(0, 229, 160, 0.14)',
            color: 'var(--text-primary)',
            borderRadius: '12px',
            padding: '12px 14px',
            fontSize: '14px',
            backdropFilter: 'blur(4px)',
          }}
        >
          New suggestion nearby. Refreshing your walk feed...
        </div>
      )}
    </main>
  )
}

export default WalkingScreen
