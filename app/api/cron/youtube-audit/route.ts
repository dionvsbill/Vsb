import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'

async function youtubeGet(path:string,access:string){const r=await fetch(`https://www.googleapis.com/youtube/v3/${path}`,{headers:{Authorization:`Bearer ${access}`},cache:'no-store'});const d=await r.json();if(!r.ok)throw new Error(d?.error?.message||'YouTube request failed');return d}
async function refresh(refresh:string){const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:process.env.GOOGLE_CLIENT_ID!,client_secret:process.env.GOOGLE_CLIENT_SECRET!,refresh_token:refresh,grant_type:'refresh_token'})});const d=await r.json();if(!r.ok)throw new Error('Token refresh failed');return d.access_token as string}
export async function GET(request:Request){
 const auth=request.headers.get('authorization');if(auth!==`Bearer ${process.env.CRON_SECRET}`)return NextResponse.json({error:'Unauthorized'},{status:401})
 const admin=createAdminClient();let checked=0,revoked=0,errors=0
 const {data:tasks}=await admin.from('watch_tasks').select('id,worker_id,earning_amount,campaign_id,liked_verified,subscribed_verified,status').eq('status','completed').limit(500)
 for(const task of tasks||[]){try{
   const {data:user}=await admin.from('users').select('id,youtube_access_secret_id,youtube_refresh_secret_id,youtube_channel_id,strikes,is_banned').eq('id',task.worker_id).single();if(!user?.youtube_access_secret_id||user.is_banned)continue
   let access=(await admin.rpc('read_youtube_secret',{p_id:user.youtube_access_secret_id})).data as string|null;const refreshId=user.youtube_refresh_secret_id
   if(!access&&refreshId){const rt=(await admin.rpc('read_youtube_secret',{p_id:refreshId})).data as string|null;if(rt){access=await refresh(rt);const saved=await admin.rpc('store_youtube_secret',{p_value:access,p_name:`youtube_access_${user.id}_${Date.now()}`});if(saved.data)await admin.from('users').update({youtube_access_secret_id:saved.data}).eq('id',user.id)}}
   if(!access)continue
   const {data:campaign}=await admin.from('campaigns').select('youtube_video_id,youtube_channel_id,task_types').eq('id',task.campaign_id).single();if(!campaign)continue
   let violation:null|string=null
   if(task.liked_verified){const rating=await youtubeGet(`videos?part=snippet&myRating=like&id=${campaign.youtube_video_id}`,access);if(!rating.items?.length)violation='unlike'}
   if(!violation&&task.subscribed_verified&&campaign.youtube_channel_id){const sub=await youtubeGet(`subscriptions?part=snippet&mine=true&forChannelId=${encodeURIComponent(campaign.youtube_channel_id)}&maxResults=1`,access);if(!sub.items?.length)violation='unsubscribe'}
   checked++
   if(violation){
    const newStrike=Math.min(3,(user.strikes||0)+1);let action='warning';let until:null|string=null
    if(newStrike===2){action='7_day_ban_and_50_percent_balance_penalty';until=new Date(Date.now()+7*86400000).toISOString()}
    if(newStrike>=3){action='permanent_ban_and_blacklist';until=null}
    await admin.from('violations').insert({user_id:user.id,type:violation,evidence:{task_id:task.id,campaign_id:task.campaign_id,checked_at:new Date().toISOString()},action_taken:action,related_task_id:task.id})
    await admin.from('violation_logs').insert({user_id:user.id,type:violation,evidence:{task_id:task.id,campaign_id:task.campaign_id},action_taken:action,related_task_id:task.id})
    if(Number(task.earning_amount)>0){await admin.rpc('debit_wallet',{p_user:user.id,p_amount:Number(task.earning_amount),p_type:'revocation',p_metadata:{reason:violation,task_id:task.id}});await admin.from('watch_tasks').update({status:'revoked',revoked_at:new Date().toISOString()}).eq('id',task.id);revoked++}
    if(newStrike===2){const {data:bal}=await admin.from('users').select('balance').eq('id',user.id).single();if(Number(bal?.balance)>0)await admin.rpc('debit_wallet',{p_user:user.id,p_amount:Number(bal?.balance)/2,p_type:'revocation',p_metadata:{reason:'strike_2_penalty',task_id:task.id}})}
    if(newStrike>=3){const {data:bal}=await admin.from('users').select('balance').eq('id',user.id).single();if(Number(bal?.balance)>0)await admin.rpc('debit_wallet',{p_user:user.id,p_amount:Number(bal?.balance),p_type:'revocation',p_metadata:{reason:'permanent_ban',task_id:task.id}});await admin.from('users').update({strikes:3,is_banned:true,banned_until:null,blacklist_reason:'Repeated YouTube compliance violations'}).eq('id',user.id)}else await admin.from('users').update({strikes:newStrike,banned_until:until,is_banned:newStrike===2}).eq('id',user.id)
   }
  }catch{errors++}}
 return NextResponse.json({checked,revoked,errors})
}
