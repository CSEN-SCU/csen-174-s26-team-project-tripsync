/* eslint-env node */
import express from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import Database from 'better-sqlite3'
import path from 'node:path'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import Groq from 'groq-sdk'
import fetch from 'node-fetch'

dotenv.config({ path: path.join(path.dirname(fileURLToPath(import.meta.url)), '.env') })

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const dataDir = path.join(__dirname, 'data')
const dbPath = path.join(dataDir, 'tripsync.sqlite')
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true })

const app = express()
app.use(cors())
app.use(express.json())

const PORT = Number(process.env.PORT || 3001)
const GROQ_API_KEY = process.env.GROQ_API_KEY || ''
const GROQ_MODEL = process.env.GROQ_MODEL || 'llama-3.1-8b-instant'
const PEXELS_API_KEY = process.env.PEXELS_API_KEY || ''
const OVERPASS_ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.osm.ch/api/interpreter',
]
const OVERPASS_TIMEOUT_MS = 18_000
const FALLBACK_IMAGE = 'https://placehold.co/800x500/161616/00e5a0?text=TripSync'
/** Default: Groq geo-aware curation only (matches gallery demo quality). Set TRIPSYNC_USE_LIVE_OVERPASS=1 to use OSM Overpass + Groq merge. */
const USE_LIVE_OVERPASS =
  process.env.TRIPSYNC_USE_LIVE_OVERPASS === '1' || process.env.TRIPSYNC_USE_LIVE_OVERPASS === 'true'

const groq = GROQ_API_KEY ? new Groq({ apiKey: GROQ_API_KEY }) : null
const db = new Database(dbPath)

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT UNIQUE NOT NULL,
    interests TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
  );
`)

db.exec(`
  CREATE TABLE IF NOT EXISTS saved_places (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    place_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    saved_at TEXT DEFAULT CURRENT_TIMESTAMP
  );
`)

const upsertUserStmt = db.prepare(`
  INSERT INTO users (session_id, interests)
  VALUES (?, ?)
  ON CONFLICT(session_id) DO UPDATE SET interests = excluded.interests
