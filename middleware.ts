import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request })
  const host = request.headers.get('host')?.split(':')[0].toLowerCase() || ''
  const rootHost = (process.env.NEXT_PUBLIC_ROOT_DOMAIN || 'vsbill.com').toLowerCase().replace(/^https?:\/\//, '').replace(/\/$/, '')
  const isLocalShop = host.endsWith('.localhost') && host !== 'localhost'
  const isWildcardShop = (host.endsWith(`.${rootHost}`) && host !== `www.${rootHost}`) || isLocalShop
  if (isWildcardShop && !request.nextUrl.pathname.startsWith('/shop/')) {
    const slug = isLocalShop ? host.slice(0, -'.localhost'.length) : host.slice(0, -(rootHost.length + 1))
    if (slug && !slug.includes('.')) {
      const url = request.nextUrl.clone()
      url.pathname = `/shop/${slug}${request.nextUrl.pathname === '/' ? '' : request.nextUrl.pathname}`
      response = NextResponse.rewrite(url)
    }
  }

  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    cookies: { getAll: () => request.cookies.getAll(), setAll: (items) => items.forEach(({ name, value, options }) => { request.cookies.set(name, value); response.cookies.set(name, value, options) }) },
  })
  await supabase.auth.getUser()
  response.headers.set('X-Content-Type-Options', 'nosniff')
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
  response.headers.set('X-Frame-Options', 'SAMEORIGIN')
  response.headers.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
  response.headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.youtube.com https://www.youtube-nocookie.com https://www.gstatic.com https://accounts.google.com; frame-src 'self' https://www.youtube.com https://www.youtube-nocookie.com https://accounts.google.com; connect-src 'self' https://*.supabase.co https://api.paystack.co https://www.googleapis.com https://accounts.google.com https://api.fingerprint.com; img-src 'self' data: blob: https:; style-src 'self' 'unsafe-inline'; font-src 'self' data: https:; base-uri 'self'; form-action 'self' https://accounts.google.com")
  if (process.env.NODE_ENV === 'production') response.headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
  return response
}

export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'] }
