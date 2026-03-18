import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'
import { ARTIFACT_DIR, getBaseUrl, loginAdmin, writeArtifacts } from './lib.mjs'

async function latestByPrefix(prefix) {
  const files = await readdir(ARTIFACT_DIR).catch(() => [])
  const matched = files
    .filter((name) => name.startsWith(prefix) && name.endsWith('.json'))
    .sort()
  if (!matched.length) return null
  return join(ARTIFACT_DIR, matched[matched.length - 1])
}

async function readJson(filePath) {
  if (!filePath) return null
  const raw = await readFile(filePath, 'utf-8')
  return JSON.parse(raw)
}

async function main() {
  // Ensure credentials are valid before producing a "ready" pack
  await loginAdmin()

  const val03Path = await latestByPrefix('val03-load-')
  const val04Path = await latestByPrefix('val04-fault-')
  const val05Path = await latestByPrefix('val05-metrics-')
  const val03 = await readJson(val03Path)
  const val04 = await readJson(val04Path)
  const val05 = await readJson(val05Path)

  const generatedAt = new Date().toISOString()
  const report = {
    criterion: 'VAL-08',
    generated_at: generatedAt,
    base_url: getBaseUrl(),
    artifacts: {
      val03: val03Path ? basename(val03Path) : null,
      val04: val04Path ? basename(val04Path) : null,
      val05: val05Path ? basename(val05Path) : null,
    },
    kpi_snapshot: {
      val03_p95_ms_1000_clients:
        val03?.scenarios?.find((s) => s.clients === 1000)?.latency?.p95_ms ?? null,
      val04_success_rate_percent: val04?.totals?.success_rate ?? null,
      val05_merge_p95_ms: val05?.merge_time?.summary?.p95_ms ?? null,
      val05_sync_p95_ms: val05?.sync_latency?.summary?.p95_ms ?? null,
      val05_conflict_rate_percent: val05?.conflict_rate_percent ?? null,
    },
    limitations: [
      val04
        ? 'VAL-04 currently uses client-side fault injection; tc/netem/toxiproxy is recommended for network-layer fidelity.'
        : 'VAL-04 artifact missing.',
      val05?.limitation ?? null,
    ].filter(Boolean),
  }

  const markdown = [
    '# VAL-08 Thesis Validation Pack',
    '',
    `Generated at: ${generatedAt}`,
    `Base URL: ${getBaseUrl()}`,
    '',
    '## Demo Scenarios',
    '1. Runtime foundation: `make ci-iam-runtime` (smoke + IAM e2e).',
    '2. Load profile (VAL-03): `make val03`.',
    '3. Fault simulation (VAL-04): `make val04`.',
    '4. Sync/merge metrics (VAL-05): `make val05`.',
    '',
    '## Artifact Map',
    `- VAL-03: ${val03Path ? basename(val03Path) : 'missing'}`,
    `- VAL-04: ${val04Path ? basename(val04Path) : 'missing'}`,
    `- VAL-05: ${val05Path ? basename(val05Path) : 'missing'}`,
    '',
    '## Criteria Coverage',
    '- Bootstrap/init/login/cookie/users/roles/RBAC/password/MFA/audit/schedule: `scripts/e2e-iam.sh` + `scripts/smoke-bootstrap.sh`.',
    '- VAL-03 load scaling: `scripts/validation/load-test.mjs`.',
    '- VAL-04 faults (loss/delay/duplicate/reconnect/partition equivalent): `scripts/validation/fault-sim.mjs`.',
    '- VAL-05 merge/sync/payload/conflict metrics: `scripts/validation/crdt-metrics.mjs`.',
    '',
    '## KPI Snapshot',
    `- VAL-03 p95 (1000 clients): ${report.kpi_snapshot.val03_p95_ms_1000_clients ?? 'n/a'} ms`,
    `- VAL-04 success rate: ${report.kpi_snapshot.val04_success_rate_percent ?? 'n/a'} %`,
    `- VAL-05 merge p95: ${report.kpi_snapshot.val05_merge_p95_ms ?? 'n/a'} ms`,
    `- VAL-05 sync p95: ${report.kpi_snapshot.val05_sync_p95_ms ?? 'n/a'} ms`,
    `- VAL-05 conflict/reject rate: ${report.kpi_snapshot.val05_conflict_rate_percent ?? 'n/a'} %`,
    '',
    '## Remaining Limitations',
    ...report.limitations.map((item) => `- ${item}`),
  ].join('\n')

  const stamp = generatedAt.slice(0, 19).replace(/[:T]/g, '-')
  const { jsonPath, mdPath } = await writeArtifacts(`val08-pack-${stamp}`, report, markdown)
  console.log(`[val08] JSON: ${jsonPath}`)
  console.log(`[val08] MD: ${mdPath}`)
}

main().catch((err) => {
  console.error('[val08] failed:', err)
  process.exit(1)
})

