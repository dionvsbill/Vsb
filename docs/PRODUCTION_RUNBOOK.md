# VSBILL production launch runbook

This repository is production-oriented and must use real provider credentials. No mock payment success, fake balances, fake campaign completion, or fabricated social-provider status is permitted.

## Before launch

1. Create a production Supabase project and apply every migration in `supabase/migrations` in filename order.
2. Verify RLS on every exposed table and test ownership boundaries with two separate users.
3. Configure Supabase Auth redirect URLs for the final Render domain.
4. Configure Paystack live keys and the webhook endpoint. Verify webhook signatures and replay/idempotency behavior with Paystack test events before enabling live traffic.
5. Configure Google OAuth and YouTube API credentials. Test consent, callback, token refresh, revocation and encrypted credential storage.
6. Configure Upstash Redis and FingerprintJS for rate limiting and device-risk controls.
7. Generate a unique 32-byte `ENCRYPTION_KEY` and a long random `CRON_SECRET`. Never reuse development secrets.
8. Configure Render from `render.yaml`; use `/api/health` as the web health check.
9. Configure only social advertising providers whose production API credentials, permissions and policy review are complete. The application must report other providers as `not_configured` rather than pretending they are active.

## Financial acceptance tests

- Client-side changes cannot alter balances, fees, rewards or payment totals.
- Every money value is stored in integer minor units.
- Replaying the same payment webhook does not create a second ledger mutation.
- A mismatched amount, currency, reference or user cannot settle a transaction.
- Failed payment initialization leaves the transaction and campaign in a recoverable state.
- Concurrent requests with the same idempotency key produce one authoritative result.

## Campaign acceptance tests

- Campaigns require authenticated, verified and non-banned accounts.
- Only policy-approved promotion modes are accepted.
- Campaign configuration is read from server-side settings and plans.
- YouTube content is validated server-side before payment initialization.
- Campaign approval is an audited server-side state transition.
- Worker/task identity, reward, completion and verification status cannot be supplied by the browser.
- Expired, rejected, revoked and reversed tasks cannot be paid.

## Security acceptance tests

Attempt every sensitive operation through direct HTTP requests, not only the UI:

- cross-user campaign access
- cross-user task submission
- altered reward values
- altered quantities and prices
- duplicate payment/webhook events
- replayed idempotency keys with a different request body
- expired task heartbeats
- unauthorized admin actions
- forged cron requests
- oversized JSON payloads and malformed IDs
- rate-limit bypasses

## Deployment gate

The launch commit must pass typecheck and production build in GitHub Actions. After Render deploys, verify `/api/health`, authentication, Paystack sandbox/live flow, webhook delivery, campaign moderation and the relevant provider integrations using real test accounts.

A green build is not proof that external credentials are configured. A provider is considered live only after a real end-to-end transaction or API operation has been verified in its production-approved environment.