`)
const getUserStmt = db.prepare('SELECT session_id, interests FROM users WHERE session_id = ?')
const resetUsersStmt = db.prepare('DELETE FROM users')
const resetSavedStmt = db.prepare('DELETE FROM saved_places')

const haversineMeters = (lat1, lon1, lat2, lon2) => {
  const toRad = (value) => (value * Math.PI) / 180
  const R = 6371000
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return Math.round(R * c)
}

const DEFAULT_PROFILE = {
  v: 1,
  interests: [],
  energy: 'balanced',
  pace: 'mix',
  avoid_chains: true,
  note: '',
}

const parseUserProfile = (rawJson) => {
  if (!rawJson || typeof rawJson !== 'string') return null
  try {
    const data = JSON.parse(rawJson)
    if (Array.isArray(data)) {
      return { ...DEFAULT_PROFILE, interests: data.filter(Boolean) }
    }
    if (data && typeof data === 'object' && Array.isArray(data.interests)) {
      return {
        ...DEFAULT_PROFILE,
        ...data,
        interests: data.interests.filter(Boolean),
        note: String(data.note || '').slice(0, 220),
        energy: ['calm', 'balanced', 'high'].includes(data.energy) ? data.energy : DEFAULT_PROFILE.energy,
        pace: ['wander', 'mix', 'highlights'].includes(data.pace) ? data.pace : DEFAULT_PROFILE.pace,
        avoid_chains: data.avoid_chains !== false,
      }
    }
    return null
  } catch (_error) {
    return null
  }
}

const profileSummaryForLog = (profile) =>
  JSON.stringify({
    interests: profile.interests,
    energy: profile.energy,
    pace: profile.pace,
    avoid_chains: profile.avoid_chains,
    has_note: Boolean(profile.note?.trim()),
  })

const normalizePlaceType = (tags = {}) =>
  tags.amenity || tags.tourism || tags.leisure || tags.historic || 'local place'

const EXCLUDED_PLACE_TYPES = new Set([
  // Transport / utilities
  'parking', 'fuel', 'car_wash', 'car_rental', 'bicycle_parking', 'bus_station',
  'taxi', 'garage', 'storage', 'bicycle',
  // Finance
  'atm', 'bank', 'bureau_de_change', 'insurance', 'money_transfer',
  // Healthcare / medical
  'pharmacy', 'doctors', 'dentist', 'hospital', 'clinic', 'veterinary',
  'social_facility', 'nursing_home', 'blood_bank',
  // Government / civic
  'post_office', 'police', 'fire_station', 'townhall', 'courthouse', 'prison',
  // Waste / maintenance
  'waste_basket', 'recycling', 'waste_disposal', 'recycling_centre',
  // Religious
  'place_of_worship',
  // Everyday errands / services
  'convenience', 'laundry', 'dry_cleaning', 'lavoir', 'locksmith',
  'hairdresser', 'beauty', 'optician', 'massage',
  'mobile_phone', 'copyshop', 'real_estate', 'estate_agent',
  'tobacco', 'alcohol', 'wine', 'beverages',
  // Retail shops (never tourist destinations)
  'shoes', 'clothes', 'clothing', 'fashion', 'sports', 'outdoor',
  'electronics', 'computer', 'appliance', 'furniture', 'hardware',
  'doityourself', 'garden', 'florist', 'stationery',
  'toys', 'jewelry', 'watches', 'gift', 'department_store', 'mall',
  'supermarket', 'grocery', 'butcher', 'deli',
  // Misc non-tourist
  'vending_machine', 'charging_station', 'telephone', 'post_box',
  'drinking_water', 'toilets', 'shower',
])

const extractNamedOverpassPlaces = (elements, logPrefix = '') => {
  const named = (elements || []).filter((node) => node.type === 'node' && node.tags?.name)
  const mapped = named.map((node) => ({
    id: `osm-${node.id}`,
    name: node.tags.name,
    type: normalizePlaceType(node.tags),
    lat: Number(node.lat),
    lon: Number(node.lon),
    tags: node.tags,
  }))
  const filtered = mapped.filter((node) => !EXCLUDED_PLACE_TYPES.has(String(node.type || '').toLowerCase()))
  if (logPrefix) {
    console.log(`${logPrefix} raw=${named.length} after-filter=${filtered.length}`)
  }
  return filtered.slice(0, 15)
}

const FALLBACK_COORD_OFFSETS = [
  { lat: 0.001, lon: 0.001 },
  { lat: -0.001, lon: 0.001 },
  { lat: 0.001, lon: -0.001 },
  { lat: -0.001, lon: -0.001 },
  { lat: 0.002, lon: 0.002 },
]

const energyCopy = {
  calm: 'They want a steady, low-rush day — quieter corners, room to breathe, minimal sensory overload.',
  balanced: 'They want a balanced day — a mix of energy without feeling rushed or tourist-trap hectic.',
  high: 'They want a packed, ambitious day — bold stops, memorable highlights, high signal per hour.',
}

const paceCopy = {
  wander: 'They like to wander and detour — serendipity over efficiency; side streets and odd angles welcome.',
  mix: 'They like a mix of classics and surprises — one or two anchor stops plus unexpected finds.',
  highlights: 'They prefer an efficient highlights reel — iconic or high-payoff stops, less meandering.',
}

const buildGroqPrompt = (profile, places, cityName = null) => {
  const interests = profile.interests || []
  const location = cityName ? `in ${cityName}` : 'nearby'
  const placesText = places
    .map((place) => `- id: ${place.id} | ${place.name} (${place.type})`)
    .join('\n')

  const chainRule = profile.avoid_chains
    ? 'Strongly prefer independent, local, or neighborhood-defining spots over global chains and mall defaults.'
    : 'Chains are acceptable only if they are clearly the best match for the stated interests.'

  const noteBlock = profile.note?.trim()
    ? `Visitor added context (honor this if relevant, ignore if empty noise): "${profile.note.trim()}"`
    : 'No extra free-text note from the visitor.'

  return `You are a sharp local curator (not a generic travel blog). Help someone get the most meaningful 90 minutes near their pin in ${cityName || 'this city'}.

