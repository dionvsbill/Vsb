import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { getVideo, isoDurationSeconds } from '@/lib/youtube'

export async function POST(request:Request){
 try{
  const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
  const {data:profile}=await supabase.from('users').select('is_paid,is_banned,email').eq('id',user.id).single();if(!profile?.is_paid||profile.is_banned)return NextResponse.json({error:'Active paid account required'},{status:403})
  const b=await request.json(); const video=await getVideo(String(b.video_id)); const taskTypes=Array.isArray(b.task_types)?b.task_types.map(String):['watch']; const allowed=['watch','like','subscribe','comment']; if(!taskTypes.every((x:string)=>allowed.includes(x)))return NextResponse.json({error:'Invalid task type'},{status:400})
  const quantity=Math.floor(Number(b.quantity));const cost=Number(b.cost_per_task);if(!Number.isInteger(quantity)||quantity<1||quantity>100000)return NextResponse.json({error:'Quantity must be between 1 and 100,000'},{status:400});if(!Number.isFinite(cost)||cost<0.10||cost>1)return NextResponse.json({error:'Cost per task must be between $0.10 and $1.00'},{status:400})
  const base=Number((quantity*cost).toFixed(2));const fee=Number((base*0.10).toFixed(2));const totalUsd=Number((base+fee).toFixed(2));const rate=160;const totalGhs=Number((totalUsd*rate).toFixed(2));
  const admin=createAdminClient(); const {data:campaign,error}=await admin.from('campaigns').insert({user_id:user.id,youtube_video_id:video.id,youtube_video_title:video.title,youtube_channel_id:video.channelId,thumbnail:video.thumbnail,duration_seconds:isoDurationSeconds(video.duration),task_types:taskTypes,required_watch_percent:100,quantity, cost_per_task:cost,total_budget:base,platform_fee:fee,status:'pending_approval'}).select('id').single();if(error||!campaign)return NextResponse.json({error:'Unable to create campaign'},{status:500})
  const reference=`VSBIL-CAMP-${campaign.id.replaceAll('-','').slice(0,16)}-${Date.now()}`
  const response=await fetch('https://api.paystack.co/transaction/initialize',{method:'POST',headers:{Authorization:`Bearer ${process.env.PAYSTACK_SECRET_KEY}`,'Content-Type':'application/json'},body:JSON.stringify({email:profile.email,amount:Math.round(totalGhs*100).toString(),currency:'GHS',reference,callback_url:`${process.env.NEXT_PUBLIC_APP_URL}/campaigns`,metadata:{user_id:user.id,campaign_id:campaign.id,type:'campaign_payment'}})})
  const payload=await response.json();if(!response.ok||!payload.status){await admin.from('campaigns').delete().eq('id',campaign.id);return NextResponse.json({error:payload.message||'Unable to initialize campaign payment'},{status:502})}
  await admin.from('transactions').insert({user_id:user.id,type:'campaign_payment',amount:totalGhs,currency:'GHS',paystack_ref:reference,status:'pending',metadata:{campaign_id:campaign.id,total_usd:totalUsd,rate}})
  return NextResponse.json({campaign_id:campaign.id,reference,authorization_url:payload.data.authorization_url,total_usd:totalUsd,total_ghs:totalGhs})
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:'Unable to create campaign'},{status:500})}
}
