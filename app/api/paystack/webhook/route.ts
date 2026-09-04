import { NextResponse } from 'next/server'
import crypto from 'node:crypto'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  const raw=await request.text(); const signature=request.headers.get('x-paystack-signature')||''
  const expected=crypto.createHmac('sha512',process.env.PAYSTACK_WEBHOOK_SECRET||process.env.PAYSTACK_SECRET_KEY||'').update(raw).digest('hex')
  try { if(!signature || !crypto.timingSafeEqual(Buffer.from(signature),Buffer.from(expected))) return NextResponse.json({error:'Invalid signature'},{status:401}) } catch { return NextResponse.json({error:'Invalid signature'},{status:401}) }
  try {
    const event=JSON.parse(raw); if(event.event!=='charge.success') return NextResponse.json({received:true})
    const data=event.data; const userId=data?.metadata?.user_id; const reference=data?.reference; const kind=data?.metadata?.type
    if(!userId || !reference || data.currency!=='GHS') return NextResponse.json({received:true})
    const admin=createAdminClient(); const {data:tx}=await admin.from('transactions').select('id,amount,status,type').eq('paystack_ref',reference).eq('user_id',userId).single()
    if(!tx) return NextResponse.json({received:true})
    if(tx.status==='success') return NextResponse.json({received:true,alreadyProcessed:true})
    const paidAmount=Number(data.amount)/100; if(Math.abs(paidAmount-Number(tx.amount))>0.01) return NextResponse.json({error:'Amount mismatch'},{status:400})
    if(kind==='entry_fee' && tx.type==='entry_fee') {
      const {error}=await admin.rpc('fulfill_entry_payment',{p_user:userId,p_ref:reference,p_amount:paidAmount,p_metadata:{channel:'webhook',provider_transaction_id:data.id}}); if(error) return NextResponse.json({error:'Entry fulfillment failed'},{status:500})
    } else if(kind==='campaign_payment' && tx.type==='campaign_payment') {
      const campaignId=data?.metadata?.campaign_id; if(!campaignId)return NextResponse.json({error:'Campaign reference missing'},{status:400})
      await admin.from('transactions').update({status:'success',metadata:{...tx,channel:'webhook',provider_transaction_id:data.id}}).eq('paystack_ref',reference)
      await admin.from('campaigns').update({status:'pending_approval'}).eq('id',campaignId).eq('user_id',userId)
    } else return NextResponse.json({received:true})
    return NextResponse.json({received:true})
  } catch { return NextResponse.json({error:'Invalid webhook'},{status:400}) }
}
