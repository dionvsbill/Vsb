# VSBILL Creator Growth Platform

VSBILL is a Ghana-ready creator promotion, feedback and commerce platform. The creator area is intentionally policy-gated: it does **not** pay users to manufacture YouTube views, likes, subscriptions, comments or other artificial engagement. Creator campaigns are limited to policy-reviewed discovery/feedback and legitimate paid promotion integrations.

## Stack

- Next.js App Router + TypeScript
- Tailwind CSS + Framer Motion + Lucide
- Supabase Postgres/Auth/Realtime/Storage with RLS
- Paystack GHS payments
- Google OAuth + YouTube Data API v3
- FingerprintJS + Upstash Redis
- Render Web Service + Render Cron Jobs
- Meta Cloud API WhatsApp (Not Connected until real credentials are configured)

## Production architecture

Registration is email verification -> YouTube connection -> server-created Paystack activation payment -> webhook verification -> atomic allocation -> activation. Money is stored in integer minor units and wallet mutations happen only through privileged database functions.

Creator tasks use a server-bounded session and heartbeat state machine. Browser values are evidence only; the server controls task ownership, state, elapsed time, reward and wallet credit.

Shop checkout uses server-generated quotes, atomic stock reservation and Paystack verification. Seller funds are held until settlement. JForce import only runs when an authorized provider endpoint is configured; otherwise the API returns a manual-import fallback instead of pretending an integration exists.

WhatsApp uses Meta Cloud API only when server credentials are configured. Incoming webhooks are signature-checked and duplicate provider message IDs are ignored by the database.

## Render deployment

VSBILL is deployed on **Render**, not Vercel. `render.yaml` defines the web service plus the six-hour YouTube audit and hourly registration-expiry cron jobs. Render cron schedules use UTC and are separate services.

Set every secret from `.env.example` in Render. Never commit `.env` files or service-role credentials. Run Supabase migrations from the repository before accepting production traffic.

## Supabase

The migration directory is replayable from an empty project. The canonical financial tables are `wallet_accounts` and `wallet_entries`; legacy decimal balance fields are compatibility data and are not mutated by new financial code. All sensitive provider events are idempotent.

## Compliance

Public verification statement: “We help creators grow via TrueView ad promotion and organic engagement tasks. No incentivized exchange.” The application blocks manipulative YouTube task types. Current YouTube policy should be reviewed before launch. YouTube explicitly prohibits artificial increases in views/likes/comments/subscribers and content that exists solely to incentivize engagement.
