import { NextResponse } from 'next/server'
import { createHash } from 'node:crypto'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = await request.json().catch(() => ({}))
    const taskId = typeof body.task_id === 'string' ? body.task_id : ''
    const sessionId = typeof body.session_id === 'string' ? body.session_id : ''
    const nonce = typeof body.session_nonce === 'string' ? body.session_nonce : ''
    if (!taskId || !sessionId || nonce.length < 32) return NextResponse.json({ error: 'Task session is required' }, { status: 400 })

    const admin = createAdminClient()
    const { data, error } = await admin.rpc('submit_discovery_task', {
      p_task_id: taskId,
      p_session_id: sessionId,
      p_worker_id: user.id,
      p_nonce_hash: createHash('sha256').update(nonce).digest('hex'),
    })
    if (error) {
      const msg = String(error.message || 'Unable to submit task')
      const status = /NOT_FOUND|SESSION|NONCE|PLAYBACK|ABNORMAL|UNAVAILABLE|STALE|EXPIRED|SUBMITTABLE/.test(msg) ? 409 : 500
      return NextResponse.json({ error: msg }, { status })
    }
    return NextResponse.json(data ?? { submitted: true })
  } catch {
    return NextResponse.json({ error: 'Unable to submit task' }, { status: 500 })
  }
}
