import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { performance } from 'node:perf_hooks'

const THIS_DIR = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(THIS_DIR, '..', '..')
export const ARTIFACT_DIR = join(REPO_ROOT, 'artifacts', 'validation')

export function envOrThrow(name) {
  const value = process.env[name]
  if (!value) {
    throw new Error(`Missing required env var: ${name}`)
  }
  return value
}

export function getBaseUrl() {
  return process.env.BASE_URL ?? 'http://localhost:3000'
}

export function authHeaders(accessToken) {
  return {
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  }
}

export async function apiRequest(url, { method = 'GET', headers = {}, body } = {}) {
  const started = performance.now()
  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await response.text()
  const elapsedMs = performance.now() - started

  let payload = null
  if (text.length > 0) {
    try {
      payload = JSON.parse(text)
    } catch {
      payload = { raw: text }
    }
  }

  if (!response.ok) {
    const error = new Error(`HTTP ${response.status} for ${method} ${url}`)
    error.status = response.status
    error.payload = payload
    error.elapsedMs = elapsedMs
    throw error
  }

  return { payload, elapsedMs, status: response.status, bytes: text.length }
}

export async function loginAdmin() {
  const baseUrl = getBaseUrl()
  const email = envOrThrow('AUTH_BOOTSTRAP_ADMIN_EMAIL')
  const password = envOrThrow('AUTH_BOOTSTRAP_ADMIN_PASSWORD')
  const { payload } = await apiRequest(`${baseUrl}/api/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: { email, password },
  })
  if (!payload?.access_token) {
    throw new Error('Login response missing access_token')
  }
  return payload.access_token
}

export async function ensureZone(accessToken, zoneNamePrefix = 'validation-zone') {
  const baseUrl = getBaseUrl()
  const list = await apiRequest(`${baseUrl}/api/v1/zones?page=1&page_size=20`, {
    headers: authHeaders(accessToken),
  })

  const zone = list.payload?.data?.[0]
  if (zone?.zone_id) {
    return zone.zone_id
  }

  const name = `${zoneNamePrefix}-${Date.now()}`
  const created = await apiRequest(`${baseUrl}/api/v1/zones`, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: { name, description: 'validation' },
  })
  if (!created.payload?.zone_id) {
    throw new Error('Failed to create zone for validation scripts')
  }
  return created.payload.zone_id
}

export async function createSchedule(accessToken, zoneId, namePrefix = 'validation-schedule') {
  const baseUrl = getBaseUrl()
  const created = await apiRequest(`${baseUrl}/api/v1/schedules`, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: {
      zone_id: zoneId,
      name: `${namePrefix}-${Date.now()}`,
    },
  })
  if (!created.payload?.schedule_id) {
    throw new Error('Failed to create schedule for validation scripts')
  }
  return created.payload.schedule_id
}

export function quantile(sortedValues, p) {
  if (!sortedValues.length) return 0
  const idx = Math.min(sortedValues.length - 1, Math.max(0, Math.floor(p * (sortedValues.length - 1))))
  return sortedValues[idx]
}

export function summarizeLatencies(samples) {
  const sorted = [...samples].sort((a, b) => a - b)
  const count = sorted.length
  const sum = sorted.reduce((acc, value) => acc + value, 0)
  return {
    count,
    min_ms: count ? sorted[0] : 0,
    max_ms: count ? sorted[count - 1] : 0,
    avg_ms: count ? sum / count : 0,
    p50_ms: quantile(sorted, 0.5),
    p95_ms: quantile(sorted, 0.95),
    p99_ms: quantile(sorted, 0.99),
  }
}

export async function writeArtifacts(name, json, markdown) {
  await mkdir(ARTIFACT_DIR, { recursive: true })
  const jsonPath = join(ARTIFACT_DIR, `${name}.json`)
  const mdPath = join(ARTIFACT_DIR, `${name}.md`)
  await writeFile(jsonPath, JSON.stringify(json, null, 2), 'utf-8')
  await writeFile(mdPath, markdown, 'utf-8')
  return { jsonPath, mdPath }
}

