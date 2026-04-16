/* eslint-env node */
import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import https from 'node:https'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'
import dotenv from 'dotenv'
import initSqlJs from 'sql.js'

dotenv.config()

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const projectRoot = path.resolve(__dirname, '..')
const dataDir = path.join(__dirname, 'data')
const dbPath = path.join(dataDir, 'tripsync.sqlite')

const require = createRequire(import.meta.url)
const sqlJsDistPath = path.dirname(require.resolve('sql.js'))

const GEMINI_API_KEY = (process.env.GEMINI_API_KEY || '').trim()
const GEMINI_MODEL = process.env.GEMINI_MODEL || 'gemini-1.5-flash'
const PORT = Number(process.env.PORT || 8787)

const PLACE_SEED = [
  {
    id: 1,
    name: 'Tartine Manufactory',
    type: 'Bakery',
    distance_m: 80,
    lat: 37.7614,
    lng: -122.4105,
    bearing_deg: 305,
  },
  {
    id: 2,
    name: 'Adobe Books',
    type: 'Bookshop',
    distance_m: 140,
    lat: 37.7592,
    lng: -122.4217,
    bearing_deg: 225,
  },
  {
    id: 3,
    name: 'Dolores Park',
    type: 'Park',
    distance_m: 210,
    lat: 37.7596,
    lng: -122.4269,
    bearing_deg: 260,
  },
  {
    id: 4,
    name: 'Bi-Rite Creamery',
    type: 'Ice Cream',
    distance_m: 260,
    lat: 37.7616,
    lng: -122.4241,
    bearing_deg: 248,
  },
  {
    id: 5,
    name: '996 Mural',
    type: 'Street Art',
    distance_m: 310,
    lat: 37.7515,
    lng: -122.4194,
    bearing_deg: 190,
  },
]

const serverState = {
  db: null,
}

const EARTH_RADIUS_METERS = 6371000

const toRadians = (value) => (value * Math.PI) / 180
const toDegrees = (value) => (value * 180) / Math.PI

const formatRelative = (timestampMs) => {
  const diffMs = Math.max(Date.now() - timestampMs, 0)
  const minutes = Math.round(diffMs / 60000)
  if (minutes < 1) return 'just now'
  if (minutes === 1) return '1 min ago'
  if (minutes < 60) return `${minutes} mins ago`
  const hours = Math.round(minutes / 60)
  return `${hours}h ago`
}

const getMapPosition = (distanceMeters, bearingDeg) => {
  const radius = Math.min(distanceMeters / 8, 38)
  const radians = ((bearingDeg - 90) * Math.PI) / 180
  return {
    x: Math.round((50 + Math.cos(radians) * radius) * 10) / 10,
    y: Math.round((50 + Math.sin(radians) * radius) * 10) / 10,
  }
}

const getDistanceMeters = (from, to) => {
  const lat1 = toRadians(from.lat)
  const lon1 = toRadians(from.lng)
  const lat2 = toRadians(to.lat)
  const lon2 = toRadians(to.lng)

  const dLat = lat2 - lat1
  const dLon = lon2 - lon1

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

  return EARTH_RADIUS_METERS * c
}

const getBearingDegrees = (from, to) => {
  const lat1 = toRadians(from.lat)
  const lat2 = toRadians(to.lat)
  const dLon = toRadians(to.lng - from.lng)
  const y = Math.sin(dLon) * Math.cos(lat2)
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon)
  return (toDegrees(Math.atan2(y, x)) + 360) % 360
}

const sendJson = (res, statusCode, payload) => {
  const body = JSON.stringify(payload)
  res.writeHead(statusCode, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  })
  res.end(body)
}

const parseBody = (req) =>
  new Promise((resolve, reject) => {
    const chunks = []

    req.on('data', (chunk) => {
      chunks.push(chunk)
    })

    req.on('end', () => {
      if (!chunks.length) {
        resolve({})
        return
      }

      try {
        const parsed = JSON.parse(Buffer.concat(chunks).toString('utf-8'))
        resolve(parsed)
      } catch (error) {
        reject(new Error('Invalid JSON body'))
      }
    })

    req.on('error', reject)
  })

const persistDb = () => {
  if (!serverState.db) return
  if (!fs.existsSync(dataDir)) {
    fs.mkdirSync(dataDir, { recursive: true })
  }
  const bytes = serverState.db.export()
  fs.writeFileSync(dbPath, Buffer.from(bytes))
}

const runStatement = (sql, params = []) => {
  const stmt = serverState.db.prepare(sql)
  stmt.bind(params)
  stmt.step()
  stmt.free()
}

const queryRows = (sql, params = []) => {
  const stmt = serverState.db.prepare(sql)
  stmt.bind(params)
  const rows = []
  while (stmt.step()) {
    rows.push(stmt.getAsObject())
  }
  stmt.free()
  return rows
}

