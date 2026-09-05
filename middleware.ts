import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request })
  const host = request.headers.get('host')?.split(':')[0].toLowerCase() || ''
  const rootHost = process.env.NEXT_PUBLIC_ROOT_DOMAIN?.toLowerCase() || 'vsbill.com'
  const isWildcardShop = host.endsWith(`.${rootHost}`) && host !== `www.${rootHost}`
  if (isWildcardShop && !request.nextUrl.pathname.startsWith('/shop/')) {
    const slug = host.slice(0, -(rootHost.length + 1))
    if (slug && !slug.includes('.')) {
      const url = request.nextUrl.clone()
      url.pathname = `/shop/${slug}${request.nextUrl.pathname === '/' ? '' : request.nextUrl.pathname}`
      return NextResponse.rewrite(url)
    }
  }
  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!, {
    cookies: { getAll: () => request.cookies.getAll(), setAll: (items) => items.forEach(({ name, value, options }) => { request.cookies.set(name, value); response.cookies.set(name, value, options) }) },
  })
  await supabase.auth.getUser()
  return response
}

export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'] }
