'use client'
import { useState } from 'react'

export default function WhatsAppBot({params}:{params:{id:string}}){
 const [enabled,setEnabled]=useState(false)
 return <main className="min-h-screen bg-slate-50 p-5 dark:bg-slate-950"><div className="mx-auto max-w-4xl"><div className="rounded-2xl border border-amber-300 bg-amber-50 p-5 text-amber-900"><b>Legacy module disabled</b><p className="mt-1 text-sm">WhatsApp is not part of the current VSBILL campaign product and is intentionally unavailable.</p></div><button onClick={()=>setEnabled(v=>!v)} className="mt-6 rounded-xl border px-4 py-2 font-bold">{enabled?'Enabled':'Disabled'}</button></div></main>
}
