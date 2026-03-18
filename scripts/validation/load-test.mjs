import { performance } from 'node:perf_hooks'
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

const SCENARIOS = [100, 500, 1000]
const REQUESTS_PER_CLIENT = Number(process.env.VAL03_REQUESTS_PER_CLIENT ?? '3')

async function runScenario({ accessToken, zoneId, clients }) {
  const baseUrl = getBaseUrl()
  const latencies = []
  let success = 0
  let failures = 0
  const failureReasons = new Map()

  const started = performance.now()
  await Promise.all(
    Array.from({ length: clients }, () =>
      (async () => {
        for (let i = 0; i < REQUESTS_PER_CLIENT; i += 1) {
          try {
            const { elapsedMs } = await apiRequest(
              `${baseUrl}/api/v1/schedules?zone_id=${encodeURIComponent(zoneId)}&page=1&page_size=20`,
              { headers: authHeaders(accessToken) }
            )
            latencies.push(elapsedMs)
            success += 1
          } catch (err) {
            failures += 1
            const reason = err?.status
              ? `HTTP_${err.status}`
              : err instanceof Error
                ? err.message
                : String(err)
            failureReasons.set(reason, (failureReasons.get(reason) ?? 0) + 1)
          }
        }
      })()
    )
  )
  const elapsedSec = (performance.now() - started) / 1000

  return {
    clients,
    requests_per_client: REQUESTS_PER_CLIENT,
    total_requests: clients * REQUESTS_PER_CLIENT,
    success,
    failures,
    success_rate: (success / Math.max(1, success + failures)) * 100,
    throughput_rps: success / Math.max(0.001, elapsedSec),
    latency: summarizeLatencies(latencies),
    failure_reasons: Array.from(failureReasons.entries()).map(([reason, count]) => ({
      reason,
      count,
    })),
  }
}

async function main() {
  const accessToken = await loginAdmin()
  const zoneId = await ensureZone(accessToken, 'val03-zone')
  await createSchedule(accessToken, zoneId, 'val03-schedule')

  const scenarios = []
  for (const clients of SCENARIOS) {
    const result = await runScenario({ accessToken, zoneId, clients })
    scenarios.push(result)
  }

  const generatedAt = new Date().toISOString()
  const report = {
    criterion: 'VAL-03',
    generated_at: generatedAt,
    base_url: getBaseUrl(),
    scenario: 'GET /api/v1/schedules load',
    scenarios,
    notes: [
      'Synthetic HTTP load from a single host process (concurrent virtual clients).',
      'Useful for reproducible relative comparison (100/500/1000) on the same environment.',
    ],
  }

  const markdown = [
    '# VAL-03 Load Test Report',
    '',
    `Generated at: ${generatedAt}`,
    `Base URL: ${getBaseUrl()}`,
    '',
    '| Clients | Total req | Success | Failures | Success % | Throughput (rps) | p95 (ms) |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: |',
    ...scenarios.map((row) =>
      `| ${row.clients} | ${row.total_requests} | ${row.success} | ${row.failures} | ${row.success_rate.toFixed(2)} | ${row.throughput_rps.toFixed(2)} | ${row.latency.p95_ms.toFixed(2)} |`
    ),
    '',
    'Notes:',
    '- Synthetic concurrent clients run from one process.',
    '- Use together with infra metrics (Prometheus/Grafana) for deeper bottleneck analysis.',
    '',
    ...scenarios.map((row) => {
      const topFailure = row.failure_reasons[0]
      return `- ${row.clients} clients top failure: ${topFailure ? `${topFailure.reason} (${topFailure.count})` : 'none'}`
    }),
  ].join('\n')

  const stamp = generatedAt.slice(0, 19).replace(/[:T]/g, '-')
  const { jsonPath, mdPath } = await writeArtifacts(`val03-load-${stamp}`, report, markdown)
  console.log(`[val03] JSON: ${jsonPath}`)
  console.log(`[val03] MD: ${mdPath}`)
}

main().catch((err) => {
  console.error('[val03] failed:', err)
  process.exit(1)
})