const queryOne = (sql, params = []) => queryRows(sql, params)[0] || null

const ensureColumn = (tableName, columnName, definitionSql) => {
  const columns = queryRows(`PRAGMA table_info(${tableName})`)
  const exists = columns.some((column) => column.name === columnName)
  if (!exists) {
    runStatement(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definitionSql}`)
  }
}

const ensureSchema = () => {
  runStatement(`
    CREATE TABLE IF NOT EXISTS places (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      distance_m INTEGER NOT NULL,
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      bearing_deg INTEGER NOT NULL
    )
  `)

  runStatement(`
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      interests_json TEXT NOT NULL,
      alert_mode TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
  `)

  runStatement(`
    CREATE TABLE IF NOT EXISTS saved_places (
      session_id TEXT NOT NULL,
      place_id TEXT NOT NULL,
      place_name TEXT,
      place_type TEXT,
      place_description TEXT,
      place_lat REAL,
      place_lng REAL,
      saved_at INTEGER NOT NULL,
      PRIMARY KEY (session_id, place_id)
    )
  `)

  runStatement(`
    CREATE TABLE IF NOT EXISTS ai_notes (
      place_id TEXT NOT NULL,
      profile_key TEXT NOT NULL,
      note TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (place_id, profile_key)
    )
  `)

  ensureColumn('saved_places', 'place_name', 'TEXT')
  ensureColumn('saved_places', 'place_type', 'TEXT')
  ensureColumn('saved_places', 'place_description', 'TEXT')
  ensureColumn('saved_places', 'place_lat', 'REAL')
  ensureColumn('saved_places', 'place_lng', 'REAL')
}

const seedPlacesIfEmpty = () => {
  const countRow = queryOne('SELECT COUNT(*) AS count FROM places')
  if (Number(countRow?.count || 0) > 0) return

  PLACE_SEED.forEach((place) => {
    runStatement(
      `INSERT INTO places (id, name, type, distance_m, lat, lng, bearing_deg)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [place.id, place.name, place.type, place.distance_m, place.lat, place.lng, place.bearing_deg],
    )
  })
}

const fallbackWhy = (place, interests) => {
  const keyInterest = interests[0] || 'local spots'
  return `${place.name} matches your ${keyInterest.toLowerCase()} vibe and is close enough to check out without breaking your walk.`
}

const requestJson = (url, options = {}, body = null) =>
  new Promise((resolve, reject) => {
    const request = https.request(url, options, (response) => {
      let responseBody = ''
      response.on('data', (chunk) => {
        responseBody += chunk.toString()
      })
      response.on('end', () => {
        if (response.statusCode && response.statusCode >= 400) {
          reject(new Error(`HTTP ${response.statusCode}: ${responseBody.slice(0, 200)}`))
          return
        }

        try {
          resolve(JSON.parse(responseBody))
        } catch (error) {
          reject(error)
        }
      })
    })

    request.on('error', reject)
    if (body) request.write(body)
    request.end()
  })

const inferTypeFromTags = (tags = {}) =>
  tags.amenity || tags.tourism || tags.shop || tags.leisure || tags.historic || 'Local Spot'

const fetchNearbyPlacesFromOverpass = async (lat, lng) => {
  const query = `
    [out:json][timeout:20];
    (
      node(around:1200,${lat},${lng})["tourism"];
      node(around:1200,${lat},${lng})["amenity"];
      node(around:1200,${lat},${lng})["shop"];
      node(around:1200,${lat},${lng})["leisure"];
    );
    out body 40;
  `

  const body = `data=${encodeURIComponent(query)}`
  const payload = await requestJson(
    'https://overpass-api.de/api/interpreter',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    body,
  )

  const from = { lat, lng }
  const normalized = (payload.elements || [])
    .filter((element) => element.type === 'node' && element.tags?.name)
    .map((element) => {
      const to = { lat: Number(element.lat), lng: Number(element.lon) }
      const distance = Math.round(getDistanceMeters(from, to))
      const bearing = getBearingDegrees(from, to)
      const type = inferTypeFromTags(element.tags)
      return {
        id: `osm-node-${element.id}`,
        name: element.tags.name,
        type: type
          .split('_')
          .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
          .join(' '),
        distance,
        bearing,
        coordinates: to,
        map: getMapPosition(distance, bearing),
      }
    })
    .sort((a, b) => a.distance - b.distance)

  return normalized.slice(0, 8)
}

