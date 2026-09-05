import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { getVideo, isoDurationSeconds } from '@/lib/youtube'

const USD_MIN_CENTS = 10
const USD_MAX_CENTS = 100

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const { data: profile } = await supabase.from('users').select('is_paid,is_banned,email').eq('id', user.id).single()
    if (!profile?.is_paid || profile.is_banned) return NextResponse.json({ error: 'Active account required' }, { status: 403 })

    const idempotencyKey = request.headers.get('Idempotency-Key')?.trim() || ''
    if (idempotencyKey.length < 16 || idempotencyKey.length > 128) {
      return NextResponse.json({ error: 'A valid Idempotency-Key is required' }, { status: 400 })
    }

    const body = await request.json().catch(() => ({}))
    const video = await getVideo(String(body.video_id || ''))
    const taskTypes = Array.isArray(body.task_types) ? body.task_types.map(String) : ['discovery']
    const allowed = ['discovery', 'feedback']
    if (!taskTypes.length || !taskTypes.every((type: string) => allowed.includes(type))) {
      return NextResponse.json({ error: 'Engagement-manipulation task types are not supported. Use discovery or feedback.' }, { status: 400 })
    }

    const quantity = Math.floor(Number(body.quantity))
    const costCents = Math.round(Number(body.cost_per_task) * 100)
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 100000) return NextResponse.json({ error: 'Quantity must be between 1 and 100,000' }, { status: 400 })
    if (!Number.isInteger(costCents) || costCents < USD_MIN_CENTS || costCents > USD_MAX_CENTS) return NextResponse.json({ error: 'Cost per task must be between $0.10 and $1.00' }, { status: 400 })

    const baseCents = quantity * costCents
    const feeCents = Math.ceil(baseCents / 10)
    const totalCents = baseCents + feeCents
    const admin = createAdminClient()

    const { data: existing } = await admin.from('transactions').select('metadata,paystack_ref,status').eq('user_id', user.id).eq('idempotency_key', idempotencyKey).maybeSingle()
    if (existing) return NextResponse.json({ existing: true, reference: existing.paystack_ref, status: existing.status, metadata: existing.metadata })

    const { data: fx } = await admin.from('fx_rates').select('rate_numeric').eq('base_currency', 'USD').eq('quote_currency', 'GHS').order('effective_from', { ascending: false }).limit(1).maybeSingle()
    const rate = fx?.rate_numeric ? Number(fx.rate_numeric) : 160
    const totalGhsMinor = Math.round(totalCents * rate)
    const totalGhs = totalGhsMinor / 100

    const { data: campaign, error } = await admin.from('campaigns').insert({
      user_id: user.id,
      youtube_video_id: video.id,
      youtube_video_title: video.title,
      youtube_channel_id: video.channelId,
      thumbnail: video.thumbnail,
      duration_seconds: isoDurationSeconds(video.duration),
      task_types: taskTypes,
      required_watch_percent: 0,
      quantity,
      cost_per_task: costCents / 100,
      cost_per_task_minor: costCents,
      total_budget: baseCents / 100,
      total_budget_minor: baseCents,
      platform_fee: feeCents / 100,
      platform_fee_minor: feeCents,
      total_charge_minor: totalCents,
      promotion_mode: 'google_ads',
      policy_review_status: 'pending',
      status: 'pending_approval',
    }).select('id').single()
    if (error || !campaign) return NextResponse.json({ error: 'Unable to create campaign' }, { status: 500 })

    const reference = `VSBIL-CAMP-${campaign.id.replaceAll('-', '').slice(0, 16)}-${Date.now()}`
    const response = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: profile.email,
        amount: String(totalGhsMinor),
        currency: 'GHS',
        reference,
        callback_url: `${process.env.NEXT_PUBLIC_APP_URL}/campaigns`,
        metadata: { user_id: user.id, campaign_id: campaign.id, type: 'campaign_payment', idempotency_key: idempotencyKey },
      }),
    })
    const payload = await response.json()
    if (!response.ok || !payload.status) {
      await admin.from('campaigns').delete().eq('id', campaign.id)
      return NextResponse.json({ error: payload.message || 'Unable to initialize campaign payment' }, { status: 502 })
    }

    await admin.from('transactions').insert({
      user_id: user.id,
      type: 'campaign_payment',
      amount: totalGhs,
      amount_minor: totalGhsMinor,
      currency: 'GHS',
      paystack_ref: reference,
      status: 'pending',
      idempotency_key: idempotencyKey,
      provider: 'paystack',
      metadata: { campaign_id: campaign.id, total_usd_cents: totalCents, usd_ghs_rate: rate },
    })

    return NextResponse.json({ campaign_id: campaign.id, reference, authorization_url: payload.data.authorization_url, total_usd_cents: totalCents, total_ghs_minor: totalGhsMinor })
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Unable to create campaign' }, { status: 500 })
  }
}
