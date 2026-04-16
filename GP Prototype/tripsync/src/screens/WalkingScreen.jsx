import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'

const FAKE_PLACES = [
  {
    id: 1,
    name: 'Tartine Manufactory',
    type: 'Bakery',
    distance: 80,
    why: 'A legendary SF bakery - the country loaf alone is worth the detour.',
    saved: false,
  },
  {
    id: 2,
    name: 'Adobe Books',
    type: 'Bookshop',
    distance: 140,
    why: 'Dusty, chaotic, and completely wonderful. Local institution.',
    saved: false,
  },
  {
    id: 3,
    name: 'Dolores Park',
    type: 'Park',
    distance: 210,
    why: 'The social heart of the Mission. Great city views.',
    saved: false,
  },
  {
    id: 4,
    name: 'Bi-Rite Creamery',
    type: 'Ice Cream',
    distance: 260,
    why: 'Salted caramel ice cream that people genuinely travel for.',
    saved: false,
  },
  {
    id: 5,
    name: '996 Mural',
    type: 'Street Art',
    distance: 310,
    why: 'One of the most photographed murals in the city.',
    saved: false,
  },
]

function WalkingScreen() {
  const navigate = useNavigate()
  const [places, setPlaces] = useState(FAKE_PLACES)
  const [isMuted, setIsMuted] = useState(false)
  const [showToast, setShowToast] = useState(false)
  const [showHero, setShowHero] = useState(false)
  const [poppingBookmarkIds, setPoppingBookmarkIds] = useState([])

  const heroPlace = places[0]
  const nearbyPlaces = useMemo(() => places.slice(1, 5), [places])

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

  const toggleSaved = (placeId) => {
    setPoppingBookmarkIds((current) => [...new Set([...current, placeId])])
    setPlaces((current) =>
      current.map((place) => (place.id === placeId ? { ...place, saved: !place.saved } : place)),
    )

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
            onClick={() => setIsMuted((current) => !current)}
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
          onClick={() => toggleSaved(heroPlace.id)}
          aria-label={heroPlace.saved ? 'Remove from saved places' : 'Save place'}
          className={poppingBookmarkIds.includes(heroPlace.id) ? 'bookmark-pop' : ''}
          style={{
            position: 'absolute',
            top: '14px',
            right: '14px',
            width: '36px',
            height: '36px',
            borderRadius: '10px',
            border: '1px solid var(--border-color)',
            background: 'var(--bg-primary)',
            color: heroPlace.saved ? 'var(--accent)' : 'var(--text-secondary)',
            cursor: 'pointer',
            fontSize: '18px',
          }}
        >
          {heroPlace.saved ? '★' : '☆'}
        </button>

        <h1 style={{ fontSize: '28px', fontWeight: 700, lineHeight: 1.15, marginBottom: '14px', paddingRight: '44px' }}>
          {heroPlace.name}
        </h1>

        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '14px' }}>
          <span className="pill">{heroPlace.type}</span>
          <span className="pill" style={{ color: 'var(--accent)', borderColor: 'var(--accent)' }}>
            {heroPlace.distance}m away
          </span>
        </div>

        <p style={{ color: 'var(--text-secondary)', fontSize: '14px', marginBottom: '6px' }}>Why you&apos;ll love it</p>
        <p style={{ color: 'var(--text-primary)', fontSize: '16px', lineHeight: 1.55 }}>{heroPlace.why}</p>
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
        <button type="button" className="btn-primary" onClick={() => toggleSaved(heroPlace.id)}>
          Save this place
        </button>
        <button type="button" className="btn-ghost" onClick={() => navigate('/saved')}>
          Saved Places →
        </button>
      </section>

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