=== Visitor profile ===
Interests: ${interests.join(', ')}
Day energy: ${energyCopy[profile.energy] || energyCopy.balanced}
Exploration style: ${paceCopy[profile.pace] || paceCopy.mix}
${chainRule}
${noteBlock}

=== Interest → place type guide ===
- Food → restaurants, food halls, markets, notable eateries (not supermarkets)
- Coffee → cafes, roasters, espresso bars
- Art → galleries, murals, art centers, sculpture
- History → monuments, museums, heritage buildings, memorials, historic sites
- Parks → parks, gardens, plazas, nature reserves, waterfronts
- Architecture → landmark buildings, bridges, notable structures
- Nightlife → bars, music venues, theatres, comedy clubs
- Hidden Gems → niche local spots, lesser-known public spaces
- Street Food → markets, taquerias, food trucks, street vendors
- Adventure / Viewpoints / Hiking → viewpoints, peaks, cliffs, beaches, trailheads, waterfalls, scenic overlooks

=== Curation rules ===
1. ONLY pick places a curious visitor would genuinely want to go — not errands, not retail shopping, not medical/finance.
2. Match each pick to at least one stated interest (name that interest in why_youll_love_it).
3. DIVERSITY: across the 5 picks, span at least 3 different primary vibes (e.g. not five nearly-identical restaurants unless interests are ONLY food-related and the list truly forces it).
4. If interests span food + outdoors + culture, reflect that spread in the picks.
5. Writing voice: concrete, specific, human. NO filler clichés (avoid words/phrases like: "hidden gem", "nestled", "vibrant", "must-visit", "bucket list"). Say what you actually see, taste, hear, or do there.

Places ${location}:
${placesText}

Return a JSON array of exactly 5 objects. Each object:
- id: exact id from the list above
- about: one or two short sentences (max 35 words total) — factual, what happens there
- why_youll_love_it: one sentence (max 28 words) — ties explicitly to their interests AND energy/pace when relevant

IMPORTANT: Return only a raw JSON array [ ... ]. No markdown, no code fences, no extra text.`
}

const parseGroqArray = (rawText) => {
  const text = String(rawText || '')
    .replace(/```json/gi, '')
    .replace(/```/g, '')
    .trim()

  const firstBracket = text.indexOf('[')
  const lastBracket = text.lastIndexOf(']')
  if (firstBracket === -1 || lastBracket === -1 || lastBracket <= firstBracket) {
    console.log('Raw Groq response:', rawText)
    throw new Error('Groq response missing JSON array brackets')
  }

  const candidate = text.slice(firstBracket, lastBracket + 1)
  try {
    const parsed = JSON.parse(candidate)
    if (!Array.isArray(parsed)) {
      console.log('Raw Groq response:', rawText)
      throw new Error('Groq did not return an array')
    }
    return parsed
  } catch (_error) {
    console.log('Raw Groq response:', rawText)
    throw new Error('Groq JSON parse failed')
  }
}

const fallbackGroqSelection = (profile, places) => {
  const interests = profile.interests || []
  return places.slice(0, 5).map((place) => ({
    id: place.id,
    why_youll_love_it: `${place.name} lines up with your ${interests[0]?.toLowerCase() || 'exploration'} thread and is a short walk from your pin.`,
  }))
}

const mergeCuratedPicks = (rawPlaces, curatedPicks, profile) => {
  const interests = profile.interests || []
  const byId = new Map(rawPlaces.map((place) => [place.id, place]))
  const used = new Set()
  const merged = []

  for (const pick of curatedPicks) {
    const id = String(pick?.id || '')
    if (!id || used.has(id) || !byId.has(id)) continue
    const place = byId.get(id)
    merged.push({
      ...place,
      about:
        typeof pick?.about === 'string' && pick.about.trim() ? pick.about.trim() : null,
      why_youll_love_it:
        typeof pick?.why_youll_love_it === 'string' && pick.why_youll_love_it.trim()
          ? pick.why_youll_love_it.trim()
          : `${place.name} fits your ${interests[0]?.toLowerCase() || 'local'} picks and sits near your pin.`,
    })
    used.add(id)
    if (merged.length === 5) break
  }

  if (merged.length < 5) {
    for (const place of rawPlaces) {
      if (used.has(place.id)) continue
      merged.push({
        ...place,
        about: null,
        why_youll_love_it: `${place.name} is a nearby ${place.type || 'spot'} that matches how you said you like to explore.`,
      })
      used.add(place.id)
      if (merged.length === 5) break
    }
  }

  return merged
}

const queryPexelsImage = async (term) => {
  if (!PEXELS_API_KEY) return FALLBACK_IMAGE
  const url = `https://api.pexels.com/v1/search?query=${encodeURIComponent(term)}&per_page=3`
  try {
    const response = await fetch(url, {
      headers: { Authorization: PEXELS_API_KEY },
    })
    if (!response.ok) return FALLBACK_IMAGE
    const payload = await response.json()
    return payload?.photos?.[0]?.src?.large || FALLBACK_IMAGE
  } catch (_error) {
    return FALLBACK_IMAGE
  }
}

