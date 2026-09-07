import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

function getPublishableKey() {
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!key) throw new Error('Supabase publishable key is not configured')
  return key
}

export async function createClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!url) throw new Error('Supabase URL is not configured')
  const cookieStore = await cookies()
  return createServerClient(url, getPublishableKey(), {
    cookies: {
      getAll() { return cookieStore.getAll() },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options))
        } catch {
          // Server Components cannot always mutate cookies; middleware handles refresh persistence.
        }
      },
    },
  )
}
