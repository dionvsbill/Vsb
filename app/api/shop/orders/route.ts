import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request:Request){
 const s=await createClient(); const b=await request.json(); const shopId=String(b.shopId||''); const items=Array.isArray(b.items)?b.items:[]; if(!shopId||!items.length)return NextResponse.json({error:'Shop and cart items are required.'},{status:400});
 const {data,error}=await s.rpc('create_shop_order',{p_shop_id:shopId,p_buyer_name:String(b.buyer_name||'').trim(),p_buyer_phone:String(b.buyer_phone||'').trim(),p_buyer_email:String(b.buyer_email||'').trim()||null,p_delivery_address:String(b.delivery_address||'').trim()||null,p_delivery_note:String(b.delivery_note||'').trim()||null,p_payment_method:String(b.payment_method||'cod'),p_delivery_fee:0,p_items:items.map((x:{product_id:string;quantity:number})=>({product_id:x.product_id,quantity:Math.max(1,Math.floor(Number(x.quantity)))}))});
 if(error)return NextResponse.json({error:error.message},{status:400}); const order=Array.isArray(data)?data[0]:data; return NextResponse.json({order},{status:201});
}
