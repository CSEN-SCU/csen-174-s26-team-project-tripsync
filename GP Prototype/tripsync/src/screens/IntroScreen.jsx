import { useNavigate } from 'react-router-dom'
import { useState } from 'react'
import { resetDemo } from '../lib/api'

const features = [
  {
    title: 'Who it is for',
    body: 'People exploring a city on foot who want local-quality suggestions without staring at maps.',
  },
  {
    title: 'Problem it solves',
    body: 'Tourist apps make you search constantly. TripSync listens to your preferences and brings places to you.',
  },
  {
    title: 'How to use it',
    body: 'Pick interests, start walking, then save spots you want to revisit. Reset between demo visitors.',
  },
]

function IntroScreen() {
  const navigate = useNavigate()
  const [isResetting, setIsResetting] = useState(false)

  const goToOnboarding = () => {
    navigate('/onboarding')
  }

  const handleResetDemo = async () => {
    try {
      setIsResetting(true)
      await resetDemo()
      navigate('/', { replace: true })
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
        justifyContent: 'space-between',
        gap: '32px',
      }}
    >
      <header>
        <p
          style={{
            color: 'var(--accent)',
            fontSize: '12px',
            fontWeight: 700,
            letterSpacing: '0.24em',
          }}
        >
          TRIPSYNC
        </p>
      </header>

      <section style={{ maxWidth: '680px' }}>
        <h1 style={{ fontSize: '48px', fontWeight: 700, lineHeight: 1.05, marginBottom: '16px' }}>
          TripSync: local suggestions while you walk.
        </h1>
        <p
          style={{
            color: 'var(--text-secondary)',
            fontSize: '18px',
            lineHeight: 1.6,
            marginBottom: '28px',
            maxWidth: '60ch',
          }}
        >
          A location-aware travel companion that recommends nearby places with voice and visual prompts, so a
          first-time user can explore instantly with zero setup confusion.
        </p>

        <div style={{ display: 'grid', gap: '12px' }}>
          {features.map((feature) => (
            <div key={feature.title} style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
              <span
                aria-hidden="true"
                style={{
                  color: 'var(--accent)',
                  fontSize: '14px',
                  lineHeight: 1,
                  marginTop: '7px',
                }}
              >
                ●
              </span>
              <div>
                <p style={{ fontSize: '15px', fontWeight: 700, marginBottom: '4px' }}>{feature.title}</p>
                <p style={{ fontSize: '15px', color: 'var(--text-secondary)', lineHeight: 1.5 }}>{feature.body}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section style={{ display: 'grid', gap: '10px', width: '100%', maxWidth: '560px' }}>
        <button type="button" className="btn-primary" onClick={goToOnboarding}>
          Start Exploring
        </button>
        <button type="button" className="btn-ghost" onClick={handleResetDemo} disabled={isResetting}>
          {isResetting ? 'Resetting...' : 'Reset Demo'}
        </button>
      </section>
    </main>
  )
}

export default IntroScreen