const queryPexelsImageForPlace = async (placeName, placeType) => {
  if (!PEXELS_API_KEY) return FALLBACK_IMAGE
  const typeStr = typeof placeType === 'string' ? placeType : String(placeType || 'local place')
  // Try exact place name first — gives most accurate photo
  const nameResult = await queryPexelsImage(placeName)
  if (nameResult !== FALLBACK_IMAGE) return nameResult
  // Fall back to type-based search
  const typeResult = await queryPexelsImage(typeStr)
  if (typeResult !== FALLBACK_IMAGE) return typeResult
  // Last resort: generic interior/exterior by broad category
  const broad = typeStr.includes('park') || typeStr.includes('garden')
    ? 'city park outdoor'
    : typeStr.includes('museum') || typeStr.includes('gallery')
    ? 'art museum interior'
    : typeStr.includes('cafe') || typeStr.includes('coffee')
    ? 'cafe interior'
    : typeStr.includes('restaurant') || typeStr.includes('food')
    ? 'restaurant dining'
    : typeStr.includes('bar') || typeStr.includes('pub')
    ? 'bar nightlife'
    : typeStr.includes('shop') || typeStr.includes('store')
    ? 'retail shop street'
    : 'city street local'
  return queryPexelsImage(broad)
}

const buildOverpassQuery = (lat, lng) => `
[out:json][timeout:10];
(
  node["name"]["amenity"](around:800,${lat},${lng});
  node["name"]["tourism"](around:800,${lat},${lng});
  node["name"]["leisure"](around:800,${lat},${lng});
  node["name"]["historic"](around:800,${lat},${lng});
  node["name"]["natural"](around:1000,${lat},${lng});
);
out body 25;
`

const fetchOverpassPlaces = async (lat, lng) => {
  const overpassQuery = buildOverpassQuery(lat, lng)
  for (const endpoint of OVERPASS_ENDPOINTS) {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), OVERPASS_TIMEOUT_MS)
    try {
      console.log(`Trying Overpass mirror: ${endpoint}`)
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: `data=${encodeURIComponent(overpassQuery)}`,
        signal: controller.signal,
      })
      clearTimeout(timeoutId)
      if (!response.ok) {
        throw new Error(`Overpass failed with ${response.status} from ${endpoint}`)
      }
      const payload = await response.json()
      const places = extractNamedOverpassPlaces(payload.elements, `[${endpoint.split('/')[2]}]`)
      if (places.length) {
        console.log(`✓ Overpass mirror success: ${endpoint}`)
        return { ok: true, places }
      }
      console.log(`Overpass mirror returned 0 usable places: ${endpoint}`)
    } catch (error) {
      clearTimeout(timeoutId)
      console.error(`Overpass error (${endpoint}):`, error.message)
    }
  }
  return { ok: false, places: [] }
}

const reverseGeocode = async (lat, lng) => {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 5000)
    const response = await fetch(url, {
      headers: { 'User-Agent': 'TripSync/1.0 (gallery-walk-demo)' },
      signal: controller.signal,
    })
    clearTimeout(timeoutId)
    if (!response.ok) return null
    const data = await response.json()
    const addr = data.address || {}
    return addr.city || addr.town || addr.village || addr.suburb || addr.county || null
  } catch (_error) {
    return null
  }
}

