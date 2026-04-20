import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { resetDemo } from '../lib/api'

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
      className="screen route-fade"
      style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: '40px', maxWidth: '880px' }}
    >
      <p className="intro-wordmark">TripSync</p>

      <div style={{ display: 'grid', gap: '20px' }}>
        <h1 className="intro-headline">
          Your city,<br />
          <span style={{ color: 'var(--accent)' }}>curated for you.</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '18px', lineHeight: 1.65, maxWidth: '520px' }}>
          Drop a pin anywhere on the map. TripSync reads your interests and uses AI to surface
          the five most personally relevant places near you — with photos and a reason why you will love each one.
        </p>
      </div>

      <div style={{ display: 'grid', gap: '14px' }}>
        {[
          'Two-minute setup: interests, then day energy & how you like to explore',
          'Drop a pin anywhere — we resolve the city and pull real nearby spots when data allows',
          'Flip any card for a straight answer: what it is, and why it fits you — not generic filler',
        ].map((text) => (
          <div key={text} className="intro-feature">
            <div className="intro-feature-dot" />
            <span>{text}</span>
          </div>
        ))}
      </div>

      <div style={{ display: 'grid', gap: '10px', maxWidth: '400px' }}>
        <button type="button" className="btn-primary" onClick={handleStart} disabled={isResetting}>
          {isResetting ? 'Starting…' : 'Get Started →'}
        </button>
        <button
          type="button"
          className="btn-ghost"
          onClick={async () => {
            setIsResetting(true)
            await resetDemo()
            setIsResetting(false)
          }}
          disabled={isResetting}
        >
          Reset Demo Data
        </button>
      </div>
    </main>
  )
}

export default IntroScreen
