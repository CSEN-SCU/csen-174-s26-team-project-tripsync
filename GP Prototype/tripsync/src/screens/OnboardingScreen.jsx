import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { clearSessionId, onboard, setInterests, setSessionId } from '../lib/api'

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
  'Shopping',
  'Music',
  'Local Culture',
]

function OnboardingScreen() {
  const navigate = useNavigate()
  const location = useLocation()
  const [selectedInterests, setSelectedInterests] = useState([])
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [formError, setFormError] = useState('')

  useEffect(() => {
    clearSessionId()
    if (location.state?.message) {
      setFormError(location.state.message)
    }
  }, [location.state?.message])

  const hasMinimumInterests = selectedInterests.length >= 3
  const progressWidth = `${Math.min((selectedInterests.length / 6) * 100, 100)}%`

  const toggleInterest = (interest) => {
    setFormError('')
    setSelectedInterests((current) => {
      if (current.includes(interest)) {
        return current.filter((item) => item !== interest)
      }
      return [...current, interest]
    })
  }

  const handleSubmit = async () => {
    if (!hasMinimumInterests || isSubmitting) return
    try {
      setIsSubmitting(true)
      const sessionId = crypto.randomUUID()
      await onboard({ sessionId, interests: selectedInterests })
      setSessionId(sessionId)
      setInterests(selectedInterests)
      navigate('/discover', { state: { sessionId } })
    } catch (_error) {
      setFormError('Onboarding failed. Make sure backend server is running on port 3001.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <main className="screen onboarding-screen">
      <div className="progress-track" aria-hidden="true">
        <div className="progress-fill" style={{ width: progressWidth }} />
      </div>

      <button className="back-btn" type="button" onClick={() => navigate('/')}>
        ←
      </button>

      <header className="screen-header">
        <p className="subtle-label">What are you into?</p>
        <h1>Pick your interests</h1>
        <p className="subtle-copy">Select at least 3 so TripSync can curate your nearby places.</p>
      </header>

      <section className="interest-grid">
        {interests.map((interest, index) => {
          const selected = selectedInterests.includes(interest)
          return (
            <button
              key={interest}
              type="button"
              className={`interest-pill pill-enter ${selected ? 'selected' : ''}`}
              style={{ animationDelay: `${index * 30}ms` }}
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
          <p className="subtle-copy">Choose at least 3 interests to continue.</p>
        ) : null}
        <button
          type="button"
          className="btn-primary"
          onClick={handleSubmit}
          disabled={!hasMinimumInterests || isSubmitting}
          style={{
            opacity: hasMinimumInterests && !isSubmitting ? 1 : 0.45,
            cursor: hasMinimumInterests && !isSubmitting ? 'pointer' : 'not-allowed',
          }}
        >
          {isSubmitting ? 'Saving...' : 'Find Places'}
        </button>
      </footer>
    </main>
  )
}

export default OnboardingScreen
