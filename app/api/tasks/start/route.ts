import { NextResponse } from 'next/server'
import { createHash, randomBytes } from 'node:crypto'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const body = await request.json().catch(() => ({}))
    const campaignId = typeof body.campaign_id === 'string' ? body.campaign_id : ''
    const fingerprint = typeof body.device_fingerprint === 'string' ? body.device_fingerprint.trim() : ''
    if (!campaignId || fingerprint.length < 10 || fingerprint.length > 256) {
      return NextResponse.json({ error: 'Invalid task request' }, { status: 400 })
    }

    const { data: profile } = await supabase
      .from('users')
      .select('is_paid,is_banned,device_fingerprint')
      .eq('id', user.id)
      .single()
    if (!profile?.is_paid || profile.is_banned) {
      return NextResponse.json({ error: 'Active account required' }, { status: 403 })
    }
    if (profile.device_fingerprint && profile.device_fingerprint !== fingerprint) {
      return NextResponse.json({ error: 'Device verification failed' }, { status: 403 })
    }

    const admin = createAdminClient()
    if (!profile.device_fingerprint) {
      const { error } = await admin.from('users').update({ device_fingerprint: fingerprint }).eq('id', user.id)
      if (error) return NextResponse.json({ error: 'Unable to bind device' }, { status: 500 })
    }

    const { data: campaign } = await admin
      .from('campaigns')
      .select('id,user_id,status,quantity,completed_count,task_types,policy_review_status')
      .eq('id', campaignId)
      .single()

    if (!campaign || campaign.user_id === user.id || !['approved', 'active'].includes(String(campaign.status))) {
      return NextResponse.json({ error: 'Campaign unavailable' }, { status: 409 })
    }

    const taskTypes = Array.isArray(campaign.task_types) ? campaign.task_types.map(String) : []
    const compliant = taskTypes.length > 0 && taskTypes.every((type) => ['discovery', 'feedback'].includes(type))
    if (!compliant || campaign.policy_review_status !== 'approved') {
      return NextResponse.json({ error: 'This campaign is not eligible for discovery tasks' }, { status: 409 })
    }

    const nonce = randomBytes(32).toString('hex')
    const nonceHash = createHash('sha256').update(nonce).digest('hex')
    const { data, error } = await admin.rpc('start_discovery_task', {
      p_campaign_id: campaignId,
      p_worker_id: user.id,
      p_device_fingerprint: fingerprint,
      p_nonce_hash: nonceHash,
      p_session_ttl_seconds: 1800,
    })

    if (error) {
      const known = String(error.message || '')
      const status = known.includes('ALREADY') || known.includes('UNAVAILABLE') || known.includes('COMPLETE') ? 409 : 500
      return NextResponse.json({ error: known || 'Unable to assign task' }, { status })
    }

    return NextResponse.json({ ...data, session_nonce: nonce })
  } catch {
    return NextResponse.json({ error: 'Unable to start task' }, { status: 500 })
  }
}
