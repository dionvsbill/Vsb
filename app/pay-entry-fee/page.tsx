'use client'
import { useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useEffect } from 'react'

export default function PayEntryFee(){
 const params=useSearchParams(); const ref=params.get('reference'); const [status,setStatus]=useState(ref?'Verifying your payment…':'Ready to unlock your account.'); const [loading,setLoading]=useState(false)
 useEffect(()=>{if(!ref)return;fetch('/api/paystack/verify',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({reference:ref})}).then(r=>r.json()).then(d=>{if(d.success){setStatus('Payment confirmed. Your account is now active.');setTimeout(()=>location.href='/dashboard',900)}else setStatus(d.error||'Payment could not be confirmed.')}).catch(()=>setStatus('Could not verify payment. Please try again.'))},[ref])
 async function pay(){setLoading(true);const r=await fetch('/api/paystack/initialize',{method:'POST'});const d=await r.json();if(!r.ok){setStatus(d.error||'Unable to start payment');setLoading(false);return}location.href=d.authorization_url}
 return <main className="flex min-h-screen items-center justify-center px-6"><section className="glass w-full max-w-lg rounded-2xl p-8 text-center shadow-premium"><p className="text-sm font-bold uppercase tracking-widest text-red-600">Account activation</p><h1 className="mt-3 text-4xl font-black">Unlock VSBIL TUBE BOOST</h1><p className="mt-4 text-slate-500">Pay the configured $10-equivalent GHS entry fee through Paystack. Payment is verified on our server before earnings are enabled.</p><div className="my-8 rounded-2xl bg-slate-100 p-6 dark:bg-slate-800"><div className="text-4xl font-black">$10</div><div className="mt-1 text-sm text-slate-500">GHS equivalent at the platform rate</div></div>{status&&<p className="mb-5 text-sm font-medium">{status}</p>}<button onClick={pay} disabled={loading||!!ref} className="w-full rounded-xl bg-red-600 px-5 py-3 font-bold text-white disabled:opacity-50">{loading?'Connecting to Paystack…':'Pay & activate'}</button></section></main>
}