const buildGroqGeoFallbackPrompt = (lat, lng, profile, cityName = null) => {
  const interests = profile.interests || []
  const location = cityName ? cityName : `coordinates ${lat}, ${lng}`
  return `You are a creative travel curator. A visitor is exploring ${location}.

Profile:
- Interests: ${interests.join(', ')}
- Day energy: ${energyCopy[profile.energy] || energyCopy.balanced}
- Exploration: ${paceCopy[profile.pace] || paceCopy.mix}
- ${profile.avoid_chains ? 'Prefer indie/local over chains.' : 'Chains OK if best fit.'}
${profile.note?.trim() ? `- Note: "${profile.note.trim()}"` : ''}

Invent or name 5 plausible, visit-worthy spots in ${cityName || 'this area'} that match the profile. No pharmacies, banks, shoe stores, or errands.

Diversify across 5 picks (food, outdoors, culture, etc. as interests allow).

Return a JSON array of exactly 5 objects:
- name, type, about (max 35 words factual), why_youll_love_it (max 28 words, name an interest)
- lat, lon near ${lat}, ${lng}

No cliché filler ("hidden gem", "nestled", "vibrant"). Return only valid JSON array, no markdown.`
}

const buildDefaultGeoFallback = (lat, lng, profile) => {
  const interests = profile.interests || []
  return [
    { name: 'Neighborhood Cafe', type: 'cafe' },
    { name: 'Riverside Walk', type: 'park' },
    { name: 'City Lookout', type: 'viewpoint' },
    { name: 'Local Kitchen', type: 'restaurant' },
    { name: 'Small Gallery', type: 'gallery' },
  ].map((place, index) => ({
    id: `fallback-${index + 1}`,
    name: place.name,
    type: place.type,
    lat: lat + FALLBACK_COORD_OFFSETS[index].lat,
    lon: lng + FALLBACK_COORD_OFFSETS[index].lon,
    why_youll_love_it: `${place.name} fits your ${interests[0]?.toLowerCase() || 'exploration'} thread near your pin.`,
  }))
}

const buildGroqFallbackPlaces = async (lat, lng, profile, cityName = null) => {
  const interests = profile.interests || []
  if (!groq) return buildDefaultGeoFallback(lat, lng, profile)
  try {
    const completion = await groq.chat.completions.create({
      model: GROQ_MODEL,
      messages: [{ role: 'user', content: buildGroqGeoFallbackPrompt(lat, lng, profile, cityName) }],
      temperature: 0.55,
    })
    const content = completion.choices?.[0]?.message?.content || '[]'
    const parsed = parseGroqArray(content).slice(0, 5)
    if (!parsed.length) return buildDefaultGeoFallback(lat, lng, profile)
    return parsed.map((place, index) => ({
      id: `fallback-groq-${index + 1}`,
      name: String(place?.name || `Local Spot ${index + 1}`),
      type: String(place?.type || 'local place'),
      about: typeof place?.about === 'string' && place.about.trim() ? place.about.trim() : null,
      lat: lat + FALLBACK_COORD_OFFSETS[index].lat,
      lon: lng + FALLBACK_COORD_OFFSETS[index].lon,
      why_youll_love_it:
        typeof place?.why_youll_love_it === 'string' && place.why_youll_love_it.trim()
          ? place.why_youll_love_it.trim()
          : `A good nearby match for your ${interests[0]?.toLowerCase() || 'local'} interests.`,
    }))
  } catch (error) {
    console.error('Groq fallback generation error:', error.message)
    return buildDefaultGeoFallback(lat, lng, profile)
  }
}

