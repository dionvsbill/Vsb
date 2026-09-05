import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { enforceRateLimit } from '@/lib/rate-limit'

export async function POST(request:Request){
 const s=await createClient();const {data:{user}}=await s.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401});
 const limited=await enforceRateLimit(`whatsapp-send:${user.id}`,20,'1 m');if(!limited.success)return NextResponse.json({error:'Too many messages'},{status:429});
 const b=await request.json().catch(()=>({}));const shopId=String(b.shop_id||'');const to=String(b.to||'').trim();const text=String(b.text||'').trim();if(!shopId||!/^\+?[1-9]\d{7,14}$/.test(to)||text.length<1||text.length>4096)return NextResponse.json({error:'Invalid WhatsApp message'},{status:400});
 const a=createAdminClient();const {data:shop}=await a.from('business_shops').select('id,user_id').eq('id',shopId).single();if(!shop||shop.user_id!==user.id)return NextResponse.json({error:'Shop not found'},{status:404});
 const token=process.env.META_WA_TOKEN;const phoneId=process.env.META_WA_PHONE_ID;if(!token||!phoneId)return NextResponse.json({error:'WhatsApp is not connected. Add Meta credentials on the server first.'},{status:503});
 const {data:usage}=await a.from('whatsapp_usage').select('conversations_used,period_start').eq('shop_id',shopId).maybeSingle();const {data:plan}=await a.from('plans').select('monthly_conversation_limit').eq('code','creator').maybeSingle();const limit=Number(plan?.monthly_conversation_limit??100);if(Number(usage?.conversations_used??0)>=limit)return NextResponse.json({error:'Monthly WhatsApp conversation limit reached'},{status:402});
 const response=await fetch(`https://graph.facebook.com/v23.0/${phoneId}/messages`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({messaging_product:'whatsapp',to,type:'text',text:{body:text}})});const payload=await response.json().catch(()=>({}));if(!response.ok)return NextResponse.json({error:payload?.error?.message||'Meta WhatsApp request failed'},{status:502});
 await a.from('whatsapp_usage').upsert({shop_id:shopId,conversations_used:Number(usage?.conversations_used??0)+1,updated_at:new Date().toISOString()},{onConflict:'shop_id'});return NextResponse.json({success:true,message_id:payload?.messages?.[0]?.id||null});
}
