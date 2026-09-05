import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { createClient } from '@/lib/supabase/server'
import { enforceRateLimit } from '@/lib/rate-limit'

export async function POST(request:Request){
 const b=await request.json().catch(()=>({}));const shopId=String(b.shop_id||'');const quoteId=String(b.quote_id||'');const key=request.headers.get('Idempotency-Key')?.trim()||'';if(!shopId||!quoteId||!/^[-A-Za-z0-9_:]{16,128}$/.test(key))return NextResponse.json({error:'shop_id, quote_id and Idempotency-Key are required'},{status:400});
 const ip=request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';const limited=await enforceRateLimit(`shop-order:${ip}`,10,'10 m');if(!limited.success)return NextResponse.json({error:'Too many checkout attempts'},{status:429});
 const a=createAdminClient();const {data:existing}=await a.from('shop_orders').select('*').eq('shop_id',shopId).eq('idempotency_key',key).maybeSingle();if(existing)return NextResponse.json({order:existing,existing:true});
 const {data:quote}=await a.from('shop_quotes').select('*').eq('id',quoteId).eq('shop_id',shopId).single();if(!quote||new Date(quote.expires_at).getTime()<Date.now())return NextResponse.json({error:'Quote expired. Request a new quote.'},{status:409});
 const buyerName=String(b.buyer_name||'').trim(),buyerPhone=String(b.buyer_phone||'').trim();if(buyerName.length<2||buyerPhone.replace(/\D/g,'').length<7)return NextResponse.json({error:'A valid customer name and phone are required'},{status:400});
 const session=await createClient();const {data:{user}}=await session.auth.getUser();
 const {data,error}=await a.rpc('create_shop_order',{p_shop_id:shopId,p_buyer_name:buyerName,p_buyer_phone:buyerPhone,p_buyer_email:String(b.buyer_email||'').trim()||null,p_delivery_address:String(b.delivery_address||'').trim()||null,p_delivery_note:String(b.delivery_note||'').trim()||null,p_payment_method:String(b.payment_method||'paystack'),p_delivery_fee:Number(quote.delivery_fee_minor)/100,p_items:quote.items});
 if(error)return NextResponse.json({error:error.message},{status:400});const order=Array.isArray(data)?data[0]:data;const orderId=order?.id;if(!orderId)return NextResponse.json({error:'Order creation failed'},{status:500});await a.from('shop_orders').update({idempotency_key:key,user_id:user?.id||null,quote_id:quote.id}).eq('id',orderId);return NextResponse.json({order:{...order,id:orderId,total_minor:quote.total_minor,currency:quote.currency}},{status:201});
}
