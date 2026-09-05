import { NextResponse } from 'next/server'
import { createHash } from 'node:crypto'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  try {
    const supabase=await createClient(); const {data:{user}}=await supabase.auth.getUser(); if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
    const key=request.headers.get('Idempotency-Key')?.trim()||''; if(!/^[A-Za-z0-9._:-]{16,128}$/.test(key))return NextResponse.json({error:'A valid Idempotency-Key is required'},{status:400})
    const body=await request.json().catch(()=>({})); const taskId=typeof body.task_id==='string'?body.task_id:''; const sessionId=typeof body.session_id==='string'?body.session_id:''; const nonce=typeof body.session_nonce==='string'?body.session_nonce:''
    if(!taskId||!sessionId||nonce.length<32)return NextResponse.json({error:'Task session is required'},{status:400})
    const admin=createAdminClient(); const {data:existing}=await admin.from('idempotency_keys').select('response_body,response_status').eq('scope','task_verify').eq('key',key).maybeSingle()
    if(existing?.response_body)return NextResponse.json(existing.response_body,{status:Number(existing.response_status)||200})
    const {data,error}=await admin.rpc('verify_discovery_task',{p_task_id:taskId,p_session_id:sessionId,p_worker_id:user.id,p_nonce_hash:createHash('sha256').update(nonce).digest('hex'),p_idempotency_key:key})
    if(error){const msg=String(error.message||'');const status=/NOT_FOUND|SESSION|NONCE|PLAYBACK|ABNORMAL|UNAVAILABLE|ALREADY/.test(msg)?409:500;return NextResponse.json({error:msg||'Verification failed'},{status})}
    return NextResponse.json(data??{success:true})
  }catch{return NextResponse.json({error:'Unable to verify task'},{status:500})}
}
