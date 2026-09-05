import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

const transitions:Record<string,string>={approve:'approved',reject:'rejected',pause:'paused',resume:'active',cancel:'cancelled'}
const allowed:Record<string,string[]>={approve:['pending_approval'],reject:['pending_approval','approved','active','paused'],pause:['approved','active'],resume:['paused'],cancel:['pending_approval','approved','active','paused']}

export async function POST(request:Request,{params}:{params:{id:string;action:string}}){
 try{
  const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
  const admin=createAdminClient();const {data:actor}=await admin.from('users').select('role,is_banned').eq('id',user.id).single();if(!actor||actor.is_banned||!['admin','superadmin'].includes(actor.role))return NextResponse.json({error:'Forbidden'},{status:403})
  const action=params.action.toLowerCase();if(!transitions[action])return NextResponse.json({error:'Unsupported campaign action'},{status:400})
  const body=await request.json().catch(()=>({}));const reason=typeof body.reason==='string'?body.reason.trim():'';if(action!=='approve'&&!reason)return NextResponse.json({error:'A reason is required'},{status:400})
  const {data:c}=await admin.from('campaigns').select('id,user_id,status,policy_review_status').eq('id',params.id).single();if(!c)return NextResponse.json({error:'Campaign not found'},{status:404})
  if(!(allowed[action]||[]).includes(String(c.status)))return NextResponse.json({error:`Cannot ${action} a campaign in ${c.status} state`},{status:409})
  if(action==='approve'&&c.policy_review_status!=='approved')return NextResponse.json({error:'Campaign policy review is not approved'},{status:409})
  const next=transitions[action];const patch:any={status:next,updated_at:new Date().toISOString()};if(action==='approve')Object.assign(patch,{approved_by:user.id,approved_at:new Date().toISOString(),rejection_reason:null});if(action==='reject')patch.rejection_reason=reason
  const {error}=await admin.from('campaigns').update(patch).eq('id',c.id).eq('status',c.status);if(error)return NextResponse.json({error:error.message},{status:500})
  await admin.from('audit_logs').insert({actor_id:user.id,action:`campaign.${action}`,target_type:'campaign',target_id:c.id,metadata:{reason:reason||null,from:c.status,to:next}})
  return NextResponse.json({success:true,campaign_id:c.id,status:next})
 }catch{return NextResponse.json({error:'Unable to update campaign'},{status:500})}
}
