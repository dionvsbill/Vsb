import { NextResponse } from 'next/server'

function configured(names: string[]) {
  return names.every((name) => Boolean(process.env[name]))
}

export async function GET() {
  return NextResponse.json({
    providers: [
      { id: 'youtube', name: 'YouTube', status: configured(['YOUTUBE_API_KEY', 'GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET']) ? 'configured' : 'not_configured', capabilities: ['content_validation', 'oauth'] },
      { id: 'facebook', name: 'Facebook', status: configured(['FACEBOOK_APP_ID', 'FACEBOOK_APP_SECRET', 'FACEBOOK_ADS_ACCESS_TOKEN', 'FACEBOOK_AD_ACCOUNT_ID']) ? 'configured' : 'not_configured', capabilities: ['paid_advertising'] },
      { id: 'instagram', name: 'Instagram', status: configured(['INSTAGRAM_APP_ID', 'INSTAGRAM_APP_SECRET', 'INSTAGRAM_ACCESS_TOKEN']) ? 'configured' : 'not_configured', capabilities: ['paid_advertising'] },
      { id: 'tiktok', name: 'TikTok', status: configured(['TIKTOK_APP_ID', 'TIKTOK_APP_SECRET', 'TIKTOK_ADVERTISER_ID']) ? 'configured' : 'not_configured', capabilities: ['paid_advertising'] },
    ],
    policy: { incentivized_engagement: false, artificial_views: false, artificial_likes: false, artificial_subscriptions: false },
  }, { headers: { 'Cache-Control': 'no-store' } })
}
