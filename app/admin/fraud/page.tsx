'use client'
import { useEffect, useState } from 'react'

export default function FraudAdminPage() {
  const [rows,setRows]=useState<any[]>([]); const [error,setError]=useState('')
  async function load(){const r=await fetch('/api/admin/fraud');const d=await r.json();if(!r.ok) return setError(d.error||'Unable to load fraud records');setRows(d.strikes||[])}
  useEffect(()=>{load()},[])
  async function ban(userId:string){const r=await fetch('/api/admin/fraud',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({user_id:userId,action:'ban'})});if(!r.ok){const d=await r.json();setError(d.error||'Action failed');return}load()}
  return <main className="mx-auto max-w-6xl px-6 py-10"><h1 className="text-3xl font-black">Fraud review</h1>{error&&<p className="mt-4 rounded-xl bg-red-50 p-4 text-red-700">{error}</p>}<div className="mt-6 overflow-x-auto rounded-2xl border bg-white"><table className="w-full text-left text-sm"><thead><tr className="border-b"><th className="p-4">User</th><th className="p-4">Reason</th><th className="p-4">Created</th><th className="p-4">Action</th></tr></thead><tbody>{rows.map((x)=><tr key={x.id} className="border-b last:border-0"><td className="p-4">{x.user_id}</td><td className="p-4">{x.reason}</td><td className="p-4">{new Date(x.created_at).toLocaleString()}</td><td className="p-4"><button onClick={()=>ban(x.user_id)} className="rounded-lg bg-red-600 px-3 py-2 font-bold text-white">Ban</button></td></tr>)}</tbody></table></div></main>
}
