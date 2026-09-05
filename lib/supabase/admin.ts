import { createClient } from '@supabase/supabase-js'

export function createAdminClient() {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SECRET_KEY
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!secret || !url) throw new Error('Server Supabase service role is not configured')
  return createClient(url, secret, { auth: { autoRefreshToken: false, persistSession: false } })
}
