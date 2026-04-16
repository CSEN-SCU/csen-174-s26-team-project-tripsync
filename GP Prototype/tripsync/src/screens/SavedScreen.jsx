import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

const SAVED = [
  {
    id: 1,
    name: 'Tartine Manufactory',
    type: 'Bakery',
    description: 'A legendary SF bakery - the country loaf alone is worth the detour.',
    savedAt: '2 mins ago',
  },
  {
    id: 2,
    name: 'Bi-Rite Creamery',
    type: 'Ice Cream',
    description: 'Salted caramel ice cream that people genuinely travel for.',
    savedAt: '8 mins ago',
  },
]

function SavedScreen() {
  const navigate = useNavigate()
  const [savedPlaces, setSavedPlaces] = useState(SAVED)
  const [removingIds, setRemovingIds] = useState([])

  const handleRemove = (id) => {
    setRemovingIds((current) => [...current, id])

    setTimeout(() => {
      setSavedPlaces((current) => current.filter((place) => place.id !== id))
      setRemovingIds((current) => current.filter((item) => item !== id))
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

      {savedPlaces.length > 0 ? (
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
      ) : (
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
      )}
    </main>
  )
}

export default SavedScreen
