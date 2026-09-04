import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { getVideo, isoDurationSeconds, parseVideoId } from '@/lib/youtube'

export async function POST(request: Request){
 try{
  const supabase=await createClient(); const {data:{user}}=await supabase.auth.getUser(); if(!user)return NextResponse.json({error:'Unauthorized'},{status:401})
  const body=await request.json(); const videoId=parseVideoId(String(body.url||'')); if(!videoId)return NextResponse.json({error:'Enter a valid YouTube video URL'},{status:400})
  const video=await getVideo(videoId)
  return NextResponse.json({...video,duration_seconds:isoDurationSeconds(video.duration)})
 }catch(e){return NextResponse.json({error:e instanceof Error?e.message:'Unable to validate video'},{status:502})}
}