const callGeminiWhy = (place, interests) =>
  new Promise((resolve, reject) => {
    if (!GEMINI_API_KEY) {
      resolve(fallbackWhy(place, interests))
      return
    }

    const prompt = `You are TripSync, a smart local guide.
User interests: ${interests.join(', ') || 'General exploring'}.
Place: ${place.name} (${place.type}), ${place.distance_m} meters away.
Write ONE short recommendation sentence (max 18 words), natural and specific.`

    const payload = JSON.stringify({
      contents: [
        {
          parts: [{ text: prompt }],
        },
      ],
      generationConfig: {
        temperature: 0.8,
        maxOutputTokens: 50,
      },
    })

    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
      GEMINI_MODEL,
    )}:generateContent?key=${encodeURIComponent(GEMINI_API_KEY)}`

    const request = https.request(
      endpoint,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (response) => {
        let body = ''
        response.on('data', (chunk) => {
          body += chunk.toString()
        })
        response.on('end', () => {
          if (response.statusCode && response.statusCode >= 400) {
            reject(new Error(`Gemini error ${response.statusCode}: ${body.slice(0, 200)}`))
            return
          }

          try {
            const parsed = JSON.parse(body)
            const content = parsed?.candidates?.[0]?.content?.parts
              ?.map((part) => part?.text || '')
              .join(' ')
              .trim()
            if (!content) {
              resolve(fallbackWhy(place, interests))
              return
            }
            resolve(content)
          } catch (error) {
            reject(error)
          }
        })
      },
    )

    request.on('error', reject)
    request.write(payload)
    request.end()
  })

const ensureAiNote = async (place, interests) => {
  const profileKey = interests.slice().sort().join('|') || 'default'
  const existing = queryOne('SELECT note FROM ai_notes WHERE place_id = ? AND profile_key = ?', [
    place.id,
    profileKey,
  ])

  if (existing?.note) return existing.note

  let note = ''
  try {
    note = await callGeminiWhy(place, interests)
  } catch (error) {
    console.warn('Gemini fallback triggered:', error.message)
    note = fallbackWhy(place, interests)
  }

  runStatement(
    'INSERT OR REPLACE INTO ai_notes (place_id, profile_key, note, updated_at) VALUES (?, ?, ?, ?)',
    [place.id, profileKey, note, Date.now()],
  )
  persistDb()
  return note
}

const buildSuggestionPayload = async (sessionId, options = {}) => {
  const session = queryOne('SELECT * FROM sessions WHERE id = ?', [sessionId])
  if (!session) return null

  const interests = JSON.parse(session.interests_json)
  const liveLat = Number(options.lat)
  const liveLng = Number(options.lng)
  const hasLiveLocation = Number.isFinite(liveLat) && Number.isFinite(liveLng)

  const dbRows = queryRows(
    `
    SELECT p.*, sp.saved_at
    FROM places p
    LEFT JOIN saved_places sp
      ON sp.place_id = CAST(p.id AS TEXT) AND sp.session_id = ?
    ORDER BY p.distance_m ASC
  `,
    [sessionId],
  )

  let basePlaces = dbRows.map((row) => ({
    id: String(row.id),
    name: row.name,
    type: row.type,
    distance: Number(row.distance_m),
    bearing: Number(row.bearing_deg),
    saved: Boolean(row.saved_at),
    savedAt: row.saved_at ? formatRelative(Number(row.saved_at)) : null,
    coordinates: { lat: Number(row.lat), lng: Number(row.lng) },
    map: getMapPosition(Number(row.distance_m), Number(row.bearing_deg)),
  }))

  if (hasLiveLocation) {
    try {
      const nearbyLive = await fetchNearbyPlacesFromOverpass(liveLat, liveLng)
      if (nearbyLive.length) {
        const savedRows = queryRows(
          'SELECT place_id, saved_at FROM saved_places WHERE session_id = ?',
          [sessionId],
        )
        const savedMap = new Map(savedRows.map((row) => [String(row.place_id), Number(row.saved_at)]))

        basePlaces = nearbyLive.map((place) => {
          const savedAt = savedMap.get(place.id)
          return {
            ...place,
            saved: Boolean(savedAt),
            savedAt: savedAt ? formatRelative(savedAt) : null,
          }
        })
      }
    } catch (error) {
      console.warn('Live nearby lookup failed:', error.message)
    }
  }

  const places = await Promise.all(
    basePlaces.map(async (place) => {
      const aiWhy = await ensureAiNote(
        {
          id: place.id,
          name: place.name,
          type: place.type,
          distance_m: place.distance,
        },
        interests,
      )
      return {
        ...place,
        why: aiWhy,
      }
    }),
  )

  return {
    session: {
      id: session.id,
      interests,
      alertMode: session.alert_mode,
    },
    places,
  }
}

const resetDemo = () => {
  runStatement('DELETE FROM saved_places')
  runStatement('DELETE FROM sessions')
  runStatement('DELETE FROM ai_notes')
  persistDb()
}

const init = async () => {
  const SQL = await initSqlJs({
    locateFile: (file) => path.join(sqlJsDistPath, file),
  })

  if (fs.existsSync(dbPath)) {
    const fileBuffer = fs.readFileSync(dbPath)
    serverState.db = new SQL.Database(fileBuffer)
  } else {
    serverState.db = new SQL.Database()
  }

  ensureSchema()
  seedPlacesIfEmpty()
  persistDb()
}

const requestHandler = async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 200, { ok: true })
    return
  }

  const url = new URL(req.url || '/', `http://${req.headers.host}`)

  if (req.method === 'GET' && url.pathname === '/api/health') {
    sendJson(res, 200, {
      ok: true,
      dbPath: path.relative(projectRoot, dbPath),
      geminiConfigured: Boolean(GEMINI_API_KEY),
      geminiModel: GEMINI_MODEL,
    })
    return
  }

  if (req.method === 'POST' && url.pathname === '/api/reset') {
    resetDemo()
    sendJson(res, 200, { ok: true })
    return
  }

  if (req.method === 'POST' && url.pathname === '/api/session') {
    const body = await parseBody(req)
    const interests = Array.isArray(body.interests) ? body.interests : []
    const alertMode = body.alertMode === 'visual-only' ? 'visual-only' : 'voice-visual'
    const sessionId = randomUUID()

    runStatement(
      'INSERT INTO sessions (id, interests_json, alert_mode, created_at) VALUES (?, ?, ?, ?)',
      [sessionId, JSON.stringify(interests), alertMode, Date.now()],
    )
    persistDb()

    sendJson(res, 201, { sessionId })
    return
  }

  if (req.method === 'GET' && url.pathname === '/api/suggestions') {
    const sessionId = url.searchParams.get('sessionId')
    const lat = url.searchParams.get('lat')
    const lng = url.searchParams.get('lng')
    if (!sessionId) {
      sendJson(res, 400, { error: 'sessionId is required' })
      return
    }
    const payload = await buildSuggestionPayload(sessionId, { lat, lng })
    if (!payload) {
      sendJson(res, 404, { error: 'session not found' })
      return
    }
    sendJson(res, 200, payload)
    return
  }

  if (req.method === 'POST' && url.pathname === '/api/saved/toggle') {
    const body = await parseBody(req)
    const sessionId = body.sessionId
    const place = body.place || {}
    const placeId = String(place.id || '')

    if (!sessionId || !placeId) {
      sendJson(res, 400, { error: 'sessionId and place payload are required' })
      return
    }

    const existing = queryOne('SELECT 1 FROM saved_places WHERE session_id = ? AND place_id = ?', [
      sessionId,
      placeId,
    ])

    if (existing) {
      runStatement('DELETE FROM saved_places WHERE session_id = ? AND place_id = ?', [sessionId, placeId])
    } else {
      if (!place.name) {
        sendJson(res, 400, { error: 'place.name is required when saving a place' })
        return
      }
      runStatement(
        `INSERT INTO saved_places
        (session_id, place_id, place_name, place_type, place_description, place_lat, place_lng, saved_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          sessionId,
          placeId,
          place.name,
          place.type || 'Local Spot',
          place.why || '',
          Number(place.coordinates?.lat || 0),
          Number(place.coordinates?.lng || 0),
          Date.now(),
        ],
      )
    }

    persistDb()
    sendJson(res, 200, { saved: !existing })
    return
  }

  if (req.method === 'GET' && url.pathname === '/api/saved') {
    const sessionId = url.searchParams.get('sessionId')
    if (!sessionId) {
      sendJson(res, 400, { error: 'sessionId is required' })
      return
    }

    const saved = queryRows(
      `
      SELECT
        sp.place_id AS id,
        sp.place_name AS name,
        sp.place_type AS type,
        sp.place_description AS description,
        sp.saved_at
      FROM saved_places sp
      WHERE sp.session_id = ?
      ORDER BY sp.saved_at DESC
      `,
      [sessionId],
    ).map((row) => ({
      id: String(row.id),
      name: row.name,
      type: row.type,
      description: row.description || `${row.name} is a strong match for this walk and can be revisited later.`,
      savedAt: formatRelative(Number(row.saved_at)),
    }))

    sendJson(res, 200, { places: saved })
    return
  }

  sendJson(res, 404, { error: 'Not found' })
}

const start = async () => {
  await init()
  const server = createServer((req, res) => {
    requestHandler(req, res).catch((error) => {
      sendJson(res, 500, { error: error.message || 'Unexpected server error' })
    })
  })

  server.listen(PORT, () => {
    console.log(`TripSync API listening on http://127.0.0.1:${PORT}`)
  })
}

start().catch((error) => {
  console.error('Failed to start TripSync API', error)
  process.exit(1)
})
