import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { enforceRateLimit } from '@/lib/rate-limit'

async function jsonFetch(url: string, init: RequestInit = {}) {
  const response = await fetch(url, { ...init, cache: 'no-store' })
  const body = await response.json().catch(() => ({}))
  return { ok: response.ok, status: response.status, body }
}

async function requireAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { user: null, error: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  const { data: profile } = await supabase.from('users').select('role,is_banned').eq('id', user.id).maybeSingle()
  if (!profile || profile.is_banned || !['admin', 'superadmin'].includes(profile.role)) {
    return { user: null, error: NextResponse.json({ error: 'Administrator access required' }, { status: 403 }) }
  }
  return { user, error: null }
}

export async function POST(request: Request) {
  const { user, error } = await requireAdmin()
  if (error || !user) return error

  const limited = await enforceRateLimit(`provider-test:${user.id}`, 10, '1 m')
  if (!limited.success) return NextResponse.json({ error: 'Too many provider connectivity tests' }, { status: 429 })

  const body = await request.json().catch(() => ({}))
  const provider = String(body.provider || '').toLowerCase()

  try {
    if (provider === 'facebook') {
      if (!process.env.FACEBOOK_ADS_ACCESS_TOKEN) return NextResponse.json({ error: 'Facebook access token is not configured' }, { status: 503 })
      const accountId = process.env.FACEBOOK_AD_ACCOUNT_ID?.replace(/^act_/, '')
      if (!accountId) return NextResponse.json({ error: 'Facebook ad account ID is not configured' }, { status: 503 })
      const graphVersion = process.env.META_GRAPH_API_VERSION || 'v23.0'
      const r = await jsonFetch(`https://graph.facebook.com/${graphVersion}/act_${encodeURIComponent(accountId)}?fields=id,name,account_status,currency&access_token=${encodeURIComponent(process.env.FACEBOOK_ADS_ACCESS_TOKEN)}`)
      if (!r.ok) return NextResponse.json({ error: r.body?.error?.message || `Facebook API returned ${r.status}` }, { status: 502 })
      return NextResponse.json({ provider, status: 'connected', account: r.body })
    }

    if (provider === 'instagram') {
      if (!process.env.INSTAGRAM_ACCESS_TOKEN) return NextResponse.json({ error: 'Instagram access token is not configured' }, { status: 503 })
      const graphVersion = process.env.META_GRAPH_API_VERSION || 'v23.0'
      const r = await jsonFetch(`https://graph.facebook.com/${graphVersion}/me?fields=id,username,name&access_token=${encodeURIComponent(process.env.INSTAGRAM_ACCESS_TOKEN)}`)
      if (!r.ok) return NextResponse.json({ error: r.body?.error?.message || `Instagram Graph API returned ${r.status}` }, { status: 502 })
      return NextResponse.json({ provider, status: 'connected', account: r.body })
    }

    if (provider === 'tiktok') {
      if (!process.env.TIKTOK_ADS_ACCESS_TOKEN) return NextResponse.json({ error: 'TikTok Ads access token is not configured' }, { status: 503 })
      const r = await jsonFetch('https://business-api.tiktok.com/open_api/v1.3/oauth2/advertiser/get/', {
        method: 'POST',
        headers: { 'Access-Token': process.env.TIKTOK_ADS_ACCESS_TOKEN, 'Content-Type': 'application/json' },
        body: JSON.stringify({ app_id: process.env.TIKTOK_APP_ID }),
      })
      if (!r.ok || r.body?.code !== 0) return NextResponse.json({ error: r.body?.message || `TikTok API returned ${r.status}` }, { status: 502 })
      return NextResponse.json({ provider, status: 'connected', account: r.body?.data })
    }

    if (provider === 'youtube') {
      if (!process.env.YOUTUBE_API_KEY) return NextResponse.json({ error: 'YouTube API key is not configured' }, { status: 503 })
      const r = await jsonFetch(`https://www.googleapis.com/youtube/v3/videos?part=id&id=dQw4w9WgXcQ&key=${encodeURIComponent(process.env.YOUTUBE_API_KEY)}`)
      if (!r.ok) return NextResponse.json({ error: r.body?.error?.message || `YouTube Data API returned ${r.status}` }, { status: 502 })
      return NextResponse.json({ provider, status: 'connected', message: 'YouTube Data API key accepted.' })
    }

    return NextResponse.json({ error: 'Unsupported provider' }, { status: 400 })
  } catch {
    return NextResponse.json({ error: 'Provider connectivity test failed' }, { status: 502 })
  }
}
