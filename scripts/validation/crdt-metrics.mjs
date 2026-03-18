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

const SLOT_BATCHES = [20, 100, 300]
const OPS_SAMPLES = Number(process.env.VAL05_OPS_SAMPLES ?? '50')

function buildSlots({ count, zoneId, baseTs }) {
  return Array.from({ length: count }, (_, index) => {
    const start = new Date(baseTs + index * 60000)
    const end = new Date(start.getTime() + 45000)
    return {
      asset_id: `val05-asset-${index}`,
      start_time: start.toISOString(),
      end_time: end.toISOString(),
      priority: index % 10,
      zone_id: zoneId,
      group_id: 'val05-group',
    }
  })
}

async function main() {
  const baseUrl = getBaseUrl()
  const accessToken = await loginAdmin()
  const zoneId = await ensureZone(accessToken, 'val05-zone')
  const scheduleId = await createSchedule(accessToken, zoneId, 'val05-schedule')

  const mergeMeasurements = []

  const lock = await apiRequest(`${baseUrl}/api/v1/schedules/${scheduleId}/lock`, {
    method: 'POST',
    headers: authHeaders(accessToken),
    body: { ttl_seconds: 180 },
  })
  const lockToken = lock.payload?.lock_token
  if (!lockToken) {
    throw new Error('Failed to acquire lock for VAL-05 metrics')
  }

  try {
    for (const count of SLOT_BATCHES) {
      const slots = buildSlots({
        count,
        zoneId,
        baseTs: Date.now() + 3_600_000,
      })
      const body = { lock_token: lockToken, slots }
      const payloadBytes = Buffer.byteLength(JSON.stringify(body), 'utf-8')
      const { elapsedMs, bytes } = await apiRequest(
        `${baseUrl}/api/v1/schedules/${scheduleId}/save`,
        {
          method: 'POST',
          headers: authHeaders(accessToken),
          body,
        }
      )
      mergeMeasurements.push({
        slot_count: count,
        merge_time_ms: elapsedMs,
        request_payload_bytes: payloadBytes,
        response_bytes: bytes,
      })
    }
  } finally {
    await apiRequest(`${baseUrl}/api/v1/schedules/${scheduleId}/lock`, {
      method: 'DELETE',
      headers: authHeaders(accessToken),
      body: { lock_token: lockToken },
    }).catch(() => {})
  }

  const opsLatencies = []
  const opsPayloadBytes = []
  let accepted = 0
  let rejected = 0
  const rejectReasons = new Map()

  for (let i = 0; i < OPS_SAMPLES; i += 1) {
    const opBody = {
      ops: [
        {
          op_type: 'add_slot',
          causal: {
            operation_id: `val05-op-${Date.now()}-${i}`,
            client_id: 'val05-metrics',
            lamport_ts: i + 1,
          },
          slot: {
            slot_id: `val05-slot-${i}`,
            asset_id: `val05-asset-${i}`,
            start_time: new Date(Date.now() + i * 60000).toISOString(),
            end_time: new Date(Date.now() + i * 60000 + 45000).toISOString(),
            priority: i % 5,
            zone_id: zoneId,
            group_id: 'val05-group',
          },
        },
      ],
    }
    const payloadBytes = Buffer.byteLength(JSON.stringify(opBody), 'utf-8')
    opsPayloadBytes.push(payloadBytes)

    try {
      const { payload, elapsedMs, bytes } = await apiRequest(
        `${baseUrl}/api/v1/schedules/${scheduleId}/ops`,
        {
          method: 'POST',
          headers: authHeaders(accessToken),
          body: opBody,
        }
      )
      opsLatencies.push(elapsedMs)

      const row = payload?.results?.[0]
      if (row?.accepted) {
        accepted += 1
      } else {
        rejected += 1
        const reason = row?.reason ?? 'unknown'
        rejectReasons.set(reason, (rejectReasons.get(reason) ?? 0) + 1)
      }

      // Include response payload size in latency/cost analysis
      opsPayloadBytes.push(bytes)
    } catch (err) {
      rejected += 1
      const reason = err instanceof Error ? err.message : String(err)
      rejectReasons.set(reason, (rejectReasons.get(reason) ?? 0) + 1)
    }
  }

  const mergeLatencies = mergeMeasurements.map((m) => m.merge_time_ms)
  const syncSummary = summarizeLatencies(opsLatencies)
  const mergeSummary = summarizeLatencies(mergeLatencies)
  const conflictRate = (rejected / Math.max(1, accepted + rejected)) * 100
  const reasonList = Array.from(rejectReasons.entries()).map(([reason, count]) => ({ reason, count }))
  const signatureBlocked = reasonList.some((item) => item.reason.includes('missing_signature'))

  const generatedAt = new Date().toISOString()
  const report = {
    criterion: 'VAL-05',
    generated_at: generatedAt,
    base_url: baseUrl,
    schedule_id: scheduleId,
    merge_time: {
      summary: mergeSummary,
      per_batch: mergeMeasurements,
    },
    sync_latency: {
      summary: syncSummary,
      samples: opsLatencies.length,
    },
    payload_size: {
      avg_bytes: opsPayloadBytes.reduce((acc, value) => acc + value, 0) / Math.max(1, opsPayloadBytes.length),
      max_bytes: Math.max(0, ...opsPayloadBytes),
      min_bytes: Math.min(...opsPayloadBytes),
    },
    conflict_rate_percent: conflictRate,
    reject_reasons: reasonList,
    limitation: signatureBlocked
      ? 'Sync ops endpoint enforces signatures in this environment; conflict-rate reflects signature rejects.'
      : null,
  }

  const markdown = [
    '# VAL-05 Sync/Merge Metrics',
    '',
    `Generated at: ${generatedAt}`,
    `Base URL: ${baseUrl}`,
    `Schedule ID: ${scheduleId}`,
    '',
    `Merge time p95: ${mergeSummary.p95_ms.toFixed(2)} ms`,
    `Sync latency p95: ${syncSummary.p95_ms.toFixed(2)} ms`,
    `Payload avg: ${report.payload_size.avg_bytes.toFixed(2)} bytes`,
    `Conflict/reject rate: ${conflictRate.toFixed(2)}%`,
    '',
    'Top reject reasons:',
    ...reasonList.map((item) => `- ${item.reason}: ${item.count}`),
    '',
    signatureBlocked
      ? 'Limitation: ops path currently requires signatures, so conflict metrics are constrained by signature enforcement.'
      : 'Ops path accepted unsigned requests in this environment.',
  ].join('\n')

  const stamp = generatedAt.slice(0, 19).replace(/[:T]/g, '-')
  const { jsonPath, mdPath } = await writeArtifacts(`val05-metrics-${stamp}`, report, markdown)
  console.log(`[val05] JSON: ${jsonPath}`)
  console.log(`[val05] MD: ${mdPath}`)
}

main().catch((err) => {
  console.error('[val05] failed:', err)
  process.exit(1)
})

