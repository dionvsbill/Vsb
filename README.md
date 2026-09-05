# VSBILL Creator Growth Platform

VSBILL is a Ghana-ready creator growth and commerce platform. The YouTube area is the **Creator Promo Hub**. Campaigns use the label **TrueView Promo Campaigns (via Google Ads)** and worker activities use **Discovery & Engagement Tasks**.

## Google verification statement

We help creators grow via TrueView ad promotion and organic engagement tasks. No incentivized exchange.

## Stack

- Next.js 14 App Router + TypeScript
- Tailwind CSS + Framer Motion + Lucide
- Supabase Postgres/Auth/Realtime/Storage with RLS
- Paystack GHS payments
- Google OAuth + YouTube Data API v3
- FingerprintJS device controls
- Vercel Cron
- Meta Cloud API-ready WhatsApp integration with an explicit development/mock state until real credentials are configured

## Production flows

Registration requires email verification, Google/YouTube connection and a GHS 160 Paystack payment before activation. Entry allocations are 20% referral, 70% platform and 10% user cashback. Payment verification is server-side and webhook processing is idempotent.

Creator task verification records playback, foreground visibility, activity signals and required engagement verification. Fraud strikes are recorded server-side and recurring YouTube audits can revoke invalid engagement.

Shop owners can create a storefront, manage products and orders, use JForce import with graceful manual fallback, and use escrow-style settlement functions. Free shops support up to 20 products and 100 WhatsApp conversations; Pro is GHS 149/month plus GHS 100 setup with the configured usage limits and fees.

## Local setup

1. Copy `.env.example` to `.env.local` and fill every required provider secret.
2. Configure Supabase Auth email verification and the project Data API/RLS.
3. Enable YouTube Data API v3 and configure OAuth scopes `youtube.readonly` and `youtube.force-ssl`.
4. Configure Paystack public/secret keys and the `/api/paystack/webhook` endpoint.
5. Configure FingerprintJS and Upstash before production traffic.
6. For WhatsApp, configure Meta Cloud API credentials only on the server and complete provider webhook verification before enabling real traffic.
7. Run `npm install`, `npm run typecheck`, `npm run build`, then `npm start`.

## Security

Never commit `.env` files or Supabase secret keys. Browser code must use only the publishable Supabase key. Sensitive provider credentials and YouTube refresh credentials stay server-side/encrypted. Wallet mutations are never accepted as trusted client values. Use RLS and database atomic functions for financial state transitions.

## Deployment

`vercel.json` schedules the six-hour YouTube audit and hourly registration-expiry job. A custom wildcard domain can be configured with `NEXT_PUBLIC_ROOT_DOMAIN`; requests to `<shop>.vsbill.com` are rewritten to `/shop/<shop>` by middleware.

## Status

Provider-dependent features intentionally show a not-connected/development state until real credentials are present. The application does not fabricate successful payments, wallet credits or WhatsApp connections.
