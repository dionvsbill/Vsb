# VSBIL TUBE BOOST

Premium YouTube campaign marketplace for verified watch, like and subscription workflows.

## Stack

- Next.js 14 App Router + TypeScript
- Tailwind CSS + Framer Motion + Lucide/shadcn-ready UI architecture
- Supabase Postgres/Auth/Realtime/Storage
- Paystack GHS payments and transfers
- YouTube Data API v3 + Google OAuth
- Render deployment compatible; Vercel Cron can call the same protected cron endpoints

## Current foundation

The Supabase production schema is provisioned in project `fatahmvxrtwytfxejmvu` with RLS on all 13 public tables, protected wallet functions, campaign/payment records, referrals, violations, payouts, audit logs and data-rights requests.

Financial values are never accepted from browser JavaScript as wallet mutations. Server-only privileged operations and Postgres functions control ledger changes.

## Local setup

1. Install Node.js 20+.
2. Copy `.env.example` to `.env.local`.
3. Create a Supabase project and configure Auth email verification.
4. Create a Google Cloud OAuth client for a Web application. Add the exact callback URL used by the Google OAuth route when it is enabled, and enable YouTube Data API v3.
5. Create Paystack API keys. Keep the secret key server-side only. Configure the webhook URL to `/api/paystack/webhook`.
6. Configure Upstash Redis for distributed rate limiting before production traffic.
7. `npm install`
8. `npm run typecheck`
9. `npm run build`
10. `npm start`

## Security

Never commit `.env` files or Supabase secret/service keys. Supabase publishable keys may be used in the browser only with correct RLS; secret keys must remain server-side. See Supabase's security guidance for the distinction.

## Payment model

Default platform settings are $10 entry fee / GHS 160, 20% referral commission, 10% new-user cashback, 70% platform allocation, 10% campaign commission and $5 minimum withdrawal with a 2% withdrawal fee. Settings are stored in `platform_settings` and can be changed by a superadmin through the application.

## Important production verification

Before launch, configure real provider credentials, verify Google OAuth consent-screen requirements, test Paystack webhook signatures and idempotency, configure distributed rate limiting, complete YouTube OAuth token storage using Supabase Vault, and run database security/performance advisors. The repository deliberately contains no provider secrets or fake production credentials.
