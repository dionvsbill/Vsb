import './globals.css'
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: { default: 'VSBIL TUBE BOOST', template: '%s | VSBIL TUBE BOOST' },
  description: 'A premium YouTube campaign marketplace for verified watch, like and subscriber engagement.',
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'),
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en" suppressHydrationWarning><body>{children}</body></html>
}
