import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(){
  const supabase=await createClient()
  const {data:{user}}=await supabase.auth.getUser()
  if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
  const {data,error}=await supabase.from('campaigns').select('id,youtube_video_id,youtube_video_title,thumbnail,quantity,completed_count,total_budget_minor,total_charge_minor,currency,status,policy_review_status,promotion_mode,created_at,updated_at').eq('user_id',user.id).order('created_at',{ascending:false}).limit(100)
  if(error)return NextResponse.json({error:error.message},{status:500})
  return NextResponse.json({campaigns:data||[]},{headers:{'Cache-Control':'private, no-store'}})
}
