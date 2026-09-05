import { NextResponse } from 'next/server'
import crypto from 'node:crypto'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  const raw = await request.text()
  const signature = request.headers.get('x-paystack-signature') || ''
  const secret = process.env.PAYSTACK_WEBHOOK_SECRET || process.env.PAYSTACK_SECRET_KEY || ''
  const expected = secret ? crypto.createHmac('sha512', secret).update(raw).digest('hex') : ''
  try {
    if (!secret || !signature || signature.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return NextResponse.json({ error: 'Invalid signature' }, { status: 401 })
  } catch { return NextResponse.json({ error: 'Invalid signature' }, { status: 401 }) }

  try {
    const event = JSON.parse(raw)
    const data = event?.data
    if (event?.event !== 'charge.success') return NextResponse.json({ received: true })
    const userId = data?.metadata?.user_id
    const reference = data?.reference
    const kind = data?.metadata?.type
    const paidMinor = Number(data?.amount)
    if (typeof userId !== 'string' || typeof reference !== 'string' || data?.currency !== 'GHS' || !Number.isSafeInteger(paidMinor) || paidMinor <= 0) return NextResponse.json({ received: true })

    const admin = createAdminClient()
    const { data: tx } = await admin.from('transactions').select('id,user_id,amount_minor,currency,type,status,metadata').eq('paystack_ref', reference).eq('user_id', userId).maybeSingle()
    if (!tx) return NextResponse.json({ received: true })
    if (tx.status === 'success') return NextResponse.json({ received: true, alreadyProcessed: true })
    if (Number(tx.amount_minor) !== paidMinor || tx.currency !== data.currency) return NextResponse.json({ error: 'Amount mismatch' }, { status: 400 })
    if (kind !== 'entry_fee' && kind !== 'campaign_payment') return NextResponse.json({ received: true })
    if (tx.type !== kind) return NextResponse.json({ error: 'Payment type mismatch' }, { status: 400 })

    const meta = tx.metadata && typeof tx.metadata === 'object' ? tx.metadata as Record<string, unknown> : {}
    const campaignId = kind === 'campaign_payment' && typeof meta.campaign_id === 'string' ? meta.campaign_id : null
    const eventId = `${event.event}:${String(data.id || '')}:${reference}`
    const { data: result, error } = await admin.rpc('process_paystack_charge_success', {
      p_event_id: eventId,
      p_event_type: event.event,
      p_user_id: userId,
      p_reference: reference,
      p_payment_type: kind,
      p_amount_minor: paidMinor,
      p_currency: data.currency,
      p_provider_transaction_id: String(data.id || ''),
      p_campaign_id: campaignId,
      p_payload: event,
    })
    if (error) return NextResponse.json({ error: error.message || 'Webhook processing failed' }, { status: 500 })
    return NextResponse.json({ received: true, result })
  } catch { return NextResponse.json({ error: 'Invalid webhook' }, { status: 400 }) }
}
