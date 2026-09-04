import Link from 'next/link'
import { ArrowRight, CheckCircle2, ShieldCheck, PlayCircle, WalletCards, Users } from 'lucide-react'

const features = [
  ['Verified engagement', 'Tasks are tied to connected YouTube identities and server-side verification.'],
  ['Protected earnings', 'Wallet changes are controlled by backend/database functions—not browser code.'],
  ['Transparent campaigns', 'Advertisers see progress, cost, approvals and completion status in one place.'],
]

export default function Home() {
  return <main>
    <nav className="mx-auto flex max-w-7xl items-center justify-between px-6 py-5">
      <Link href="/" className="text-xl font-black tracking-tight">VSBIL <span className="gradient-text">TUBE BOOST</span></Link>
      <div className="flex gap-3"><Link href="/login" className="rounded-xl px-4 py-2 text-sm font-semibold">Log in</Link><Link href="/register" className="rounded-xl bg-slate-950 px-4 py-2 text-sm font-semibold text-white dark:bg-white dark:text-slate-950">Get started</Link></div>
    </nav>
    <section className="mx-auto max-w-7xl px-6 pb-24 pt-16 text-center">
      <div className="mx-auto mb-6 inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm"><ShieldCheck className="h-4 w-4"/> Built for verified YouTube campaigns</div>
      <h1 className="mx-auto max-w-5xl text-5xl font-black tracking-tight md:text-7xl">Grow YouTube channels with <span className="gradient-text">real, verified activity.</span></h1>
      <p className="mx-auto mt-6 max-w-2xl text-lg leading-8 text-slate-600 dark:text-slate-300">VSBIL TUBE BOOST connects campaign owners with verified participants for watch, like and subscription tasks—with fraud controls and transparent earnings.</p>
      <div className="mt-9 flex flex-col justify-center gap-3 sm:flex-row"><Link href="/register" className="inline-flex items-center justify-center gap-2 rounded-2xl bg-red-600 px-6 py-4 font-bold text-white shadow-premium">Start for $10 <ArrowRight className="h-5 w-5"/></Link><Link href="/how-it-works" className="inline-flex items-center justify-center gap-2 rounded-2xl border px-6 py-4 font-bold"><PlayCircle className="h-5 w-5"/> How it works</Link></div>
    </section>
    <section className="mx-auto grid max-w-7xl gap-5 px-6 pb-24 md:grid-cols-3">{features.map(([title,copy],i)=><article key={title} className="glass rounded-2xl p-7 shadow-premium"><div className="mb-5 flex h-11 w-11 items-center justify-center rounded-xl bg-slate-100 dark:bg-slate-800">{i===0?<CheckCircle2/>:i===1?<WalletCards/>:<Users/>}</div><h2 className="text-xl font-bold">{title}</h2><p className="mt-2 leading-7 text-slate-600 dark:text-slate-300">{copy}</p></article>)}</section>
    <section className="border-y bg-slate-950 px-6 py-20 text-white"><div className="mx-auto max-w-4xl text-center"><p className="text-sm font-bold uppercase tracking-[.25em] text-red-400">Simple entry</p><h2 className="mt-3 text-4xl font-black">One $10 registration fee. Then unlock the platform.</h2><p className="mx-auto mt-4 max-w-2xl text-slate-300">20% referral commission, 10% instant entry cashback, and a structured marketplace for earning through verified tasks.</p><Link href="/pricing" className="mt-7 inline-flex rounded-2xl bg-white px-6 py-3 font-bold text-slate-950">See pricing</Link></div></section>
    <footer className="mx-auto flex max-w-7xl flex-col gap-4 px-6 py-10 text-sm text-slate-500 md:flex-row md:items-center md:justify-between"><span>© 2026 VSBIL TUBE BOOST</span><div className="flex gap-5"><Link href="/terms">Terms</Link><Link href="/privacy">Privacy</Link><Link href="/guidelines">Guidelines</Link><Link href="/contact">Contact</Link></div></footer>
  </main>
}
