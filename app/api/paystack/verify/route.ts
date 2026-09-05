import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const { reference } = await request.json()
    if (typeof reference !== 'string' || !/^[-.=a-zA-Z0-9]+$/.test(reference)) return NextResponse.json({ error: 'Invalid reference' }, { status: 400 })
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const admin = createAdminClient()
    const { data: tx } = await admin.from('transactions').select('id,user_id,amount_minor,currency,status,type,metadata').eq('paystack_ref', reference).single()
    if (!tx || tx.user_id !== user.id) return NextResponse.json({ error: 'Payment not found' }, { status: 404 })
    if (tx.status === 'success') return NextResponse.json({ success: true, alreadyProcessed: true })
    if (!Number.isSafeInteger(Number(tx.amount_minor)) || Number(tx.amount_minor) <= 0 || tx.currency !== 'GHS') return NextResponse.json({ error: 'Payment configuration is invalid' }, { status: 500 })

    const response = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, { headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}` } })
    const payload = await response.json().catch(() => ({}))
    if (!response.ok || !payload.status) return NextResponse.json({ error: 'Payment verification failed' }, { status: 502 })
    if (payload.data?.status !== 'success') {
      await admin.from('transactions').update({ status: 'failed', metadata: { ...(tx.metadata && typeof tx.metadata === 'object' ? tx.metadata : {}), provider_status: payload.data?.status || 'unknown' } }).eq('id', tx.id).eq('status', 'pending')
      return NextResponse.json({ success: false, status: payload.data?.status || 'unknown' })
    }
    const paidMinor = Number(payload.data.amount)
    if (!Number.isSafeInteger(paidMinor) || paidMinor !== Number(tx.amount_minor) || payload.data.currency !== tx.currency) return NextResponse.json({ error: 'Payment amount or currency mismatch' }, { status: 400 })

    const meta = tx.metadata && typeof tx.metadata === 'object' ? tx.metadata as Record<string, unknown> : {}
    const campaignId = tx.type === 'campaign_payment' && typeof meta.campaign_id === 'string' ? meta.campaign_id : null
    const { data, error } = await admin.rpc('process_paystack_charge_success', {
      p_event_id: `verify:${reference}:${payload.data.id}`,
      p_event_type: 'charge.success.verify',
      p_user_id: user.id,
      p_reference: reference,
      p_payment_type: tx.type,
      p_amount_minor: paidMinor,
      p_currency: payload.data.currency,
      p_provider_transaction_id: String(payload.data.id),
      p_campaign_id: campaignId,
      p_payload: payload.data,
    })
    if (error) return NextResponse.json({ error: error.message || 'Payment fulfillment failed' }, { status: 500 })
    return NextResponse.json(data ?? { success: true })
  } catch {
    return NextResponse.json({ error: 'Payment verification unavailable' }, { status: 500 })
  }
}
