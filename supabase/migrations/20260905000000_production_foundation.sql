begin;
create extension if not exists pgcrypto;

-- Canonical enums used by the application.
do $$ begin create type public.user_role as enum ('user','admin','superadmin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.transaction_type as enum ('entry_fee','task_earning','referral_earning','campaign_payment','withdrawal','revocation','refund','adjustment'); exception when duplicate_object then null; end $$;
do $$ begin create type public.transaction_status as enum ('pending','success','failed','reversed'); exception when duplicate_object then null; end $$;
do $$ begin create type public.campaign_status as enum ('pending_approval','approved','active','paused','completed','rejected','cancelled'); exception when duplicate_object then null; end $$;
do $$ begin create type public.task_status as enum ('assigned','watching','verifying','completed','revoked','fraud','expired'); exception when duplicate_object then null; end $$;
do $$ begin create type public.violation_type as enum ('unsubscribe','unlike','fake_watch','multi_account','device_abuse','payment_abuse','captcha_failure','other'); exception when duplicate_object then null; end $$;
do $$ begin create type public.payout_method as enum ('momo','bank'); exception when duplicate_object then null; end $$;
do $$ begin create type public.payout_status as enum ('pending','approved','processing','paid','failed','rejected'); exception when duplicate_object then null; end $$;

-- Baseline application schema. Foreign keys are added after all tables exist so a
-- clean Supabase project can replay the repository deterministically.
create table if not exists public.users (
  id uuid primary key,
  email text not null,
  name text not null default '', avatar_url text,
  referral_code text not null unique, referred_by uuid,
  youtube_channel_id text unique, youtube_channel_title text,
  youtube_subscriber_count bigint not null default 0 check (youtube_subscriber_count >= 0),
  youtube_access_secret_id uuid, youtube_refresh_secret_id uuid, youtube_connected_at timestamptz,
  role public.user_role not null default 'user', is_paid boolean not null default false,
  entry_fee_paid_at timestamptz, entry_fee_expires_at timestamptz not null default (now()+interval '24 hours'),
  balance numeric not null default 0 check (balance >= 0), total_earned numeric not null default 0 check (total_earned >= 0),
  total_withdrawn numeric not null default 0 check (total_withdrawn >= 0), strikes integer not null default 0 check (strikes between 0 and 3),
  is_banned boolean not null default false, banned_until timestamptz, blacklist_reason text,
  device_fingerprint text unique, last_ip inet, phone_hash text unique, email_verified_at timestamptz, deactivated_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.platform_settings (
  id boolean primary key default true check (id), entry_fee_usd numeric not null default 10 check(entry_fee_usd>0),
  entry_fee_ghs numeric not null default 160 check(entry_fee_ghs>0), referral_percent numeric not null default 20 check(referral_percent between 0 and 100),
  cashback_percent numeric not null default 10 check(cashback_percent between 0 and 100), platform_entry_percent numeric not null default 70 check(platform_entry_percent between 0 and 100),
  campaign_commission_percent numeric not null default 10 check(campaign_commission_percent between 0 and 100), minimum_withdrawal_usd numeric not null default 5 check(minimum_withdrawal_usd>0),
  withdrawal_fee_percent numeric not null default 2 check(withdrawal_fee_percent between 0 and 100), watch_grace_seconds integer not null default 10 check(watch_grace_seconds>=0),
  updated_at timestamptz not null default now(), entry_fee_minor bigint,
  campaign_min_quantity integer, campaign_max_quantity integer, campaign_min_cost_cents integer, campaign_max_cost_cents integer,
  campaign_platform_fee_bps integer, task_session_ttl_seconds integer, task_heartbeat_interval_seconds integer,
  task_inactivity_timeout_seconds integer, config_version bigint
);
create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(), code text not null unique, name text not null,
  monthly_price_minor bigint not null default 0 check(monthly_price_minor>=0), setup_fee_minor bigint not null default 0 check(setup_fee_minor>=0),
  product_limit integer not null default 20 check(product_limit>0), monthly_conversation_limit integer not null default 100 check(monthly_conversation_limit>=0),
  shop_fee_bps integer not null default 500 check(shop_fee_bps between 0 and 10000), extra_conversation_minor bigint not null default 50 check(extra_conversation_minor>=0),
  active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  min_cost_cents integer, max_cost_cents integer
);
create table if not exists public.fx_rates (
  id uuid primary key default gen_random_uuid(), base_currency text not null, quote_currency text not null,
  rate_numeric numeric not null check(rate_numeric>0), effective_from timestamptz not null default now(), effective_to timestamptz,
  source text not null default 'manual', created_at timestamptz not null default now()
);
create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(), provider text not null, event_type text not null, event_id text,
  signature_valid boolean not null default false, payload jsonb not null default '{}',
  processing_status text not null default 'received' check(processing_status in ('received','processing','processed','failed','ignored')),
  error_message text, processed_at timestamptz, created_at timestamptz not null default now(), unique(provider,event_id)
);
create table if not exists public.idempotency_keys (
  id uuid primary key default gen_random_uuid(), scope text not null, key text not null, request_hash text,
  response_status integer, response_body jsonb, locked_at timestamptz, expires_at timestamptz not null default(now()+interval '24 hours'),
  created_at timestamptz not null default now(), unique(scope,key)
);
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, type public.transaction_type not null,
  amount numeric not null check(amount>0), currency text not null default 'GHS', paystack_ref text unique,
  status public.transaction_status not null default 'pending', metadata jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  amount_minor bigint, idempotency_key text, webhook_event_id uuid, provider text default 'paystack'
);
create table if not exists public.wallets (
  user_id uuid primary key, available numeric not null default 0 check(available>=0), reserved_campaign numeric not null default 0 check(reserved_campaign>=0),
  pending_shop numeric not null default 0 check(pending_shop>=0), updated_at timestamptz not null default now(), cash_wallet numeric not null default 0,
  credit_wallet numeric not null default 0, pending_shop_balance numeric not null default 0, available_shop_balance numeric not null default 0
);
create table if not exists public.wallet_ledger (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, entry_type text not null, amount numeric not null,
  balance_after numeric not null, reference_id uuid, description text, created_at timestamptz not null default now(), amount_minor bigint, balance_after_minor bigint, idempotency_key text
);
create table if not exists public.wallet_accounts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null unique, balance_minor bigint not null default 0 check(balance_minor>=0),
  pending_minor bigint not null default 0 check(pending_minor>=0), reserved_minor bigint not null default 0 check(reserved_minor>=0), currency text not null default 'GHS' check(currency='GHS'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.wallet_entries (
  id uuid primary key default gen_random_uuid(), wallet_id uuid not null, amount_minor bigint not null check(amount_minor<>0),
  balance_after_minor bigint not null check(balance_after_minor>=0), entry_type text not null, reference_type text, reference_id uuid,
  idempotency_key text, metadata jsonb not null default '{}', created_at timestamptz not null default now(), unique(wallet_id,idempotency_key)
);
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, youtube_video_id text not null, youtube_video_title text not null,
  youtube_channel_id text, thumbnail text, duration_seconds integer not null default 0 check(duration_seconds>=0), task_types text[] not null default '{watch}',
  required_watch_percent numeric not null default 100 check(required_watch_percent>0 and required_watch_percent<=100), quantity integer not null check(quantity>0), completed_count integer not null default 0,
  cost_per_task numeric not null check(cost_per_task>0), total_budget numeric not null check(total_budget>0), platform_fee numeric not null default 0 check(platform_fee>=0),
  status public.campaign_status not null default 'pending_approval', rejection_reason text, approved_by uuid, approved_at timestamptz, starts_at timestamptz, ends_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), comment_options text[] not null default '{}',
  cost_per_task_minor bigint, total_budget_minor bigint, platform_fee_minor bigint, total_charge_minor bigint, currency text not null default 'USD',
  promotion_mode text not null default 'google_ads', policy_review_status text not null default 'pending'
);
create table if not exists public.watch_tasks (
  id uuid primary key default gen_random_uuid(), campaign_id uuid not null, worker_id uuid not null, status public.task_status not null default 'assigned',
  watch_start timestamptz, watch_end timestamptz, watch_duration_verified numeric not null default 0, watch_percent_verified numeric not null default 0,
  liked_verified boolean not null default false, subscribed_verified boolean not null default false, comment_verified boolean not null default false, captcha_passed boolean not null default false,
  visibility_failures integer not null default 0, mouse_activity_score numeric not null default 0, ip_address inet, device_fingerprint text,
  fraud_score numeric not null default 0 check(fraud_score between 0 and 100), evidence jsonb not null default '{}', earning_amount numeric not null default 0,
  created_at timestamptz not null default now(), completed_at timestamptz, revoked_at timestamptz, ip inet, fingerprint text, earning_amount_minor bigint, updated_at timestamptz not null default now()
);
create table if not exists public.task_sessions (
  id uuid primary key default gen_random_uuid(), task_id uuid not null, worker_id uuid not null, campaign_id uuid not null, nonce_hash text not null unique,
  started_at timestamptz not null default now(), expires_at timestamptz not null, last_heartbeat_at timestamptz, visibility_failures integer not null default 0,
  seek_events integer not null default 0, playback_seconds numeric(12,3) not null default 0, status text not null default 'active' check(status in ('active','expired','submitted','verified','rejected','cancelled')),
  evidence jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.task_heartbeats (
  id uuid primary key default gen_random_uuid(), session_id uuid not null, client_time_seconds numeric(12,3) not null check(client_time_seconds>=0),
  visibility_state text not null check(visibility_state in ('visible','hidden','prerender','unloaded')), playback_rate numeric(6,3) not null default 1 check(playback_rate>0 and playback_rate<=4),
  seek_detected boolean not null default false, mouse_activity boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(), referrer_id uuid not null, referred_id uuid not null unique, entry_fee_amount numeric not null check(entry_fee_amount>0),
  commission_earned numeric not null default 0 check(commission_earned>=0), cashback_amount numeric not null default 0 check(cashback_amount>=0), created_at timestamptz not null default now()
);
create table if not exists public.violations (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, type public.violation_type not null, evidence jsonb not null default '{}', action_taken text not null, related_task_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.violation_logs (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, type public.violation_type not null, evidence jsonb not null default '{}', action_taken text not null, related_task_id uuid, created_at timestamptz not null default now()
);
create table if not exists public.payout_methods (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, method public.payout_method not null, account_name text not null, account_number text not null,
  bank_code text, provider text, is_default boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, payout_method_id uuid not null, amount numeric not null check(amount>0), fee numeric not null default 0 check(fee>=0),
  net_amount numeric not null check(net_amount>0), currency text not null default 'GHS', status public.payout_status not null default 'pending', paystack_transfer_code text, paystack_recipient_code text,
  admin_note text, processed_by uuid, processed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(), actor_id uuid, action text not null, target_type text, target_id uuid, ip_address inet, user_agent text, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(), actor_id uuid, target_user_id uuid, event_type text not null, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.data_rights_requests (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, request_type text not null check(request_type in ('export','delete','revoke_youtube')),
  status text not null default 'pending' check(status in ('pending','processing','completed','rejected')), notes text, created_at timestamptz not null default now(), completed_at timestamptz
);
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(), user_id uuid, email text not null, subject text not null, message text not null,
  status text not null default 'open' check(status in ('open','in_progress','resolved','closed')), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.business_shops (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, name text not null, phone text, address text, currency text not null default 'GHS', created_at timestamptz not null default now(),
  store_slug text, description text, logo_url text, banner_url text, momo_number text, delivery_fee numeric not null default 0, jforce_id text, is_published boolean not null default false,
  shop_status text not null default 'pending', is_pro boolean not null default false, pro_expires_at timestamptz
);
create table if not exists public.inventory_products (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, shop_id uuid not null, name text not null, sku text not null, quantity integer not null default 0 check(quantity>=0),
  selling_price numeric not null default 0 check(selling_price>=0), cost_price numeric not null default 0 check(cost_price>=0), reorder_level integer not null default 0 check(reorder_level>=0), unit text not null default 'piece',
  description text, image_url text, discount_percent numeric not null default 0 check(discount_percent between 0 and 100), is_published boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), category text, image_urls text[] not null default '{}', original_price numeric,
  source text, source_url text, source_product_id text, source_currency text, source_in_stock boolean, last_synced_at timestamptz, selling_price_minor bigint, cost_price_minor bigint
);
create table if not exists public.shop_customers (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, phone text not null, name text, email text, address text, order_count integer not null default 0 check(order_count>=0),
  total_spent numeric not null default 0 check(total_spent>=0), last_order_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.shop_orders (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, user_id uuid not null, order_number text not null unique, buyer_name text not null, buyer_phone text not null,
  buyer_email text, delivery_address text, delivery_note text, subtotal numeric not null default 0 check(subtotal>=0), discount_amount numeric not null default 0 check(discount_amount>=0), delivery_fee numeric not null default 0 check(delivery_fee>=0),
  total numeric not null default 0 check(total>=0), currency text not null default 'GHS', payment_method text not null default 'cash_on_delivery',
  payment_status text not null default 'unpaid', status text not null default 'pending', payment_reference text, tracking_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  idempotency_key text, subtotal_minor bigint, delivery_fee_minor bigint, total_minor bigint, quote_id uuid
);
create table if not exists public.shop_order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null, product_id uuid not null, product_name text not null, sku text not null, quantity integer not null check(quantity>0),
  unit_price numeric not null check(unit_price>=0), discount_percent numeric not null default 0, line_total numeric not null check(line_total>=0), created_at timestamptz not null default now()
);
create table if not exists public.shop_order_events (
  id uuid primary key default gen_random_uuid(), order_id uuid not null, status text not null, note text, created_at timestamptz not null default now()
);
create table if not exists public.shop_transactions (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, order_id uuid, user_id uuid, type text not null, amount numeric not null, currency text not null default 'GHS',
  status text not null default 'posted', reference text unique, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.shop_wallet_holds (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, order_id uuid not null unique, gross_amount numeric not null default 0, fee_amount numeric not null default 0, net_amount numeric not null,
  status text not null default 'held', held_at timestamptz not null default now(), released_at timestamptz
);
create table if not exists public.shop_settlements (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, order_id uuid not null unique, gross_amount numeric not null, platform_fee numeric not null default 0, net_amount numeric not null,
  status text not null default 'released', released_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table if not exists public.shop_subscriptions (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, user_id uuid not null, plan text not null default 'free', status text not null default 'active',
  amount_ghs numeric not null default 0, setup_fee_ghs numeric not null default 0, current_period_start timestamptz not null default now(), current_period_end timestamptz, provider_reference text unique,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.shop_subscription_usage (
  shop_id uuid primary key, product_count integer not null default 0 check(product_count>=0), conversations_used integer not null default 0 check(conversations_used>=0),
  period_start timestamptz not null default now(), period_end timestamptz, updated_at timestamptz not null default now()
);
create table if not exists public.shop_checkout_sessions (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, buyer_name text not null, buyer_phone text not null, buyer_email text, delivery_address text, delivery_note text,
  payment_method text not null, items jsonb not null, amount numeric not null check(amount>0), currency text not null default 'GHS', reference text not null unique,
  status text not null default 'pending', provider_transaction_id text, created_at timestamptz not null default now(), paid_at timestamptz
);
create table if not exists public.wallet_holds (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, order_id uuid, amount numeric not null default 0, fee numeric not null default 0,
  status text not null default 'held', created_at timestamptz not null default now(), released_at timestamptz
);
create table if not exists public.jforce_clicks (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, product_id uuid, affiliate_url text not null, referrer text, user_agent_hash text, ip_hash text, created_at timestamptz not null default now()
);
create table if not exists public.whatsapp_connections (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null unique, waba_id text, phone_number_id text, access_token_encrypted text, webhook_verify_token_encrypted text,
  status text not null default 'mock', display_phone_number text, last_error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.whatsapp_flows (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, name text not null, trigger_keyword text not null, nodes jsonb not null default '[]', is_enabled boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.whatsapp_conversations (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, customer_phone text not null, status text not null default 'open', started_at timestamptz not null default now(), last_message_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.whatsapp_messages_shop (
  id uuid primary key default gen_random_uuid(), conversation_id uuid not null, direction text not null, message_type text not null default 'text', body text,
  provider_message_id text unique, status text, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.whatsapp_shop_flows (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null, trigger_keyword text not null, action_type text not null, action_config jsonb not null default '{}', is_enabled boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.business_subscriptions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, product text not null, plan text not null, status text not null default 'active', starts_at timestamptz not null default now(), ends_at timestamptz not null, created_at timestamptz not null default now()
);
create table if not exists public.business_subscription_payments (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, purpose text not null, amount numeric not null check(amount>0), currency text not null default 'GHS', reference text not null unique,
  status text not null default 'pending', provider_transaction_id text, created_at timestamptz not null default now(), paid_at timestamptz
);

-- Foreign keys after all application tables exist.
alter table public.users drop constraint if exists users_id_fkey; alter table public.users add constraint users_id_fkey foreign key(id) references auth.users(id) on delete cascade;
alter table public.users drop constraint if exists users_referred_by_fkey; alter table public.users add constraint users_referred_by_fkey foreign key(referred_by) references public.users(id) on delete set null;
alter table public.transactions drop constraint if exists transactions_user_id_fkey; alter table public.transactions add constraint transactions_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.transactions drop constraint if exists transactions_webhook_event_id_fkey; alter table public.transactions add constraint transactions_webhook_event_id_fkey foreign key(webhook_event_id) references public.webhook_events(id);
alter table public.wallets drop constraint if exists wallets_user_id_fkey; alter table public.wallets add constraint wallets_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.wallet_ledger drop constraint if exists wallet_ledger_user_id_fkey; alter table public.wallet_ledger add constraint wallet_ledger_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.wallet_accounts drop constraint if exists wallet_accounts_user_id_fkey; alter table public.wallet_accounts add constraint wallet_accounts_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.wallet_entries drop constraint if exists wallet_entries_wallet_id_fkey; alter table public.wallet_entries add constraint wallet_entries_wallet_id_fkey foreign key(wallet_id) references public.wallet_accounts(id) on delete restrict;
alter table public.campaigns drop constraint if exists campaigns_user_id_fkey; alter table public.campaigns add constraint campaigns_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.campaigns drop constraint if exists campaigns_approved_by_fkey; alter table public.campaigns add constraint campaigns_approved_by_fkey foreign key(approved_by) references public.users(id) on delete set null;
alter table public.watch_tasks drop constraint if exists watch_tasks_campaign_id_fkey; alter table public.watch_tasks add constraint watch_tasks_campaign_id_fkey foreign key(campaign_id) references public.campaigns(id) on delete cascade;
alter table public.watch_tasks drop constraint if exists watch_tasks_worker_id_fkey; alter table public.watch_tasks add constraint watch_tasks_worker_id_fkey foreign key(worker_id) references public.users(id) on delete cascade;
alter table public.task_sessions drop constraint if exists task_sessions_task_id_fkey; alter table public.task_sessions add constraint task_sessions_task_id_fkey foreign key(task_id) references public.watch_tasks(id) on delete cascade;
alter table public.task_sessions drop constraint if exists task_sessions_worker_id_fkey; alter table public.task_sessions add constraint task_sessions_worker_id_fkey foreign key(worker_id) references public.users(id) on delete cascade;
alter table public.task_sessions drop constraint if exists task_sessions_campaign_id_fkey; alter table public.task_sessions add constraint task_sessions_campaign_id_fkey foreign key(campaign_id) references public.campaigns(id) on delete cascade;
alter table public.task_heartbeats drop constraint if exists task_heartbeats_session_id_fkey; alter table public.task_heartbeats add constraint task_heartbeats_session_id_fkey foreign key(session_id) references public.task_sessions(id) on delete cascade;
alter table public.referrals drop constraint if exists referrals_referrer_id_fkey; alter table public.referrals add constraint referrals_referrer_id_fkey foreign key(referrer_id) references public.users(id) on delete cascade;
alter table public.referrals drop constraint if exists referrals_referred_id_fkey; alter table public.referrals add constraint referrals_referred_id_fkey foreign key(referred_id) references public.users(id) on delete cascade;
alter table public.violations drop constraint if exists violations_user_id_fkey; alter table public.violations add constraint violations_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.violations drop constraint if exists violations_related_task_id_fkey; alter table public.violations add constraint violations_related_task_id_fkey foreign key(related_task_id) references public.watch_tasks(id) on delete set null;
alter table public.violation_logs drop constraint if exists violation_logs_user_id_fkey; alter table public.violation_logs add constraint violation_logs_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.violation_logs drop constraint if exists violation_logs_related_task_id_fkey; alter table public.violation_logs add constraint violation_logs_related_task_id_fkey foreign key(related_task_id) references public.watch_tasks(id) on delete set null;
alter table public.payout_methods drop constraint if exists payout_methods_user_id_fkey; alter table public.payout_methods add constraint payout_methods_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.payouts drop constraint if exists payouts_user_id_fkey; alter table public.payouts add constraint payouts_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.payouts drop constraint if exists payouts_payout_method_id_fkey; alter table public.payouts add constraint payouts_payout_method_id_fkey foreign key(payout_method_id) references public.payout_methods(id) on delete restrict;
alter table public.payouts drop constraint if exists payouts_processed_by_fkey; alter table public.payouts add constraint payouts_processed_by_fkey foreign key(processed_by) references public.users(id) on delete set null;
alter table public.audit_logs drop constraint if exists audit_logs_actor_id_fkey; alter table public.audit_logs add constraint audit_logs_actor_id_fkey foreign key(actor_id) references public.users(id) on delete set null;
alter table public.audit_events drop constraint if exists audit_events_actor_id_fkey; alter table public.audit_events add constraint audit_events_actor_id_fkey foreign key(actor_id) references public.users(id) on delete set null;
alter table public.audit_events drop constraint if exists audit_events_target_user_id_fkey; alter table public.audit_events add constraint audit_events_target_user_id_fkey foreign key(target_user_id) references public.users(id) on delete set null;
alter table public.data_rights_requests drop constraint if exists data_rights_requests_user_id_fkey; alter table public.data_rights_requests add constraint data_rights_requests_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.support_tickets drop constraint if exists support_tickets_user_id_fkey; alter table public.support_tickets add constraint support_tickets_user_id_fkey foreign key(user_id) references public.users(id) on delete set null;
alter table public.business_shops drop constraint if exists business_shops_user_id_fkey; alter table public.business_shops add constraint business_shops_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.inventory_products drop constraint if exists inventory_products_user_id_fkey; alter table public.inventory_products add constraint inventory_products_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.inventory_products drop constraint if exists inventory_products_shop_id_fkey; alter table public.inventory_products add constraint inventory_products_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_customers drop constraint if exists shop_customers_shop_id_fkey; alter table public.shop_customers add constraint shop_customers_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_orders drop constraint if exists shop_orders_shop_id_fkey; alter table public.shop_orders add constraint shop_orders_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_orders drop constraint if exists shop_orders_user_id_fkey; alter table public.shop_orders add constraint shop_orders_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.shop_order_items drop constraint if exists shop_order_items_order_id_fkey; alter table public.shop_order_items add constraint shop_order_items_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_order_items drop constraint if exists shop_order_items_product_id_fkey; alter table public.shop_order_items add constraint shop_order_items_product_id_fkey foreign key(product_id) references public.inventory_products(id) on delete restrict;
alter table public.shop_order_events drop constraint if exists shop_order_events_order_id_fkey; alter table public.shop_order_events add constraint shop_order_events_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_transactions drop constraint if exists shop_transactions_shop_id_fkey; alter table public.shop_transactions add constraint shop_transactions_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_transactions drop constraint if exists shop_transactions_order_id_fkey; alter table public.shop_transactions add constraint shop_transactions_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete set null;
alter table public.shop_transactions drop constraint if exists shop_transactions_user_id_fkey; alter table public.shop_transactions add constraint shop_transactions_user_id_fkey foreign key(user_id) references public.users(id) on delete set null;
alter table public.shop_wallet_holds drop constraint if exists shop_wallet_holds_shop_id_fkey; alter table public.shop_wallet_holds add constraint shop_wallet_holds_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_wallet_holds drop constraint if exists shop_wallet_holds_order_id_fkey; alter table public.shop_wallet_holds add constraint shop_wallet_holds_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_settlements drop constraint if exists shop_settlements_shop_id_fkey; alter table public.shop_settlements add constraint shop_settlements_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_settlements drop constraint if exists shop_settlements_order_id_fkey; alter table public.shop_settlements add constraint shop_settlements_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_subscriptions drop constraint if exists shop_subscriptions_shop_id_fkey; alter table public.shop_subscriptions add constraint shop_subscriptions_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_subscriptions drop constraint if exists shop_subscriptions_user_id_fkey; alter table public.shop_subscriptions add constraint shop_subscriptions_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.shop_subscription_usage drop constraint if exists shop_subscription_usage_shop_id_fkey; alter table public.shop_subscription_usage add constraint shop_subscription_usage_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.shop_checkout_sessions drop constraint if exists shop_checkout_sessions_shop_id_fkey; alter table public.shop_checkout_sessions add constraint shop_checkout_sessions_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.wallet_holds drop constraint if exists wallet_holds_shop_id_fkey; alter table public.wallet_holds add constraint wallet_holds_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.wallet_holds drop constraint if exists wallet_holds_order_id_fkey; alter table public.wallet_holds add constraint wallet_holds_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete set null;
alter table public.jforce_clicks drop constraint if exists jforce_clicks_shop_id_fkey; alter table public.jforce_clicks add constraint jforce_clicks_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.jforce_clicks drop constraint if exists jforce_clicks_product_id_fkey; alter table public.jforce_clicks add constraint jforce_clicks_product_id_fkey foreign key(product_id) references public.inventory_products(id) on delete set null;
alter table public.whatsapp_connections drop constraint if exists whatsapp_connections_shop_id_fkey; alter table public.whatsapp_connections add constraint whatsapp_connections_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.whatsapp_flows drop constraint if exists whatsapp_flows_shop_id_fkey; alter table public.whatsapp_flows add constraint whatsapp_flows_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.whatsapp_conversations drop constraint if exists whatsapp_conversations_shop_id_fkey; alter table public.whatsapp_conversations add constraint whatsapp_conversations_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.whatsapp_messages_shop drop constraint if exists whatsapp_messages_shop_conversation_id_fkey; alter table public.whatsapp_messages_shop add constraint whatsapp_messages_shop_conversation_id_fkey foreign key(conversation_id) references public.whatsapp_conversations(id) on delete cascade;
alter table public.whatsapp_shop_flows drop constraint if exists whatsapp_shop_flows_shop_id_fkey; alter table public.whatsapp_shop_flows add constraint whatsapp_shop_flows_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.business_subscriptions drop constraint if exists business_subscriptions_user_id_fkey; alter table public.business_subscriptions add constraint business_subscriptions_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.business_subscription_payments drop constraint if exists business_subscription_payments_user_id_fkey; alter table public.business_subscription_payments add constraint business_subscription_payments_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;

create unique index if not exists users_one_channel_idx on public.users(youtube_channel_id) where youtube_channel_id is not null;
create unique index if not exists users_one_device_idx on public.users(device_fingerprint) where device_fingerprint is not null;
create unique index if not exists users_one_momo_idx on public.users(phone_hash) where phone_hash is not null;
create unique index if not exists transactions_idempotency_idx on public.transactions(user_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists transactions_provider_reference_idx on public.transactions(paystack_ref) where paystack_ref is not null;
create unique index if not exists wallet_ledger_idempotency_idx on public.wallet_ledger(user_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists shop_orders_idempotency_idx on public.shop_orders(shop_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists watch_tasks_campaign_worker_idx on public.watch_tasks(campaign_id,worker_id);
create unique index if not exists task_sessions_active_task_idx on public.task_sessions(task_id) where status in ('active','submitted');
create index if not exists watch_tasks_campaign_status_idx on public.watch_tasks(campaign_id,status);
create index if not exists watch_tasks_worker_status_idx on public.watch_tasks(worker_id,status);
create index if not exists task_heartbeats_session_idx on public.task_heartbeats(session_id,created_at desc);

-- Minimal safe authorization helpers used by RLS policies. They live in a private schema and are not executable by clients.
create schema if not exists private;
create or replace function private.is_staff() returns boolean language sql stable security definer set search_path = public, pg_temp as $$ select exists(select 1 from public.users where id=auth.uid() and role in ('admin','superadmin') and is_banned=false) $$;
create or replace function private.is_superadmin() returns boolean language sql stable security definer set search_path = public, pg_temp as $$ select exists(select 1 from public.users where id=auth.uid() and role='superadmin' and is_banned=false) $$;
revoke all on function private.is_staff() from public, anon, authenticated;
revoke all on function private.is_superadmin() from public, anon, authenticated;

-- Seed only structural defaults; production values are completed/validated by later configuration migrations.
insert into public.platform_settings(id,entry_fee_minor,campaign_min_quantity,campaign_max_quantity,campaign_min_cost_cents,campaign_max_cost_cents,campaign_platform_fee_bps,task_session_ttl_seconds,task_heartbeat_interval_seconds,task_inactivity_timeout_seconds,config_version)
values(true,16000,1,100000,10,10000,1000,1800,5,30,1)
on conflict (id) do nothing;
insert into public.plans(code,name,monthly_price_minor,setup_fee_minor,product_limit,monthly_conversation_limit,shop_fee_bps,extra_conversation_minor,active,min_cost_cents,max_cost_cents)
values('creator','Creator',0,0,20,100,500,50,true,10,10000)
on conflict(code) do nothing;

-- RLS is enabled for every public application table. Policies are deliberately minimal here;
-- later hardening migrations add the exact owner/staff policies.
do $$ declare r record; begin for r in select tablename from pg_tables where schemaname='public' loop execute format('alter table public.%I enable row level security',r.tablename); end loop; end $$;

commit;
