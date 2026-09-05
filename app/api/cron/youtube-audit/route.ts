import { NextResponse } from 'next/server'

// Legacy incentivized like/subscribe auditing is intentionally disabled. The
// current product only supports compliant discovery/feedback campaigns, so this
// endpoint must never inspect or revoke rewards based on YouTube likes/subscriptions.
export async function GET(request: Request) {
  if (request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  return NextResponse.json({ enabled: false, reason: 'Legacy incentivized engagement auditing is disabled; use discovery/feedback task verification.' })
}
