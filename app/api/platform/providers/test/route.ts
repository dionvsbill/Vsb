import {NextResponse} from 'next/server'
import {createClient} from '@/lib/supabase/server'

async function jsonFetch(url:string,init:RequestInit={}){const r=await fetch(url,{...init,cache:'no-store'});const body=await r.json().catch(()=>({}));return {ok:r.ok,body}}

export async function POST(request:Request){
 const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
 const body=await request.json().catch(()=>({}));const provider=String(body.provider||'').toLowerCase()
 try{
  if(provider==='facebook'){
   if(!process.env.FACEBOOK_ADS_ACCESS_TOKEN)return NextResponse.json({error:'Facebook access token is not configured'},{status:503})
   const r=await jsonFetch(`https://graph.facebook.com/v23.0/me?fields=id,name&access_token=${encodeURIComponent(process.env.FACEBOOK_ADS_ACCESS_TOKEN)}`)
   if(!r.ok)return NextResponse.json({error:r.body?.error?.message||'Facebook token rejected'},{status:502});return NextResponse.json({provider,status:'connected',account:r.body})
  }
  if(provider==='instagram'){
   if(!process.env.INSTAGRAM_ACCESS_TOKEN)return NextResponse.json({error:'Instagram access token is not configured'},{status:503})
   const r=await jsonFetch(`https://graph.facebook.com/v23.0/me?fields=id,username,name&access_token=${encodeURIComponent(process.env.INSTAGRAM_ACCESS_TOKEN)}`)
   if(!r.ok)return NextResponse.json({error:r.body?.error?.message||'Instagram token rejected'},{status:502});return NextResponse.json({provider,status:'connected',account:r.body})
  }
  if(provider==='tiktok'){
   if(!process.env.TIKTOK_ADS_ACCESS_TOKEN)return NextResponse.json({error:'TIKTOK_ADS_ACCESS_TOKEN is not configured'},{status:503})
   const r=await jsonFetch('https://business-api.tiktok.com/open_api/v1.3/oauth2/advertiser/get/',{method:'POST',headers:{'Access-Token':process.env.TIKTOK_ADS_ACCESS_TOKEN,'Content-Type':'application/json'},body:JSON.stringify({app_id:process.env.TIKTOK_APP_ID})})
   if(!r.ok||r.body?.code!==0)return NextResponse.json({error:r.body?.message||'TikTok token rejected'},{status:502});return NextResponse.json({provider,status:'connected',account:r.body?.data})
  }
  if(provider==='youtube')return NextResponse.json({provider,status:'configured',message:'YouTube OAuth/API configuration is available through the existing connection flow.'})
  return NextResponse.json({error:'Unsupported provider'},{status:400})
 }catch{return NextResponse.json({error:'Provider connectivity test failed'},{status:502})}
}
