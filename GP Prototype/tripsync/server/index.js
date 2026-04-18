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
  tags.amenity || tags.tourism || tags.leisure || tags.shop || 'local place'

const EXCLUDED_PLACE_TYPES = new Set([
  'parking',
  'fuel',
  'laundry',
  'car_wash',
  'atm',
  'bank',
  'pharmacy',
  'post_office',
  'police',
  'fire_station',
  'townhall',
  'courthouse',
  'waste_basket',
  'recycling',
  'car_rental',
  'bicycle_parking',
  'bus_station',
  'taxi',
  'garage',
  'storage',
  'place_of_worship',
  'convenience',
  'massage',
  'bicycle',
  'wine',
  'alcohol',
  'tobacco',
  'hairdresser',
  'beauty',
  'optician',
  'insurance',
  'real_estate',
  'mobile_phone',
  'copyshop',
  'dry_cleaning',
  'locksmith',
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

const buildGroqPrompt = (interests, places) => {
  const placesText = places
    .map((place) => `- id: ${place.id} | ${place.name} (${place.type})`)
    .join('\n')

  return `You are a travel recommendation engine. The user has specifically told us they love: ${interests.join(', ')}. This is critical — only recommend places that directly match at least one of these interests. Do not recommend generic bars or restaurants unless Food or Nightlife is explicitly in their interests.

Here are nearby places:
${placesText}
Pick exactly 5 that best match the user's stated interests. For each return: id, why_youll_love_it (one sentence max 20 words that mentions their specific interest by name).

IMPORTANT: Return only a raw JSON array starting with [ and ending with ]. No markdown, no code blocks, no explanation text before or after the array. Only the JSON.

Return only a valid JSON array, no markdown, no explanation.`
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
        why_youll_love_it: `${place.name} matches your ${interests[0]?.toLowerCase() || 'local'} vibe and is near your pin.`,
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
  node["name"]["shop"](around:800,${lat},${lng});
);
out body 20;
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

const buildGroqGeoFallbackPrompt = (lat, lng, interests) => `The user is at coordinates ${lat}, ${lng}. Based on what city or region this likely is, invent 5 realistic-sounding local places that might exist there (cafes, parks, galleries, restaurants, landmarks). The user likes: ${interests.join(', ')}. Return a JSON array of exactly 5 objects, each with: name, type, why_youll_love_it (max 20 words). Return only valid JSON, no markdown.`

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

const buildGroqFallbackPlaces = async (lat, lng, interests) => {
  if (!groq) return buildDefaultGeoFallback(lat, lng, interests)
  try {
    const completion = await groq.chat.completions.create({
      model: GROQ_MODEL,
      messages: [{ role: 'user', content: buildGroqGeoFallbackPrompt(lat, lng, interests) }],
      temperature: 0.6,
    })
    const content = completion.choices?.[0]?.message?.content || '[]'
    const parsed = parseGroqArray(content).slice(0, 5)
    if (!parsed.length) return buildDefaultGeoFallback(lat, lng, interests)
    return parsed.map((place, index) => ({
      id: `fallback-groq-${index + 1}`,
      name: String(place?.name || `Local Spot ${index + 1}`),
      type: String(place?.type || 'local place'),
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
          messages: [{ role: 'user', content: buildGroqPrompt(interests, rawPlaces) }],
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
    curatedFive = await buildGroqFallbackPlaces(lat, lng, interests)
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
        why_youll_love_it: pick.why_youll_love_it,
        lat: Number(pick.lat),
        lon: Number(pick.lon),
        distance_m: distanceMeters,
        photo_url: photoUrl,
      }
    }),
  )

  return res.json({ places: finalPlaces, data_mode: dataMode })
})

app.get('/api/reset', (_req, res) => {
  resetSavedStmt.run()
  resetUsersStmt.run()
  return res.json({ success: true })
})

app.listen(PORT, () => {
  console.log(`TripSync API running at http://127.0.0.1:${PORT}`)
})
