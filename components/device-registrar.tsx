'use client'
import { useEffect } from 'react'
import FingerprintJS from '@fingerprintjs/fingerprintjs'

export default function DeviceRegistrar() {
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const fp = await FingerprintJS.load()
        const result = await fp.get()
        if (!cancelled) await fetch('/api/device/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ visitor_id: result.visitorId }) })
      } catch {}
    })()
    return () => { cancelled = true }
  }, [])
  return null
}
