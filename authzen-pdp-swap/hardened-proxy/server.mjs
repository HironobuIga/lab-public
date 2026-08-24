// The contrib authzen-proxy, plus exactly enough to close the gaps against a
// native implementation (Keycloak). Written to measure what it actually takes to
// use an adapter for real. Zero dependencies (node standard library only).
//
// Differences from the contrib version:
//   1. Input validation — reject missing REQUIRED fields with 400
//   2. Authentication  — verify the Bearer token via Keycloak introspection, 401 if invalid
//   3. Discovery       — /.well-known/authzen-configuration
//   4. Batch           — /access/v1/evaluations (top-level defaults, per-item overrides)
//
// The decision itself is the same as the contrib version: the request is passed
// straight through as OPA's input.

import { createServer } from 'node:http'

const PORT = Number(process.env.PORT || 3000)
const OPA_URL = process.env.OPA_URL || 'http://localhost:8181'
const OPA_POLICY_PATH = process.env.OPA_POLICY_PATH || 'authzen/allow'
const PUBLIC_URL = process.env.PUBLIC_URL || `http://localhost:${PORT}`
// Where tokens get verified. Unset means no authentication (same as the contrib version).
const INTROSPECT_URL = process.env.INTROSPECT_URL || ''
const INTROSPECT_CLIENT_ID = process.env.INTROSPECT_CLIENT_ID || ''
const INTROSPECT_CLIENT_SECRET = process.env.INTROSPECT_CLIENT_SECRET || ''

const json = (res, code, body, reqId) => {
  const payload = JSON.stringify(body)
  const headers = { 'content-type': 'application/json' }
  if (reqId) headers['x-request-id'] = reqId
  res.writeHead(code, headers).end(payload)
}

// --- 1. Input validation: are the spec's REQUIRED fields present?
function validate(ev) {
  const missing = []
  if (!ev || typeof ev !== 'object') return ['body']
  for (const [path, v] of [
    ['subject.type', ev.subject?.type],
    ['subject.id', ev.subject?.id],
    ['action.name', ev.action?.name],
    ['resource.type', ev.resource?.type],
    ['resource.id', ev.resource?.id],
  ]) {
    if (typeof v !== 'string' || v === '') missing.push(path)
  }
  return missing
}

// --- 2. Authentication: verify the token by introspection
async function authenticate(req) {
  if (!INTROSPECT_URL) return { ok: true, skipped: true }
  const auth = req.headers['authorization'] || ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!token) return { ok: false }
  try {
    const body = new URLSearchParams({
      token,
      client_id: INTROSPECT_CLIENT_ID,
      client_secret: INTROSPECT_CLIENT_SECRET,
    })
    const r = await fetch(INTROSPECT_URL, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body,
    })
    if (!r.ok) return { ok: false }
    const data = await r.json()
    return { ok: data.active === true }
  } catch {
    return { ok: false }
  }
}

// The decision itself. Like the contrib version, the request goes through as input.
async function decide(ev) {
  const r = await fetch(`${OPA_URL}/v1/data/${OPA_POLICY_PATH}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ input: ev }),
  })
  if (!r.ok) throw new Error(`OPA returned ${r.status}`)
  const data = await r.json()
  return data.result ?? { decision: false }
}

// --- 4. Batch: top level supplies the defaults, the array overrides them
function expand(body) {
  const base = {
    subject: body.subject,
    action: body.action,
    resource: body.resource,
    context: body.context,
  }
  const items = Array.isArray(body.evaluations) && body.evaluations.length ? body.evaluations : [{}]
  return items.map((it) => ({
    subject: it.subject ?? base.subject,
    action: it.action ?? base.action,
    resource: it.resource ?? base.resource,
    ...((it.context ?? base.context) ? { context: it.context ?? base.context } : {}),
  }))
}

const readBody = (req) =>
  new Promise((resolve, reject) => {
    let raw = ''
    req.on('data', (c) => {
      raw += c
      if (raw.length > 1_000_000) reject(new Error('body too large'))
    })
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {})
      } catch {
        reject(new Error('invalid json'))
      }
    })
    req.on('error', reject)
  })

const server = createServer(async (req, res) => {
  const reqId = req.headers['x-request-id']
  const path = (req.url || '').split('?')[0]

  // --- 3. Discovery
  if (req.method === 'GET' && path === '/.well-known/authzen-configuration') {
    return json(res, 200, {
      policy_decision_point: PUBLIC_URL,
      access_evaluation_endpoint: `${PUBLIC_URL}/access/v1/evaluation`,
      access_evaluations_endpoint: `${PUBLIC_URL}/access/v1/evaluations`,
    }, reqId)
  }
  if (req.method === 'GET' && path === '/health') {
    return json(res, 200, { status: 'healthy' }, reqId)
  }

  const isSingle = path === '/access/v1/evaluation'
  const isBatch = path === '/access/v1/evaluations'
  if (!isSingle && !isBatch) return json(res, 404, { error: 'not_found' }, reqId)
  if (req.method !== 'POST') return json(res, 405, { error: 'method_not_allowed' }, reqId)

  const auth = await authenticate(req)
  if (!auth.ok) return json(res, 401, { error: 'unauthorized' }, reqId)

  let body
  try {
    body = await readBody(req)
  } catch (e) {
    return json(res, 400, { error: 'invalid_request', error_description: e.message }, reqId)
  }

  try {
    const items = isBatch ? expand(body) : [body]
    for (const it of items) {
      const missing = validate(it)
      if (missing.length) {
        return json(res, 400, {
          error: 'invalid_request',
          error_description: `missing required field(s): ${missing.join(', ')}`,
        }, reqId)
      }
    }
    const decisions = await Promise.all(items.map(decide))
    return json(res, 200, isBatch ? { evaluations: decisions } : decisions[0], reqId)
  } catch (e) {
    return json(res, 502, { error: 'pdp_unavailable', error_description: e.message }, reqId)
  }
})

server.listen(PORT, () => {
  console.log(`hardened authzen proxy on ${PORT} -> ${OPA_URL}/v1/data/${OPA_POLICY_PATH}`)
  console.log(`auth: ${INTROSPECT_URL ? 'introspection' : 'DISABLED'}`)
})
