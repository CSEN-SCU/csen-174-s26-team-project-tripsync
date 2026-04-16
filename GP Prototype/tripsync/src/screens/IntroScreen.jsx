import { useNavigate } from 'react-router-dom'

const features = [
  'Set your interests once',
  'Get voice alerts as you walk',
  'No map. No searching. Just explore.',
]

function IntroScreen() {
  const navigate = useNavigate()

  const goToOnboarding = () => {
    navigate('/onboarding')
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
          Your city finds you.
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
          Tell us what you love. Walk around. We&apos;ll ping you when something worth stopping for is
          nearby.
        </p>

        <div style={{ display: 'grid', gap: '12px' }}>
          {features.map((feature) => (
            <div key={feature} style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <span
                aria-hidden="true"
                style={{
                  color: 'var(--accent)',
                  fontSize: '14px',
                  lineHeight: 1,
                }}
              >
                ●
              </span>
              <p style={{ fontSize: '16px', color: 'var(--text-primary)' }}>{feature}</p>
            </div>
          ))}
        </div>
      </section>

      <section style={{ display: 'grid', gap: '10px', width: '100%', maxWidth: '560px' }}>
        <button type="button" className="btn-primary" onClick={goToOnboarding}>
          Start Exploring
        </button>
        <button type="button" className="btn-ghost" onClick={goToOnboarding}>
          Reset Demo
        </button>
      </section>
    </main>
  )
}

export default IntroScreen
