import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import IntroScreen from './screens/IntroScreen'
import OnboardingScreen from './screens/OnboardingScreen'
import WalkingScreen from './screens/WalkingScreen'
import SavedScreen from './screens/SavedScreen'

function AnimatedRoutes() {
  const location = useLocation()

  return (
    <div key={location.pathname} className="route-fade">
      <Routes location={location}>
        <Route path="/" element={<IntroScreen />} />
        <Route path="/onboarding" element={<OnboardingScreen />} />
        <Route path="/walking" element={<WalkingScreen />} />
        <Route path="/saved" element={<SavedScreen />} />
      </Routes>
    </div>
  )
}

function App() {
  return (
    <BrowserRouter>
      <AnimatedRoutes />
    </BrowserRouter>
  )
}

export default App
