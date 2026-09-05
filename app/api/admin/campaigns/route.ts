import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function GET() {
  const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
  const admin=createAdminClient();const {data:actor}=await admin.from('users').select('role,is_banned').eq('id',user.id).single();if(!actor||actor.is_banned||!['admin','superadmin'].includes(actor.role))return NextResponse.json({error:'Forbidden'},{status:403})
  const {data,error}=await admin.from('campaigns').select('id,user_id,youtube_video_id,youtube_video_title,quantity,completed_count,total_budget_minor,total_charge_minor,status,policy_review_status,promotion_mode,created_at,updated_at').order('created_at',{ascending:false}).limit(200)
  if(error)return NextResponse.json({error:error.message},{status:500});return NextResponse.json({campaigns:data||[]})
}