app.post('/api/onboard', (req, res) => {
  const sessionId = req.body?.session_id
  let profile = null
  if (req.body?.profile && typeof req.body.profile === 'object') {
    profile = parseUserProfile(JSON.stringify(req.body.profile))
  } else if (Array.isArray(req.body?.interests)) {
    profile = parseUserProfile(JSON.stringify({ interests: req.body.interests }))
  }

  if (!sessionId || !profile?.interests?.length) {
    return res.status(400).json({
      success: false,
      error: 'session_id and profile (or interests[]) with at least one interest are required',
    })
  }

  upsertUserStmt.run(sessionId, JSON.stringify(profile))
  return res.json({ success: true })
})

app.get('/api/discover', async (req, res) => {
  const lat = Number(req.query.lat)
  const lng = Number(req.query.lng)
  const sessionId = String(req.query.session_id || '')

  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !sessionId) {
    return res.status(400).json({ error: 'lat, lng, and session_id are required' })
  }

  const user = getUserStmt.get(sessionId)
  const profile = user?.interests ? parseUserProfile(user.interests) : null
  console.log(`Session ID received: ${sessionId}`)
  console.log(`Profile: ${profile ? profileSummaryForLog(profile) : 'null'}`)
  if (!profile?.interests?.length) {
    console.log('WARNING: no profile / interests found for this session')
    return res.status(400).json({ error: 'Session not found. Please complete onboarding first.' })
  }

  const cityName = await reverseGeocode(lat, lng)
  if (cityName) console.log(`City resolved: ${cityName}`)

  let curatedFive = []
  let dataMode = 'demo'

  if (USE_LIVE_OVERPASS) {
    const overpassResult = await fetchOverpassPlaces(lat, lng)
    if (overpassResult.ok) {
      const rawPlaces = overpassResult.places
      console.log(`Overpass success — ${rawPlaces.length} places found near ${lat},${lng}`)
      console.log(`Overpass candidates: ${rawPlaces.map((p) => `${p.name} (${p.type})`).join(', ')}`)
      dataMode = 'live'
      let curated = []
      if (groq) {
        try {
          const completion = await groq.chat.completions.create({
            model: GROQ_MODEL,
            messages: [{ role: 'user', content: buildGroqPrompt(profile, rawPlaces, cityName) }],
            temperature: 0.42,
          })
          const content = completion.choices?.[0]?.message?.content || '[]'
          curated = parseGroqArray(content)
        } catch (error) {
          console.error('Groq error:', error.message)
          curated = fallbackGroqSelection(profile, rawPlaces)
        }
      } else {
        curated = fallbackGroqSelection(profile, rawPlaces)
      }
      curatedFive = mergeCuratedPicks(rawPlaces, curated, profile)
    } else {
      console.log(`Overpass failed — using Groq-generated fallback for ${lat},${lng}`)
      curatedFive = await buildGroqFallbackPlaces(lat, lng, profile, cityName)
    }
  } else {
    console.log(
      `Curation: AI-only (Groq geo). Set TRIPSYNC_USE_LIVE_OVERPASS=1 for live OSM + merge. Pin: ${lat},${lng}`,
    )
    curatedFive = await buildGroqFallbackPlaces(lat, lng, profile, cityName)
  }

  const finalPlaces = await Promise.all(
    curatedFive.map(async (pick) => {
      const placeType = String(pick.type || 'local place')
      const photoUrl = await queryPexelsImageForPlace(pick.name, placeType)
      const distanceMeters = haversineMeters(lat, lng, Number(pick.lat), Number(pick.lon))
      return {
        id: pick.id,
        name: pick.name,
        type: placeType,
        about: pick.about || null,
        why_youll_love_it:
          typeof pick.why_youll_love_it === 'string' && pick.why_youll_love_it.trim()
            ? pick.why_youll_love_it.trim()
            : `${pick.name || 'This spot'} is a short walk from your pin and fits your picks.`,
        lat: Number(pick.lat),
        lon: Number(pick.lon),
        distance_m: distanceMeters,
        photo_url: photoUrl,
      }
    }),
  )

  return res.json({ places: finalPlaces, data_mode: dataMode, city_name: cityName || null })
})

app.get('/api/reset', (_req, res) => {
  resetSavedStmt.run()
  resetUsersStmt.run()
  return res.json({ success: true })
})

app.listen(PORT, () => {
  console.log(`TripSync API running at http://127.0.0.1:${PORT}`)
})
