begin;
create table if not exists public.jforce_imports(
 id uuid primary key default gen_random_uuid(),shop_id uuid not null,user_id uuid not null,source_product_id text,source_url text not null,status text not null default 'queued' check(status in ('queued','running','succeeded','failed','cancelled')),
 request_payload jsonb not null default '{}',response_payload jsonb not null default '{}',error_message text,created_at timestamptz not null default now(),started_at timestamptz,completed_at timestamptz
);
create table if not exists public.stock_adjustments(
 id uuid primary key default gen_random_uuid(),product_id uuid not null,user_id uuid not null,delta_quantity integer not null,reason text not null,reference_type text,reference_id uuid,created_at timestamptz not null default now()
);
create table if not exists public.seller_balances(
 id uuid primary key default gen_random_uuid(),shop_id uuid not null unique,currency text not null default 'GHS',pending_minor bigint not null default 0 check(pending_minor>=0),available_minor bigint not null default 0 check(available_minor>=0),reserved_minor bigint not null default 0 check(reserved_minor>=0),updated_at timestamptz not null default now()
);
create table if not exists public.seller_ledger_entries(
 id uuid primary key default gen_random_uuid(),seller_balance_id uuid not null,direction text not null check(direction in ('credit','debit')),amount_minor bigint not null check(amount_minor>0),entry_type text not null,reference_type text,reference_id uuid,idempotency_key text unique,metadata jsonb not null default '{}',created_at timestamptz not null default now()
);
create table if not exists public.delivery_events(
 id uuid primary key default gen_random_uuid(),order_id uuid not null,status text not null,tracking_code text,provider text,metadata jsonb not null default '{}',created_at timestamptz not null default now()
);
create table if not exists public.shop_disputes(
 id uuid primary key default gen_random_uuid(),order_id uuid not null,user_id uuid not null,reason text not null,status text not null default 'open' check(status in ('open','investigating','resolved_buyer','resolved_seller','rejected')),resolution_note text,created_at timestamptz not null default now(),resolved_at timestamptz
);
create table if not exists public.settlement_jobs(
 id uuid primary key default gen_random_uuid(),shop_id uuid,order_id uuid,kind text not null,status text not null default 'queued' check(status in ('queued','running','succeeded','failed','retrying')),attempts integer not null default 0,next_run_at timestamptz not null default now(),last_error text,created_at timestamptz not null default now(),completed_at timestamptz
);
alter table public.jforce_imports add constraint jforce_imports_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.jforce_imports add constraint jforce_imports_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.stock_adjustments add constraint stock_adjustments_product_id_fkey foreign key(product_id) references public.inventory_products(id) on delete restrict;
alter table public.stock_adjustments add constraint stock_adjustments_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.seller_balances add constraint seller_balances_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.seller_ledger_entries add constraint seller_ledger_entries_balance_id_fkey foreign key(seller_balance_id) references public.seller_balances(id) on delete restrict;
alter table public.delivery_events add constraint delivery_events_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_disputes add constraint shop_disputes_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete cascade;
alter table public.shop_disputes add constraint shop_disputes_user_id_fkey foreign key(user_id) references public.users(id) on delete cascade;
alter table public.settlement_jobs add constraint settlement_jobs_shop_id_fkey foreign key(shop_id) references public.business_shops(id) on delete cascade;
alter table public.settlement_jobs add constraint settlement_jobs_order_id_fkey foreign key(order_id) references public.shop_orders(id) on delete set null;
create index if not exists stock_adjustments_product_created_idx on public.stock_adjustments(product_id,created_at desc);
create index if not exists delivery_events_order_created_idx on public.delivery_events(order_id,created_at desc);
create index if not exists settlement_jobs_due_idx on public.settlement_jobs(status,next_run_at);
commit;
