import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { clearSessionId, onboard, setProfile, setSessionId } from '../lib/api'

const interests = [
  'Food',
  'Coffee',
  'Art',
  'History',
  'Parks',
  'Architecture',
  'Nightlife',
  'Hidden Gems',
  'Street Food',
  'Adventure',
  'Viewpoints',
  'Hiking',
  'Music',
  'Local Culture',
]

const ENERGY_OPTIONS = [
  { id: 'calm', title: 'Steady & calm', desc: 'Quieter corners, room to breathe' },
  { id: 'balanced', title: 'Balanced', desc: 'Energy without the tourist-trap rush' },
  { id: 'high', title: 'Packed & bold', desc: 'High signal per hour, memorable stops' },
]

const PACE_OPTIONS = [
  { id: 'wander', title: 'Wander & detour', desc: 'Serendipity over efficiency' },
  { id: 'mix', title: 'Classics + surprises', desc: 'Anchors plus unexpected finds' },
  { id: 'highlights', title: 'Highlights reel', desc: 'Iconic stops, less meandering' },
]

function OnboardingScreen() {
  const navigate = useNavigate()
  const location = useLocation()
  const [step, setStep] = useState(1)
  const [selectedInterests, setSelectedInterests] = useState([])
  const [energy, setEnergy] = useState('balanced')
  const [pace, setPace] = useState('mix')
  const [avoidChains, setAvoidChains] = useState(true)
  const [note, setNote] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [formError, setFormError] = useState('')

  useEffect(() => {
    clearSessionId()
    if (location.state?.message) {
      setFormError(location.state.message)
    }
  }, [location.state?.message])

  const hasMinimumInterests = selectedInterests.length >= 3
  const progressWidth = step === 1
    ? `${Math.min((selectedInterests.length / 6) * 50, 50)}%`
    : `${50 + Math.min((note.trim().length / 80) * 50, 50)}%`

  const toggleInterest = (interest) => {
    setFormError('')
    setSelectedInterests((current) => {
      if (current.includes(interest)) {
        return current.filter((item) => item !== interest)
      }
      return [...current, interest]
    })
  }

  const buildProfile = () => ({
    v: 1,
    interests: selectedInterests,
    energy,
    pace,
    avoid_chains: avoidChains,
    note: note.trim().slice(0, 220),
  })

  const handleFinish = async () => {
    if (!hasMinimumInterests || isSubmitting) return
    try {
      setIsSubmitting(true)
      const sessionId = crypto.randomUUID()
      const profile = buildProfile()
      await onboard({ sessionId, profile })
      setSessionId(sessionId)
      setProfile(profile)
      navigate('/discover', { state: { sessionId } })
    } catch (_error) {
      setFormError('Onboarding failed. Make sure backend server is running on port 3001.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <main className="screen onboarding-screen route-fade">
      <div className="progress-track" aria-hidden="true">
        <div className="progress-fill" style={{ width: progressWidth }} />
      </div>

      <button className="back-btn" type="button" onClick={() => (step === 2 ? setStep(1) : navigate('/'))}>
        ←
      </button>

      {step === 1 ? (
        <>
          <header className="screen-header">
            <p className="subtle-label">Step 1 of 2</p>
            <h1>What pulls you in?</h1>
            <p className="subtle-copy">
              Pick what you actually care about today — TripSync uses this to weight real places near your pin, not generic lists.
            </p>
          </header>

          <section className="interest-grid">
            {interests.map((interest, index) => {
              const selected = selectedInterests.includes(interest)
              return (
                <button
                  key={interest}
                  type="button"
                  className={`interest-pill pill-enter ${selected ? 'selected' : ''}`}
                  style={{ animationDelay: `${index * 28}ms` }}
                  onClick={() => toggleInterest(interest)}
                >
                  {interest}
                </button>
              )
            })}
          </section>

          <footer className="onboarding-footer">
            {formError ? <p className="error-copy">{formError}</p> : null}
            {!hasMinimumInterests ? (
              <p className="subtle-copy">Choose at least 3 — more overlap helps the curator connect dots.</p>
            ) : null}
            <button
              type="button"
              className="btn-primary"
              onClick={() => setStep(2)}
              disabled={!hasMinimumInterests}
              style={{
                opacity: hasMinimumInterests ? 1 : 0.45,
                cursor: hasMinimumInterests ? 'pointer' : 'not-allowed',
              }}
            >
              Continue →
            </button>
          </footer>
        </>
      ) : (
        <>
          <header className="screen-header">
            <p className="subtle-label">Step 2 of 2</p>
            <h1>Set the tone</h1>
            <p className="subtle-copy">
              Same map pin, different vibe — this steers how aggressive, varied, and local-first the AI picks should be.
            </p>
          </header>

          <section className="onb-section">
            <h2 className="onb-section-title">Day energy</h2>
            <div className="choice-grid">
              {ENERGY_OPTIONS.map((opt) => (
                <button
                  key={opt.id}
                  type="button"
                  className={`choice-card ${energy === opt.id ? 'selected' : ''}`}
                  onClick={() => setEnergy(opt.id)}
                >
                  <span className="choice-title">{opt.title}</span>
                  <span className="choice-desc">{opt.desc}</span>
                </button>
              ))}
            </div>
          </section>

          <section className="onb-section">
            <h2 className="onb-section-title">Exploration style</h2>
            <div className="choice-grid">
              {PACE_OPTIONS.map((opt) => (
                <button
                  key={opt.id}
                  type="button"
                  className={`choice-card ${pace === opt.id ? 'selected' : ''}`}
                  onClick={() => setPace(opt.id)}
                >
                  <span className="choice-title">{opt.title}</span>
                  <span className="choice-desc">{opt.desc}</span>
                </button>
              ))}
            </div>
          </section>

          <section className="onb-section">
            <label className="toggle-row">
              <input
                type="checkbox"
                checked={avoidChains}
                onChange={(e) => setAvoidChains(e.target.checked)}
              />
              <span>Prefer indie & neighborhood spots over big chains</span>
            </label>
          </section>

          <section className="onb-section">
            <label className="onb-section-title" htmlFor="trip-note">Anything else? (optional)</label>
            <textarea
              id="trip-note"
              className="onb-textarea"
              rows={3}
              maxLength={220}
              placeholder="e.g. vegetarian, love brutalist architecture, avoiding steep hills…"
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
            <p className="char-count">{note.length}/220</p>
          </section>

          <footer className="onboarding-footer">
            {formError ? <p className="error-copy">{formError}</p> : null}
            <button type="button" className="btn-ghost" onClick={() => setStep(1)}>
              ← Back to interests
            </button>
            <button
              type="button"
              className="btn-primary"
              onClick={handleFinish}
              disabled={isSubmitting}
            >
              {isSubmitting ? 'Saving…' : 'Build my map'}
            </button>
          </footer>
        </>
      )}
    </main>
  )
}

export default OnboardingScreen
