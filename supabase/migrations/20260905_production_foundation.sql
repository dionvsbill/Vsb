begin;
create extension if not exists pgcrypto;

create table if not exists public.webhook_events (
  id uuid primary key default gen_random_uuid(), provider text not null, event_type text not null,
  event_id text, signature_valid boolean not null default false, payload jsonb not null default '{}',
  processing_status text not null default 'received' check (processing_status in ('received','processing','processed','failed','ignored')),
  error_message text, processed_at timestamptz, created_at timestamptz not null default now(), unique(provider,event_id)
);
create table if not exists public.idempotency_keys (
  id uuid primary key default gen_random_uuid(), scope text not null, key text not null,
  request_hash text, response_status integer, response_body jsonb, locked_at timestamptz,
  expires_at timestamptz not null default now()+interval '24 hours', created_at timestamptz not null default now(), unique(scope,key)
);
create table if not exists public.task_sessions (
  id uuid primary key default gen_random_uuid(), task_id uuid not null references public.watch_tasks(id) on delete cascade,
  worker_id uuid not null references public.users(id) on delete cascade, campaign_id uuid not null references public.campaigns(id) on delete cascade,
  nonce_hash text not null unique, started_at timestamptz not null default now(), expires_at timestamptz not null,
  last_heartbeat_at timestamptz, visibility_failures integer not null default 0 check(visibility_failures>=0),
  seek_events integer not null default 0 check(seek_events>=0), playback_seconds numeric(12,3) not null default 0 check(playback_seconds>=0),
  status text not null default 'active' check(status in ('active','expired','submitted','verified','rejected','cancelled')),
  evidence jsonb not null default '{}', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists task_sessions_active_task_idx on public.task_sessions(task_id) where status in ('active','submitted');
create table if not exists public.task_heartbeats (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references public.task_sessions(id) on delete cascade,
  client_time_seconds numeric(12,3) not null check(client_time_seconds>=0), visibility_state text not null,
  playback_rate numeric(6,3) not null default 1 check(playback_rate>0 and playback_rate<=4),
  seek_detected boolean not null default false, mouse_activity boolean not null default false, created_at timestamptz not null default now()
);
create index if not exists task_heartbeats_session_idx on public.task_heartbeats(session_id,created_at desc);

create table if not exists public.wallet_accounts (
  id uuid primary key default gen_random_uuid(), user_id uuid not null unique references public.users(id) on delete cascade,
  balance_minor bigint not null default 0 check(balance_minor>=0), pending_minor bigint not null default 0 check(pending_minor>=0),
  reserved_minor bigint not null default 0 check(reserved_minor>=0), currency text not null default 'GHS', created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.wallet_entries (
  id uuid primary key default gen_random_uuid(), wallet_id uuid not null references public.wallet_accounts(id) on delete restrict,
  amount_minor bigint not null check(amount_minor<>0), balance_after_minor bigint not null check(balance_after_minor>=0),
  entry_type text not null, reference_type text, reference_id uuid, idempotency_key text, metadata jsonb not null default '{}', created_at timestamptz not null default now(), unique(wallet_id,idempotency_key)
);

alter table public.transactions add column if not exists amount_minor bigint;
alter table public.transactions add column if not exists idempotency_key text;
alter table public.transactions add column if not exists webhook_event_id uuid references public.webhook_events(id);
create unique index if not exists transactions_idempotency_idx on public.transactions(user_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists transactions_provider_reference_idx on public.transactions(paystack_ref) where paystack_ref is not null;
alter table public.wallet_ledger add column if not exists amount_minor bigint;
alter table public.wallet_ledger add column if not exists balance_after_minor bigint;
alter table public.wallet_ledger add column if not exists idempotency_key text;
create unique index if not exists wallet_ledger_idempotency_idx on public.wallet_ledger(user_id,idempotency_key) where idempotency_key is not null;
alter table public.shop_orders add column if not exists idempotency_key text;
alter table public.shop_orders add column if not exists total_minor bigint;
create unique index if not exists shop_orders_idempotency_idx on public.shop_orders(shop_id,idempotency_key) where idempotency_key is not null;
alter table public.campaigns add column if not exists cost_per_task_minor bigint;
alter table public.campaigns add column if not exists total_budget_minor bigint;
alter table public.campaigns add column if not exists platform_fee_minor bigint;
alter table public.campaigns add column if not exists total_charge_minor bigint;
alter table public.campaigns add column if not exists promotion_mode text not null default 'google_ads';
alter table public.campaigns add column if not exists policy_review_status text not null default 'pending';

create index if not exists watch_tasks_campaign_status_idx on public.watch_tasks(campaign_id,status);
create index if not exists watch_tasks_worker_status_idx on public.watch_tasks(worker_id,status);

alter table public.webhook_events enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.task_sessions enable row level security;
alter table public.task_heartbeats enable row level security;
alter table public.wallet_accounts enable row level security;
alter table public.wallet_entries enable row level security;
create policy wallet_accounts_owner_select on public.wallet_accounts for select using(user_id=auth.uid());
create policy wallet_entries_owner_select on public.wallet_entries for select using(exists(select 1 from public.wallet_accounts w where w.id=wallet_id and w.user_id=auth.uid()));
create policy task_sessions_owner_select on public.task_sessions for select using(worker_id=auth.uid());
create policy task_heartbeats_owner_select on public.task_heartbeats for select using(exists(select 1 from public.task_sessions s where s.id=session_id and s.worker_id=auth.uid()));
commit;
