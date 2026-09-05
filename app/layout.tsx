import './globals.css'
import type { Metadata } from 'next'
import DeviceRegistrar from '@/components/device-registrar'

export const metadata: Metadata = {
  title: { default: 'VSBILL', template: '%s | VSBILL' },
  description: 'Ghana-ready creator promotion, feedback and commerce platform.',
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL || 'http://localhost:3000'),
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en" suppressHydrationWarning><body><DeviceRegistrar />{children}</body></html>
}
