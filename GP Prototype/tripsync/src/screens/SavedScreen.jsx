import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fetchSavedPlaces, getSessionId, toggleSavedPlace } from '../lib/api'

function SavedScreen() {
  const navigate = useNavigate()
  const [savedPlaces, setSavedPlaces] = useState([])
  const [removingIds, setRemovingIds] = useState([])
  const [loadError, setLoadError] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const sessionId = getSessionId()

  useEffect(() => {
    if (!sessionId) {
      navigate('/onboarding', { replace: true })
      return
    }

    let cancelled = false

    const loadSaved = async () => {
      try {
        const payload = await fetchSavedPlaces(sessionId)
        if (cancelled) return
        setSavedPlaces(payload.places)
        setLoadError('')
      } catch (error) {
        if (cancelled) return
        setLoadError('Could not load saved places.')
      } finally {
        if (!cancelled) setIsLoading(false)
      }
    }

    loadSaved()

    return () => {
      cancelled = true
    }
  }, [navigate, sessionId])

  const handleRemove = (id) => {
    setRemovingIds((current) => [...current, id])

    setTimeout(async () => {
      setSavedPlaces((current) => current.filter((place) => place.id !== id))
      setRemovingIds((current) => current.filter((item) => item !== id))
      if (sessionId) {
        try {
          await toggleSavedPlace({ sessionId, place: { id } })
        } catch (error) {
          setLoadError('Could not update saved place state.')
        }
      }
    }, 260)
  }

  return (
    <main className="screen" style={{ display: 'flex', flexDirection: 'column', minHeight: '100vh', gap: '18px' }}>
      <header style={{ display: 'grid', gridTemplateColumns: '40px 1fr 40px', alignItems: 'center', gap: '8px' }}>
        <button
          type="button"
          onClick={() => navigate(-1)}
          aria-label="Go back"
          style={{
            width: '40px',
            height: '40px',
            border: '1px solid var(--border-color)',
            borderRadius: '10px',
            background: 'transparent',
            color: 'var(--text-primary)',
            fontSize: '20px',
            cursor: 'pointer',
          }}
        >
          ←
        </button>

        <h1 style={{ textAlign: 'center', fontSize: '22px', fontWeight: 700 }}>Saved Places</h1>

        <span
          aria-label={`${savedPlaces.length} saved places`}
          style={{
            justifySelf: 'end',
            minWidth: '32px',
            height: '32px',
            borderRadius: '999px',
            border: '1px solid var(--border-color)',
            display: 'inline-flex',
            justifyContent: 'center',
            alignItems: 'center',
            fontSize: '13px',
            fontWeight: 700,
            color: 'var(--text-primary)',
            background: 'var(--bg-card)',
          }}
        >
          {savedPlaces.length}
        </span>
      </header>

      {isLoading ? (
        <section className="card">
          <p style={{ color: 'var(--text-secondary)' }}>Loading saved places...</p>
        </section>
      ) : null}
      {loadError ? (
        <section className="card" style={{ borderColor: '#754545' }}>
          <p style={{ color: '#ff9f9f' }}>{loadError}</p>
        </section>
      ) : null}

      {!isLoading && savedPlaces.length > 0 ? (
        <section style={{ display: 'grid', gap: '12px' }}>
          {savedPlaces.map((place) => {
            const isRemoving = removingIds.includes(place.id)

            return (
              <article
                key={place.id}
                className="card"
                style={{
                  display: 'grid',
                  gap: '10px',
                  opacity: isRemoving ? 0 : 1,
                  transform: isRemoving ? 'translateY(-4px)' : 'translateY(0)',
                  transition: 'opacity 260ms ease, transform 260ms ease',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px' }}>
                  <div style={{ display: 'grid', gap: '8px' }}>
                    <h2 style={{ fontSize: '19px', fontWeight: 700, lineHeight: 1.2 }}>{place.name}</h2>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span className="pill">{place.type}</span>
                      <span style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>{place.savedAt}</span>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => handleRemove(place.id)}
                    aria-label={`Remove ${place.name}`}
                    style={{
                      width: '34px',
                      height: '34px',
                      borderRadius: '10px',
                      border: '1px solid var(--border-color)',
                      background: 'transparent',
                      color: 'var(--text-secondary)',
                      cursor: 'pointer',
                      fontSize: '16px',
                    }}
                  >
                    🗑
                  </button>
                </div>

                <p style={{ color: 'var(--text-secondary)', fontSize: '14px', lineHeight: 1.55 }}>{place.description}</p>
              </article>
            )
          })}
        </section>
      ) : null}

      {!isLoading && savedPlaces.length === 0 ? (
        <section
          className="card"
          style={{
            marginTop: '8vh',
            textAlign: 'center',
            display: 'grid',
            gap: '12px',
            justifyItems: 'center',
            paddingTop: '28px',
            paddingBottom: '24px',
          }}
        >
          <p style={{ color: 'var(--accent)', fontSize: '42px', lineHeight: 1 }}>✦</p>
          <h2 style={{ fontSize: '24px', fontWeight: 700 }}>Nothing saved yet</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '15px', maxWidth: '44ch', lineHeight: 1.6 }}>
            Head out and explore - we&apos;ll help you find things worth keeping.
          </p>
          <button type="button" className="btn-primary" onClick={() => navigate('/walking')}>
            Back to Walk
          </button>
        </section>
      ) : null}
    </main>
  )
}

export default SavedScreen
