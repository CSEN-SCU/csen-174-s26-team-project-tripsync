import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import IntroScreen from './screens/IntroScreen'
import OnboardingScreen from './screens/OnboardingScreen'
import DiscoverScreen from './screens/DiscoverScreen'

function AnimatedRoutes() {
  const location = useLocation()

  return (
    <div key={location.pathname} className="route-fade">
      <Routes location={location}>
        <Route path="/" element={<IntroScreen />} />
        <Route path="/onboarding" element={<OnboardingScreen />} />
        <Route path="/discover" element={<DiscoverScreen />} />
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
