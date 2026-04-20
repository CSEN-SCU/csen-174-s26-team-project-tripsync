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

const buildGroqPrompt = (interests, places, cityName = null) => {
  const location = cityName ? `in ${cityName}` : 'nearby'
  const placesText = places
    .map((place) => `- id: ${place.id} | ${place.name} (${place.type})`)
    .join('\n')

  return `You are a creative travel curator helping a visitor discover the best of ${cityName || 'their city'}.

Visitor interests: ${interests.join(', ')}.

Interest → place type guide (use this to match picks to interests):
- Food → restaurants, cafes, food halls, markets, notable eateries
- Coffee → cafes, coffee roasters, espresso bars
- Art → galleries, murals, art centers, sculpture, street art
- History → historic sites, monuments, museums, heritage buildings, memorials
- Parks → parks, gardens, plazas, nature reserves, waterfronts
- Architecture → landmark buildings, bridges, notable structures, plazas
- Nightlife → bars, music venues, clubs, theatres, comedy clubs
- Hidden Gems → niche local spots, secret gardens, lesser-known attractions
- Street Food → food trucks, markets, taquerias, noodle shops, street vendors
- Adventure → trailheads, viewpoints, peaks, cliffs, waterfalls, beaches
- Viewpoints → scenic overlooks, hilltops, rooftop terraces, panoramic spots
- Hiking → trailheads, nature paths, peaks, open spaces
- Music → live music venues, jazz bars, record stores, concert halls
- Local Culture → neighborhoods, cultural centers, indie shops, local institutions

Rules — follow strictly:
1. ONLY pick places a tourist would genuinely want to visit.
2. NEVER pick: shoe stores, clothing shops, pharmacies, banks, supermarkets, gyms, or any everyday errand.
3. Match every pick to at least one stated interest using the guide above.
4. Prefer niche, locally loved, or unique spots over generic chains.
5. If a place type like "viewpoint", "peak", "waterfall", or "beach" exists in the list, always prioritize it for Adventure/Viewpoints/Hiking interests.

Places ${location}:
${placesText}

Pick exactly 5 of the most visit-worthy places that match the interests. Return a JSON array where each object has:
- id: exact id from the list
- about: one sentence (max 20 words) describing what this place actually is
- why_youll_love_it: one sentence (max 20 words) naming the specific interest it satisfies

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

const fallbackGroqSelection = (interests, places) =>
  places.slice(0, 5).map((place) => ({
    id: place.id,
    why_youll_love_it: `${place.name} fits your ${interests[0]?.toLowerCase() || 'local'} interests and is close to your pin.`,
  }))

const mergeCuratedPicks = (rawPlaces, curatedPicks, interests) => {
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
          : `${place.name} matches your ${interests[0]?.toLowerCase() || 'local'} vibe and is near your pin.`,
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
        why_youll_love_it: `${place.name} is a nearby ${place.type || 'spot'} that fits your interests.`,
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
  // Try exact place name first — gives most accurate photo
  const nameResult = await queryPexelsImage(placeName)
  if (nameResult !== FALLBACK_IMAGE) return nameResult
  // Fall back to type-based search
  const typeResult = await queryPexelsImage(placeType)
  if (typeResult !== FALLBACK_IMAGE) return typeResult
  // Last resort: generic interior/exterior by broad category
  const broad = placeType.includes('park') || placeType.includes('garden')
    ? 'city park outdoor'
    : placeType.includes('museum') || placeType.includes('gallery')
    ? 'art museum interior'
    : placeType.includes('cafe') || placeType.includes('coffee')
    ? 'cafe interior'
    : placeType.includes('restaurant') || placeType.includes('food')
    ? 'restaurant dining'
    : placeType.includes('bar') || placeType.includes('pub')
    ? 'bar nightlife'
    : placeType.includes('shop') || placeType.includes('store')
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

const buildGroqGeoFallbackPrompt = (lat, lng, interests, cityName = null) => {
  const location = cityName ? cityName : `coordinates ${lat}, ${lng}`
  return `You are a creative travel curator. A visitor is exploring ${location}. Their interests: ${interests.join(', ')}.

Suggest 5 genuinely visit-worthy, tourist-friendly places in ${cityName || 'this area'} that match their interests. Think local gems, not chains or everyday services.

Interest → place type guide:
- Food → beloved local restaurants, cafes, food markets
- History → museums, monuments, historic sites, heritage buildings
- Parks → parks, gardens, plazas, nature reserves
- Architecture → landmark buildings, notable structures, bridges
- Adventure → scenic overlooks, hilltops, trailheads, viewpoints, waterfalls, beaches
- Viewpoints → panoramic spots, hilltops, scenic terraces
- Hiking → trailheads, open spaces, nature paths, peaks
- Art → galleries, murals, cultural centers
- Nightlife → bars, live music venues, theatres
- Coffee → specialty cafes, roasters
- Hidden Gems → niche local spots, secret gardens, lesser-known spots
- Street Food → taquerias, markets, street vendors, food halls
- Music → jazz bars, concert venues, live music spots
- Local Culture → cultural centers, neighborhoods, indie institutions

Return a JSON array of exactly 5 objects, each with:
- name: the place name
- type: place type (e.g. viewpoint, park, restaurant, museum)
- about: one sentence (max 20 words) describing what this place is
- why_youll_love_it: one sentence (max 20 words) tied to a specific interest
- lat: a realistic coordinate near ${lat}
- lon: a realistic coordinate near ${lng}

Return only valid JSON array, no markdown.`
}

const buildDefaultGeoFallback = (lat, lng, interests) =>
  [
    { name: 'Local Cafe', type: 'cafe' },
    { name: 'City Park', type: 'park' },
    { name: 'Art Gallery', type: 'gallery' },
    { name: 'Restaurant Row', type: 'restaurant' },
    { name: 'Bookshop', type: 'books' },
  ].map((place, index) => ({
    id: `fallback-${index + 1}`,
    name: place.name,
    type: place.type,
    lat: lat + FALLBACK_COORD_OFFSETS[index].lat,
    lon: lng + FALLBACK_COORD_OFFSETS[index].lon,
    why_youll_love_it: `${place.name} fits your ${interests[0]?.toLowerCase() || 'local'} interests nearby.`,
  }))

const buildGroqFallbackPlaces = async (lat, lng, interests, cityName = null) => {
  if (!groq) return buildDefaultGeoFallback(lat, lng, interests)
  try {
    const completion = await groq.chat.completions.create({
      model: GROQ_MODEL,
      messages: [{ role: 'user', content: buildGroqGeoFallbackPrompt(lat, lng, interests, cityName) }],
      temperature: 0.6,
    })
    const content = completion.choices?.[0]?.message?.content || '[]'
    const parsed = parseGroqArray(content).slice(0, 5)
    if (!parsed.length) return buildDefaultGeoFallback(lat, lng, interests)
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
    return buildDefaultGeoFallback(lat, lng, interests)
  }
}

app.post('/api/onboard', (req, res) => {
  const sessionId = req.body?.session_id
  const interests = Array.isArray(req.body?.interests) ? req.body.interests : []

  if (!sessionId || !interests.length) {
    return res.status(400).json({ success: false, error: 'session_id and interests are required' })
  }

  upsertUserStmt.run(sessionId, JSON.stringify(interests))
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
  const interests = user?.interests ? JSON.parse(user.interests) : null
  console.log(`Session ID received: ${sessionId}`)
  console.log(`Interests found: ${JSON.stringify(interests)}`)
  if (!interests || !Array.isArray(interests) || !interests.length) {
    console.log('WARNING: no interests found for this session')
    return res.status(400).json({ error: 'Session not found. Please complete onboarding first.' })
  }

  const cityName = await reverseGeocode(lat, lng)
  if (cityName) console.log(`City resolved: ${cityName}`)

  const overpassResult = await fetchOverpassPlaces(lat, lng)
  let curatedFive = []
  let dataMode = 'demo'

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
          messages: [{ role: 'user', content: buildGroqPrompt(interests, rawPlaces, cityName) }],
          temperature: 0.4,
        })
        const content = completion.choices?.[0]?.message?.content || '[]'
        curated = parseGroqArray(content)
      } catch (error) {
        console.error('Groq error:', error.message)
        curated = fallbackGroqSelection(interests, rawPlaces)
      }
    } else {
      curated = fallbackGroqSelection(interests, rawPlaces)
    }
    curatedFive = mergeCuratedPicks(rawPlaces, curated, interests)
  } else {
    console.log(`Overpass failed — using Groq-generated fallback for ${lat},${lng}`)
    curatedFive = await buildGroqFallbackPlaces(lat, lng, interests, cityName)
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
        why_youll_love_it: pick.why_youll_love_it,
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
