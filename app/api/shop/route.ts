import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const body = await request.json()
  const name = String(body.name || '').trim()
  const slug = String(body.slug || '').trim().toLowerCase().replace(/[^a-z0-9-]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '')
  if (!name || slug.length < 3) return NextResponse.json({ error: 'Shop name and a valid unique slug are required.' }, { status: 400 })
  const { data: existing } = await supabase.from('business_shops').select('id').eq('store_slug', slug).maybeSingle()
  if (existing) return NextResponse.json({ error: 'That shop slug is already in use.' }, { status: 409 })
  const { data, error } = await supabase.from('business_shops').insert({ user_id: user.id, name, store_slug: slug, description: String(body.description || '').trim() || null, momo_number: String(body.momo_number || '').trim() || null, delivery_fee: Math.max(0, Number(body.delivery_fee || 0)), jforce_id: String(body.jforce_id || '').trim() || null, shop_status: 'pending', is_published: false, is_pro: false }).select('id,store_slug,name,shop_status').single()
  if (error) return NextResponse.json({ error: error.message }, { status: 400 })
  return NextResponse.json({ shop: data }, { status: 201 })
}
