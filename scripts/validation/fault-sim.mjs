import { setTimeout as sleep } from 'node:timers/promises'
import {
  apiRequest,
  authHeaders,
  createSchedule,
  ensureZone,
  getBaseUrl,
  loginAdmin,
  summarizeLatencies,
  writeArtifacts,
} from './lib.mjs'

const TOTAL_REQUESTS = Number(process.env.VAL04_TOTAL_REQUESTS ?? '300')
const PACKET_LOSS_RATE = Number(process.env.VAL04_PACKET_LOSS_RATE ?? '0.2')
const DUPLICATE_RATE = Number(process.env.VAL04_DUPLICATE_RATE ?? '0.12')
const MIN_DELAY_MS = Number(process.env.VAL04_MIN_DELAY_MS ?? '120')
const MAX_DELAY_MS = Number(process.env.VAL04_MAX_DELAY_MS ?? '450')
const PARTITION_START = Number(process.env.VAL04_PARTITION_START ?? '120')
const PARTITION_END = Number(process.env.VAL04_PARTITION_END ?? '180')
const RECONNECT_EVERY = Number(process.env.VAL04_RECONNECT_EVERY ?? '75')

function randomBetween(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

async function main() {
  const baseUrl = getBaseUrl()
  let accessToken = await loginAdmin()
  const zoneId = await ensureZone(accessToken, 'val04-zone')
  await createSchedule(accessToken, zoneId, 'val04-schedule')

  const latencies = []
  const failures = []
  let success = 0
  let dropped = 0
  let duplicated = 0

  for (let i = 0; i < TOTAL_REQUESTS; i += 1) {
    if (i > 0 && i % RECONNECT_EVERY === 0) {
      accessToken = await loginAdmin()
    }

    // packet loss simulation
    if (Math.random() < PACKET_LOSS_RATE) {
      dropped += 1
      continue
    }

    // delay simulation
    const delay = randomBetween(MIN_DELAY_MS, MAX_DELAY_MS)
    await sleep(delay)

    const inPartition = i >= PARTITION_START && i < PARTITION_END
    const targetBaseUrl = inPartition ? 'http://127.0.0.1:9' : baseUrl

    const attempts = Math.random() < DUPLICATE_RATE ? 2 : 1
    if (attempts === 2) duplicated += 1

    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        const { elapsedMs } = await apiRequest(
          `${targetBaseUrl}/api/v1/schedules?zone_id=${encodeURIComponent(zoneId)}&page=1&page_size=20`,
          { headers: authHeaders(accessToken) }
        )
        latencies.push(elapsedMs)
        success += 1
      } catch (err) {
        failures.push(
          err instanceof Error
            ? err.message
            : String(err)
        )
      }
    }
  }

  const generatedAt = new Date().toISOString()
  const report = {
    criterion: 'VAL-04',
    generated_at: generatedAt,
    base_url: baseUrl,
    injector_profile: {
      packet_loss_rate: PACKET_LOSS_RATE,
      duplicate_rate: DUPLICATE_RATE,
      delay_ms: { min: MIN_DELAY_MS, max: MAX_DELAY_MS },
      reconnect_every_requests: RECONNECT_EVERY,
      temporary_partition: { from_index: PARTITION_START, to_index: PARTITION_END },
    },
    totals: {
      planned_requests: TOTAL_REQUESTS,
      dropped,
      duplicated_events: duplicated,
      sent_requests: success + failures.length,
      success,
      failures: failures.length,
      success_rate: (success / Math.max(1, success + failures.length)) * 100,
    },
    latency: summarizeLatencies(latencies),
    failure_samples: failures.slice(0, 20),
    notes: [
      'Faults are injected at client/request level (delay, drop, duplicate, reconnect, temporary partition).',
      'For network-layer realism, replace with tc/netem or Toxiproxy in a Linux CI runner.',
    ],
  }

  const markdown = [
    '# VAL-04 Fault Simulation Report',
    '',
    `Generated at: ${generatedAt}`,
    `Base URL: ${baseUrl}`,
    '',
    'Injected fault profile:',
    `- Packet loss rate: ${PACKET_LOSS_RATE}`,
    `- Duplicate rate: ${DUPLICATE_RATE}`,
    `- Delay range: ${MIN_DELAY_MS}-${MAX_DELAY_MS} ms`,
    `- Reconnect every: ${RECONNECT_EVERY} requests`,
    `- Temporary partition window: [${PARTITION_START}, ${PARTITION_END})`,
    '',
    `Success rate: ${report.totals.success_rate.toFixed(2)}%`,
    `Latency p95: ${report.latency.p95_ms.toFixed(2)} ms`,
    '',
    'Note: this is an equivalent fault injector at client level; network-layer netem/toxiproxy remains a future upgrade.',
  ].join('\n')

  const stamp = generatedAt.slice(0, 19).replace(/[:T]/g, '-')
  const { jsonPath, mdPath } = await writeArtifacts(`val04-fault-${stamp}`, report, markdown)
  console.log(`[val04] JSON: ${jsonPath}`)
  console.log(`[val04] MD: ${mdPath}`)
}

main().catch((err) => {
  console.error('[val04] failed:', err)
  process.exit(1)
})

