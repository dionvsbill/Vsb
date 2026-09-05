import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function GET() {
  try {
    const admin = createAdminClient()
    const [{ data: settings }, { data: fx }, { data: plan }] = await Promise.all([
      admin.from('platform_settings').select('allowed_campaign_modes,campaign_min_quantity,campaign_max_quantity,campaign_min_cost_cents,campaign_max_cost_cents,campaign_platform_fee_bps,config_version').eq('id', true).maybeSingle(),
      admin.from('fx_rates').select('base_currency,quote_currency,rate_numeric,effective_from,effective_to,source').eq('base_currency','USD').eq('quote_currency','GHS').lte('effective_from',new Date().toISOString()).or('effective_to.is.null,effective_to.gt.' + new Date().toISOString()).order('effective_from',{ascending:false}).limit(1).maybeSingle(),
      admin.from('plans').select('code,min_cost_cents,max_cost_cents').eq('code','creator').eq('active',true).maybeSingle(),
    ])
    if (!settings || !plan || !fx?.rate_numeric) return NextResponse.json({ error: 'Platform configuration is unavailable' }, { status: 503 })
    const modes = Array.isArray(settings.allowed_campaign_modes) ? settings.allowed_campaign_modes.map(String) : []
    const minQuantity = Number(settings.campaign_min_quantity), maxQuantity = Number(settings.campaign_max_quantity)
    const minCostCents = Number(plan.min_cost_cents ?? settings.campaign_min_cost_cents), maxCostCents = Number(plan.max_cost_cents ?? settings.campaign_max_cost_cents)
    const platformFeeBps = Number(settings.campaign_platform_fee_bps)
    if (!modes.length || !modes.every((m) => ['discovery','feedback'].includes(m)) || !Number.isInteger(minQuantity) || !Number.isInteger(maxQuantity) || minQuantity < 1 || maxQuantity < minQuantity || !Number.isInteger(minCostCents) || !Number.isInteger(maxCostCents) || minCostCents < 1 || maxCostCents < minCostCents || !Number.isInteger(platformFeeBps) || platformFeeBps < 0 || platformFeeBps > 10000) return NextResponse.json({ error: 'Platform campaign configuration is invalid' }, { status: 503 })
    return NextResponse.json({ campaign:{allowedModes:modes,minQuantity,maxQuantity,minCostCents,maxCostCents,platformFeeBps},fx:{base:fx.base_currency,quote:fx.quote_currency,rate:Number(fx.rate_numeric),effectiveAt:fx.effective_from,source:fx.source},configVersion:Number(settings.config_version ?? 1) })
  } catch { return NextResponse.json({ error: 'Unable to load platform configuration' }, { status: 500 }) }
}
