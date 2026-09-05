import { NextResponse } from 'next/server'
import { createHash } from 'node:crypto'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { enforceRateLimit } from '@/lib/rate-limit'

export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const body = await request.json().catch(() => ({}))
  const visitorId = typeof body.visitor_id === 'string' ? body.visitor_id.trim() : ''
  if (visitorId.length < 10 || visitorId.length > 256) return NextResponse.json({ error: 'Invalid device identifier' }, { status: 400 })
  const limited = await enforceRateLimit(`device:${user.id}`, 10, '1 h')
  if (!limited.success) return NextResponse.json({ error: 'Too many device registrations' }, { status: 429 })
  const hash = createHash('sha256').update(visitorId).digest('hex')
  const admin = createAdminClient()
  const { data: owner } = await admin.from('users').select('id,device_fingerprint,is_banned').eq('device_fingerprint', visitorId).neq('id', user.id).maybeSingle()
  if (owner) return NextResponse.json({ error: 'This device is already associated with another account' }, { status: 409 })
  const { error } = await admin.from('device_registrations').upsert({ user_id: user.id, visitor_id_hash: hash, last_ip: request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null, last_seen_at: new Date().toISOString() }, { onConflict: 'user_id,visitor_id_hash' })
  if (error) return NextResponse.json({ error: 'Unable to register device' }, { status: 500 })
  return NextResponse.json({ registered: true, banned: Boolean(owner?.is_banned) })
}
