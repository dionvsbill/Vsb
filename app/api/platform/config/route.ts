import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function GET() {
  try {
    const admin = createAdminClient()
    const [{ data: settings }, { data: fx }, { data: plan }] = await Promise.all([
      admin.from('platform_settings').select('*').eq('id', 1).maybeSingle(),
      admin.from('fx_rates').select('base_currency,quote_currency,rate_numeric,effective_at').eq('base_currency','USD').eq('quote_currency','GHS').order('effective_at',{ascending:false}).limit(1).maybeSingle(),
      admin.from('plans').select('*').eq('code','creator').maybeSingle(),
    ])
    const s = settings ?? {}
    const p = plan ?? {}
    if (!fx?.rate_numeric) return NextResponse.json({ error: 'A current USD/GHS exchange rate is required' }, { status: 503 })
    return NextResponse.json({
      campaign: {
        allowedModes: Array.isArray(s.allowed_campaign_modes) ? s.allowed_campaign_modes : ['discovery','feedback'],
        minQuantity: Number(s.campaign_min_quantity ?? 1),
        maxQuantity: Number(s.campaign_max_quantity ?? 100000),
        minCostCents: Number(p.min_cost_cents ?? s.campaign_min_cost_cents ?? 10),
        maxCostCents: Number(p.max_cost_cents ?? s.campaign_max_cost_cents ?? 100),
        platformFeeBps: Number(s.campaign_platform_fee_bps ?? 1000),
      },
      fx: { base: fx.base_currency, quote: fx.quote_currency, rate: Number(fx.rate_numeric), effectiveAt: fx.effective_at },
    })
  } catch {
    return NextResponse.json({ error: 'Unable to load platform configuration' }, { status: 500 })
  }
}
