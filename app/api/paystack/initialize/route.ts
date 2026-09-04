import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const { data: profile, error: profileError } = await supabase.from('users').select('id,email,is_paid,is_banned,entry_fee_expires_at').eq('id', user.id).single()
    if (profileError || !profile) return NextResponse.json({ error: 'Profile not found' }, { status: 404 })
    if (profile.is_banned) return NextResponse.json({ error: 'Account is restricted' }, { status: 403 })
    if (profile.is_paid) return NextResponse.json({ error: 'Entry fee already paid' }, { status: 409 })
    if (profile.entry_fee_expires_at && new Date(profile.entry_fee_expires_at) < new Date()) return NextResponse.json({ error: 'Registration window expired' }, { status: 410 })
    const settings = await supabase.from('platform_settings').select('entry_fee_ghs').eq('id',true).single()
    const amountGhs = Number(settings.data?.entry_fee_ghs ?? 160)
    const reference = `VSBIL-${user.id.replaceAll('-','').slice(0,12)}-${Date.now()}`
    const response = await fetch('https://api.paystack.co/transaction/initialize', { method:'POST', headers:{ Authorization:`Bearer ${process.env.PAYSTACK_SECRET_KEY}`, 'Content-Type':'application/json' }, body:JSON.stringify({ email:profile.email, amount:Math.round(amountGhs*100).toString(), currency:'GHS', reference, callback_url:`${process.env.NEXT_PUBLIC_APP_URL}/pay-entry-fee`, metadata:{user_id:user.id,type:'entry_fee'} }) })
    const payload = await response.json()
    if (!response.ok || !payload.status) return NextResponse.json({ error:payload.message || 'Unable to initialize payment' }, { status:502 })
    await supabase.from('transactions').insert({user_id:user.id,type:'entry_fee',amount:amountGhs,currency:'GHS',paystack_ref:reference,status:'pending',metadata:{access_code:payload.data.access_code}})
    return NextResponse.json({ authorization_url:payload.data.authorization_url, access_code:payload.data.access_code, reference })
  } catch { return NextResponse.json({ error:'Payment service unavailable' }, { status:500 }) }
}
