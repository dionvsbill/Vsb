import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { enforceRateLimit } from '@/lib/rate-limit'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const limited = await enforceRateLimit(`task-heartbeat:user:${user.id}`)
    if (!limited.success) return NextResponse.json({ error: 'Too many heartbeat requests' }, { status: 429 })
    const body = await request.json().catch(() => ({}))
    const sessionId = typeof body.session_id === 'string' ? body.session_id : ''
    const playbackSeconds = Number(body.playback_seconds)
    const visibility = typeof body.visibility_state === 'string' ? body.visibility_state : ''
    const playbackRate = Number(body.playback_rate ?? 1)
    const seekDetected = Boolean(body.seek_detected)
    const mouseActivity = Boolean(body.mouse_activity)
    if (!sessionId || !Number.isFinite(playbackSeconds) || playbackSeconds < 0 || playbackSeconds > 86400 || !['visible', 'hidden', 'prerender', 'unloaded'].includes(visibility) || !Number.isFinite(playbackRate) || playbackRate <= 0 || playbackRate > 4) return NextResponse.json({ error: 'Invalid heartbeat' }, { status: 400 })
    const admin = createAdminClient()
    const { data: session } = await admin.from('task_sessions').select('id,worker_id,status').eq('id', sessionId).single()
    if (!session || session.worker_id !== user.id) return NextResponse.json({ error: 'Session not found' }, { status: 404 })
    const { data, error } = await admin.rpc('record_task_heartbeat', { p_session_id: sessionId, p_client_time_seconds: playbackSeconds, p_visibility_state: visibility, p_playback_rate: playbackRate, p_seek_detected: seekDetected, p_mouse_activity: mouseActivity })
    if (error) { const msg=String(error.message||'Heartbeat rejected'); const status=/EXPIRED|INACTIVE|FREQUENT|NOT_ACTIVE/.test(msg)?409:500; return NextResponse.json({ error: msg }, { status }) }
    return NextResponse.json(data)
  } catch { return NextResponse.json({ error: 'Unable to record heartbeat' }, { status: 500 }) }
}
