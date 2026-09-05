# VSBILL production requirements

## Launch gate

Production means version-controlled Supabase migrations, RLS, authenticated/authorized APIs, payment webhooks, idempotency, integer money accounting, atomic inventory, payout reconciliation, audit logging, provider verification, CI and browser tests.

## Creator Promo Hub compliance

VSBILL must not pay or otherwise incentivize users to manufacture YouTube views, likes, subscriptions, comments, or other artificial engagement. Promotion uses legitimate Google Ads/TrueView promotion and organic discovery/feedback that does not require an engagement action. APIs must reject manipulative task types.

Public verification wording: “We help creators grow via TrueView ad promotion and organic engagement tasks. No incentivized exchange.”

The business model must receive current Google/YouTube policy and applicable Ghana legal review before launch.

## Money

New financial operations use integer minor units: GHS 160.00 = 16000 pesewas; USD 0.10 = 10 cents. Browser input never sets balances, fees, rewards, order totals or payout amounts. PostgreSQL transactions/functions perform ledger mutations. Every external payment event is durable and idempotent.

## Task state machine

`assigned -> watching -> submitted -> verified -> paid`; recovery states: `expired`, `abandoned`, `rejected`, `revoked`, `reversed`. The browser cannot choose worker identity, reward amount, owner, completion count or verification status. Sessions use nonce, expiry, server heartbeats and evidence.

## Commerce

Server-side quotes calculate product totals and delivery. Order creation must lock inventory, snapshot prices, validate stock and use an idempotency key. Payment webhooks are authoritative. Seller funds remain pending until settlement and fees are atomically applied.

## WhatsApp and JForce

WhatsApp remains Development/Not connected until Meta credentials and webhook verification exist. Secrets are encrypted and never exposed to the browser. JForce must use an authorized API; otherwise manual import is the only fallback.

## Security

All inputs are validated, authenticated, authorized and rate-limited. Sensitive actions create audit records. Production dependencies are pinned. Launch requires passing typecheck, build, migration, RLS, payment, security and end-to-end tests.
