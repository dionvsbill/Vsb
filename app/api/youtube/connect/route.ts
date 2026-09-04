import { NextResponse } from 'next/server'
import crypto from 'node:crypto'
import { createClient } from '@/lib/supabase/server'

export async function GET(request:Request){
 const supabase=await createClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.redirect(new URL('/login',request.url))
 const state=crypto.randomBytes(32).toString('hex');const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');url.searchParams.set('client_id',process.env.GOOGLE_CLIENT_ID!);url.searchParams.set('redirect_uri',`${process.env.NEXT_PUBLIC_APP_URL}/api/youtube/callback`);url.searchParams.set('response_type','code');url.searchParams.set('access_type','offline');url.searchParams.set('prompt','consent');url.searchParams.set('scope','openid email https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube.force-ssl');url.searchParams.set('state',state)
 const response=NextResponse.redirect(url);response.cookies.set('youtube_oauth_state',`${user.id}:${state}`,{httpOnly:true,secure:process.env.NODE_ENV==='production',sameSite:'lax',maxAge:600,path:'/'});return response
}
