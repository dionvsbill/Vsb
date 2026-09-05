'use client'
import { FormEvent, useState } from 'react'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'

export default function LoginPage(){
 const [email,setEmail]=useState(''); const [password,setPassword]=useState(''); const [error,setError]=useState(''); const [loading,setLoading]=useState(false)
 async function submit(e:FormEvent){e.preventDefault();setError('');setLoading(true);const {error}=await createClient().auth.signInWithPassword({email,password});setLoading(false);if(error){setError(error.message);return}window.location.href='/dashboard'}
 return <main className="flex min-h-screen items-center justify-center px-6"><form onSubmit={submit} className="glass w-full max-w-md rounded-2xl p-8 shadow-premium"><h1 className="text-3xl font-black">Welcome back</h1><p className="mt-2 text-slate-500">Sign in to VSBILL.</p><label className="mt-7 block text-sm font-semibold">Email<input required type="email" value={email} onChange={e=>setEmail(e.target.value)} className="mt-2 w-full rounded-xl border bg-transparent px-4 py-3 outline-none"/></label><label className="mt-4 block text-sm font-semibold">Password<input required type="password" value={password} onChange={e=>setPassword(e.target.value)} className="mt-2 w-full rounded-xl border bg-transparent px-4 py-3 outline-none"/></label>{error&&<p className="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}<button disabled={loading} className="mt-6 w-full rounded-xl bg-slate-950 px-4 py-3 font-bold text-white disabled:opacity-50 dark:bg-white dark:text-slate-950">{loading?'Signing in…':'Sign in'}</button><p className="mt-6 text-center text-sm text-slate-500">New here? <Link className="font-bold text-red-600" href="/register">Create an account</Link></p></form></main>
}
