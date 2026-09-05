import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { encryptSecret } from '@/lib/crypto'

export async function GET(request:Request){
 const url=new URL(request.url);const code=url.searchParams.get('code');const state=url.searchParams.get('state');const cookie=(await import('next/headers')).cookies();const saved=cookie.get('youtube_oauth_state')?.value;
 if(!code||!state||!saved)return NextResponse.redirect(new URL('/dashboard/profile?error=oauth_state',request.url));
 const [userId,savedState]=saved.split(':');if(!userId||savedState!==state)return NextResponse.redirect(new URL('/dashboard/profile?error=oauth_state',request.url));
 try{
  const tokenRes=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({code,client_id:process.env.GOOGLE_CLIENT_ID!,client_secret:process.env.GOOGLE_CLIENT_SECRET!,redirect_uri:`${process.env.NEXT_PUBLIC_APP_URL}/api/youtube/callback`,grant_type:'authorization_code'})});
  const tokens=await tokenRes.json();if(!tokenRes.ok||!tokens.access_token)throw new Error('Google token exchange failed');
  const yt=await fetch('https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true',{headers:{Authorization:`Bearer ${tokens.access_token}`}});const data=await yt.json();if(!yt.ok||!data.items?.[0])throw new Error('No YouTube channel was returned');
  const channel=data.items[0];const admin=createAdminClient();
  const access=await admin.rpc('store_youtube_secret',{p_user_id:userId,p_name:'access_token',p_ciphertext:encryptSecret(String(tokens.access_token))});if(access.error)throw access.error;
  let refreshId=null;if(tokens.refresh_token){const refresh=await admin.rpc('store_youtube_secret',{p_user_id:userId,p_name:'refresh_token',p_ciphertext:encryptSecret(String(tokens.refresh_token))});if(refresh.error)throw refresh.error;refreshId=refresh.data}
  const {error}=await admin.from('users').update({youtube_channel_id:channel.id,youtube_channel_title:channel.snippet?.title||'',youtube_subscriber_count:Number(channel.statistics?.subscriberCount||0),youtube_access_secret_id:access.data,youtube_refresh_secret_id:refreshId,youtube_connected_at:new Date().toISOString()}).eq('id',userId);if(error)throw error
  const response=NextResponse.redirect(new URL('/dashboard/profile?youtube=connected',request.url));response.cookies.delete('youtube_oauth_state');return response
 }catch(e){return NextResponse.redirect(new URL(`/dashboard/profile?error=${encodeURIComponent(e instanceof Error?e.message:'youtube_connection_failed')}`,request.url))}
}
