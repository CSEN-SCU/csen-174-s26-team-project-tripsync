import { useNavigate } from 'react-router-dom'
import { resetDemo } from '../lib/api'
import { useState } from 'react'

function IntroScreen() {
  const navigate = useNavigate()
  const [isResetting, setIsResetting] = useState(false)

  const handleStart = async () => {
    try {
      setIsResetting(true)
      await resetDemo()
      navigate('/onboarding')
    } finally {
      setIsResetting(false)
    }
  }

  return (
    <main
      className="screen"
      style={{
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'center',
        gap: '26px',
        maxWidth: '960px',
      }}
    >
      <p style={{ color: 'var(--accent)', letterSpacing: '0.24em', fontWeight: 700, fontSize: '12px' }}>
        TRIPSYNC
      </p>
      <section className="card" style={{ display: 'grid', gap: '18px', padding: '28px' }}>
        <h1 style={{ fontSize: '52px', fontWeight: 700, lineHeight: 1.02 }}>TripSync</h1>
        <h2 style={{ fontSize: '24px', fontWeight: 600, color: 'var(--accent)' }}>
          Your city, curated for you as you walk
        </h2>
        <p style={{ color: 'var(--text-secondary)', fontSize: '17px', lineHeight: 1.7 }}>
          TripSync is for gallery walk demo visitors who want instant local recommendations without typing searches.
          It solves the “where do I go now?” problem by combining onboarding preferences, a map pin, and AI curation.
        </p>
        <p style={{ color: 'var(--text-secondary)', fontSize: '15px', lineHeight: 1.7 }}>
          How to use: tap Get Started, choose at least 3 interests, set your location pin on the map, and review
          curated places with photos and personalized reasons.
        </p>
      </section>
      <section style={{ display: 'grid', gap: '10px', maxWidth: '560px' }}>
        <button type="button" className="btn-primary" onClick={handleStart} disabled={isResetting}>
          {isResetting ? 'Resetting demo...' : 'Get Started'}
        </button>
        <button
          type="button"
          className="btn-ghost"
          onClick={async () => {
            setIsResetting(true)
            await resetDemo()
            setIsResetting(false)
          }}
        >
          Reset Demo Data
        </button>
      </section>
    </main>
  )
}

export default IntroScreen
