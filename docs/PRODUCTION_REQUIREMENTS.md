# VSBILL production requirements

## Launch gate

Production means version-controlled Supabase migrations, RLS, authenticated/authorized APIs, payment webhooks, idempotency, integer money accounting, atomic inventory, payout reconciliation, audit logging, provider verification, CI and browser tests.

## Creator Promo Hub compliance

VSBILL must not pay or otherwise incentivize users to manufacture YouTube views, likes, subscriptions, comments, or other artificial engagement. Promotion uses legitimate paid advertising when a real Google Ads integration is configured and policy-reviewed discovery/feedback activities that do not require an engagement action. APIs reject manipulative task types.

Public verification wording: “We help creators grow via TrueView ad promotion and organic engagement tasks. No incentivized exchange.”

## Money

New financial operations use integer minor units: GHS 160.00 = 16000 pesewas; USD 0.10 = 10 cents. Browser input never sets balances, fees, rewards, order totals or payout amounts. PostgreSQL transactions/functions perform ledger mutations. Every external payment event is durable and idempotent.

## Task state machine

`assigned -> watching -> submitted -> verified -> paid`; recovery states: `expired`, `abandoned`, `rejected`, `revoked`, `reversed`. The browser cannot choose worker identity, reward amount, owner, completion count or verification status. Sessions use nonce, expiry, server-bounded heartbeats and evidence.

## Commerce

Server-side quotes calculate product totals and delivery. Order creation locks inventory, snapshots prices, validates stock and uses an idempotency key. Payment webhooks are authoritative. Seller funds remain pending until settlement and fees are atomically applied.

## Providers

WhatsApp is Not Connected until Meta credentials and webhook verification exist. JForce only runs against an authorized API configured with `JFORCE_API_URL` and `JFORCE_API_TOKEN`; otherwise manual import is returned. Google Ads must not be described as active until its real API integration exists.

## Render

Render is the production platform. Scheduled work is implemented as Render Cron services in `render.yaml`; there is no Vercel cron dependency.

## Security

All inputs are validated, authenticated, authorized and rate-limited. Sensitive actions create audit records. Production dependencies are pinned. Launch requires passing typecheck, build, migration, RLS, payment, security and end-to-end tests.
