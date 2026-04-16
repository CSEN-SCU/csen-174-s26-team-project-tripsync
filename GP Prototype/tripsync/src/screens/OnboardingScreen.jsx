import { useState } from 'react'
import { useNavigate } from 'react-router-dom'

const interests = [
  'Food',
  'Coffee',
  'Art',
  'History',
  'Shopping',
  'Parks',
  'Architecture',
  'Nightlife',
  'Hidden Gems',
  'Local Culture',
  'Street Food',
  'Music',
]

function OnboardingScreen() {
  const navigate = useNavigate()
  const [selectedInterests, setSelectedInterests] = useState([])
  const [alertMode, setAlertMode] = useState('voice-visual')

  const hasMinimumInterests = selectedInterests.length >= 3
  const progressWidth = `${Math.min((selectedInterests.length / 6) * 100, 100)}%`

  const toggleInterest = (interest) => {
    setSelectedInterests((current) => {
      if (current.includes(interest)) {
        return current.filter((item) => item !== interest)
      }
      return [...current, interest]
    })
  }

  return (
    <main className="screen" style={{ display: 'flex', flexDirection: 'column', minHeight: '100vh', paddingTop: '30px' }}>
      <div className="progress-track" aria-hidden="true">
        <div className="progress-fill" style={{ width: progressWidth }} />
      </div>

      <div style={{ flex: 1, display: 'grid', gap: '20px', alignContent: 'start', maxWidth: '860px' }}>
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

        <div>
          <p style={{ color: 'var(--text-secondary)', fontSize: '14px', marginBottom: '10px' }}>
            Step 1 of 2
          </p>
          <h1 style={{ fontSize: '32px', fontWeight: 700, lineHeight: 1.1, marginBottom: '10px' }}>
            What do you love?
          </h1>
          <p style={{ color: 'var(--text-secondary)', fontSize: '16px', lineHeight: 1.5 }}>
            We&apos;ll use this to personalize every suggestion.
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: '10px' }}>
          {interests.map((interest, index) => {
            const isSelected = selectedInterests.includes(interest)

            return (
              <button
                key={interest}
                type="button"
                onClick={() => toggleInterest(interest)}
                className="pill pill-enter"
                style={{
                  animationDelay: `${index * 30}ms`,
                  minHeight: '44px',
                  border: isSelected ? 'none' : '1px solid var(--border-color)',
                  backgroundColor: isSelected ? 'var(--accent)' : 'transparent',
                  color: isSelected ? 'var(--bg-primary)' : 'var(--text-primary)',
                  fontSize: '13px',
                  fontWeight: 600,
                  lineHeight: 1.2,
                  textAlign: 'center',
                  padding: '10px',
                }}
              >
                {interest}
              </button>
            )
          })}
        </div>

        {hasMinimumInterests && (
          <section style={{ marginTop: '4px' }}>
            <h2 style={{ fontSize: '24px', fontWeight: 700, marginBottom: '12px' }}>
              How do you want alerts?
            </h2>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0, 1fr))', gap: '12px' }}>
              <button
                type="button"
                onClick={() => setAlertMode('voice-visual')}
                style={{
                  textAlign: 'left',
                  padding: '16px',
                  borderRadius: '14px',
                  border:
                    alertMode === 'voice-visual'
                      ? '1px solid var(--accent)'
                      : '1px solid var(--border-color)',
                  background: 'var(--bg-card)',
                  color: 'var(--text-primary)',
                  cursor: 'pointer',
                }}
              >
                <p style={{ fontSize: '20px', marginBottom: '8px' }}>🔊</p>
                <p style={{ fontSize: '16px', fontWeight: 600, marginBottom: '6px' }}>Voice + Visual</p>
                <p style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
                  Hear suggestions as you walk
                </p>
              </button>

              <button
                type="button"
                onClick={() => setAlertMode('visual-only')}
                style={{
                  textAlign: 'left',
                  padding: '16px',
                  borderRadius: '14px',
                  border:
                    alertMode === 'visual-only'
                      ? '1px solid var(--accent)'
                      : '1px solid var(--border-color)',
                  background: 'var(--bg-card)',
                  color: 'var(--text-primary)',
                  cursor: 'pointer',
                }}
              >
                <p style={{ fontSize: '20px', marginBottom: '8px' }}>👁</p>
                <p style={{ fontSize: '16px', fontWeight: 600, marginBottom: '6px' }}>Visual only</p>
                <p style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
                  See suggestions on screen
                </p>
              </button>
            </div>
          </section>
        )}
      </div>

      <div style={{ paddingTop: '20px' }}>
        <button
          type="button"
          className="btn-primary"
          disabled={!hasMinimumInterests}
          onClick={() => navigate('/walking')}
          style={{
            opacity: hasMinimumInterests ? 1 : 0.45,
            cursor: hasMinimumInterests ? 'pointer' : 'not-allowed',
          }}
        >
          Let&apos;s Go
        </button>
      </div>
    </main>
  )
}

export default OnboardingScreen
