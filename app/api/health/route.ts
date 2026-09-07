import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'

export const dynamic = 'force-dynamic'

const required = [
  'NEXT_PUBLIC_APP_URL',
  'NEXT_PUBLIC_SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'PAYSTACK_SECRET_KEY',
  'PAYSTACK_WEBHOOK_SECRET',
  'ENCRYPTION_KEY',
  'CRON_SECRET',
] as const

export async function GET() {
  const missing = required.filter((name) => !process.env[name])
  if (missing.length) {
    return NextResponse.json({ status: 'degraded', checks: { configuration: 'failed', database: 'not_checked' }, missing }, { status: 503 })
  }

  try {
    const admin = createAdminClient()
    const started = Date.now()
    const { error } = await admin.from('platform_settings').select('id').eq('id', true).maybeSingle()
    if (error) throw error
    return NextResponse.json({
      status: 'ok',
      checks: { configuration: 'ok', database: 'ok' },
      latency_ms: Date.now() - started,
      timestamp: new Date().toISOString(),
    }, { headers: { 'Cache-Control': 'no-store' } })
  } catch {
    return NextResponse.json({ status: 'degraded', checks: { configuration: 'ok', database: 'failed' }, timestamp: new Date().toISOString() }, { status: 503, headers: { 'Cache-Control': 'no-store' } })
  }
}
