import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const { reference } = await request.json()
    if (typeof reference !== 'string' || !/^[-.=a-zA-Z0-9]+$/.test(reference)) return NextResponse.json({error:'Invalid reference'},{status:400})
    const supabase = await createClient(); const {data:{user}}=await supabase.auth.getUser(); if(!user) return NextResponse.json({error:'Unauthorized'},{status:401})
    const admin=createAdminClient()
    const {data:tx}=await admin.from('transactions').select('user_id,amount,status,type').eq('paystack_ref',reference).single()
    if(!tx || tx.user_id!==user.id || tx.type!=='entry_fee') return NextResponse.json({error:'Payment not found'},{status:404})
    if(tx.status==='success') return NextResponse.json({success:true,alreadyProcessed:true})
    const response=await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,{headers:{Authorization:`Bearer ${process.env.PAYSTACK_SECRET_KEY}`}})
    const payload=await response.json(); if(!response.ok || !payload.status) return NextResponse.json({error:'Payment verification failed'},{status:502})
    if(payload.data.status!=='success') { await admin.from('transactions').update({status:'failed',metadata:{provider_status:payload.data.status}}).eq('paystack_ref',reference).eq('user_id',user.id); return NextResponse.json({success:false,status:payload.data.status}) }
    const paidAmount=Number(payload.data.amount)/100
    if(Math.abs(paidAmount-Number(tx.amount))>0.01 || payload.data.currency!=='GHS') return NextResponse.json({error:'Payment amount or currency mismatch'},{status:400})
    const {error}=await admin.rpc('fulfill_entry_payment',{p_user:user.id,p_ref:reference,p_amount:paidAmount,p_metadata:{channel:'verify',provider_transaction_id:payload.data.id}})
    if(error) return NextResponse.json({error:'Payment fulfillment failed'},{status:500})
    return NextResponse.json({success:true})
  } catch { return NextResponse.json({error:'Payment verification unavailable'},{status:500}) }
}
