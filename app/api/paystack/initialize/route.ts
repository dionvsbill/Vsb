import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const key = request.headers.get('Idempotency-Key')?.trim() || ''
    if (!/^[A-Za-z0-9._:-]{16,128}$/.test(key)) return NextResponse.json({ error: 'A valid Idempotency-Key is required' }, { status: 400 })

    const { data: profile, error: profileError } = await supabase.from('users').select('id,email,is_paid,is_banned,entry_fee_expires_at').eq('id', user.id).single()
    if (profileError || !profile) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
    if (profile.is_banned) return NextResponse.json({ error: 'Account is restricted' }, { status: 403 })
    if (profile.is_paid) return NextResponse.json({ error: 'Entry fee already paid' }, { status: 409 })
    if (profile.entry_fee_expires_at && new Date(profile.entry_fee_expires_at) < new Date()) return NextResponse.json({ error: 'Registration window expired' }, { status: 410 })

    const admin = createAdminClient()
    const { data: settings } = await admin.from('platform_settings').select('entry_fee_minor').eq('id', true).maybeSingle()
    const amountMinor = Number(settings?.entry_fee_minor)
    if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) return NextResponse.json({ error: 'Entry-fee configuration is unavailable' }, { status: 503 })

    const { data: existing } = await admin.from('transactions').select('id,paystack_ref,amount_minor,status,metadata').eq('user_id', user.id).eq('idempotency_key', key).maybeSingle()
    if (existing) {
      if (existing.amount_minor !== amountMinor) return NextResponse.json({ error: 'Idempotency key was already used for another amount' }, { status: 409 })
      const meta = existing.metadata && typeof existing.metadata === 'object' ? existing.metadata as Record<string, unknown> : {}
      if (meta.authorization_url) return NextResponse.json({ authorization_url: meta.authorization_url, access_code: meta.access_code, reference: existing.paystack_ref })
      if (existing.status === 'failed') return NextResponse.json({ error: 'Previous payment initialization failed; use a new idempotency key' }, { status: 409 })
      return NextResponse.json({ reference: existing.paystack_ref, status: existing.status }, { status: 202 })
    }

    const reference = `VSBIL-${user.id.replaceAll('-', '').slice(0, 12)}-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`
    const { error: intentError } = await admin.from('transactions').insert({
      user_id: user.id, type: 'entry_fee', amount: amountMinor / 100, amount_minor: amountMinor, currency: 'GHS', paystack_ref: reference,
      status: 'pending', idempotency_key: key, provider: 'paystack', metadata: { purpose: 'entry_fee', created_as_intent: true },
    })
    if (intentError) return NextResponse.json({ error: 'Unable to create payment intent' }, { status: 500 })

    const response = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: { Authorization: `Bearer ${process.env.PAYSTACK_SECRET_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: profile.email, amount: amountMinor.toString(), currency: 'GHS', reference, callback_url: `${process.env.NEXT_PUBLIC_APP_URL}/pay-entry-fee`, metadata: { user_id: user.id, type: 'entry_fee', idempotency_key: key } }),
    })
    const payload = await response.json().catch(() => ({}))
    if (!response.ok || !payload.status) {
      await admin.from('transactions').update({ status: 'failed', metadata: { purpose: 'entry_fee', provider_error: payload.message || 'initialize_failed' } }).eq('paystack_ref', reference).eq('status', 'pending')
      return NextResponse.json({ error: payload.message || 'Unable to initialize payment' }, { status: 502 })
    }
    await admin.from('transactions').update({ metadata: { purpose: 'entry_fee', created_as_intent: true, authorization_url: payload.data.authorization_url, access_code: payload.data.access_code } }).eq('paystack_ref', reference).eq('status', 'pending')
    return NextResponse.json({ authorization_url: payload.data.authorization_url, access_code: payload.data.access_code, reference })
  } catch {
    return NextResponse.json({ error: 'Payment service unavailable' }, { status: 500 })
  }
}
