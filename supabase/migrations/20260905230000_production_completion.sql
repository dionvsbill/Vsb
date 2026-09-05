begin;

-- Production completion contract. The existing users/wallet_accounts/transactions/shop tables remain
-- canonical; these additions close provider, fraud, checkout and secret-storage gaps without creating a
-- second balance source.
create table if not exists public.provider_secrets (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.users(id) on delete cascade,
  provider text not null, secret_name text not null, ciphertext text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(owner_id,provider,secret_name)
);
create table if not exists public.fraud_strikes (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.users(id) on delete cascade,
  reason text not null, evidence jsonb not null default '{}', related_task_id uuid references public.watch_tasks(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.device_registrations (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.users(id) on delete cascade,
  visitor_id_hash text not null, first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
  last_ip inet, user_agent_hash text, unique(user_id,visitor_id_hash)
);
create table if not exists public.shop_quotes (
  id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.business_shops(id) on delete cascade,
  items jsonb not null, subtotal_minor bigint not null check(subtotal_minor>=0), delivery_fee_minor bigint not null check(delivery_fee_minor>=0),
  total_minor bigint not null check(total_minor>=0), currency text not null default 'GHS', expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create table if not exists public.whatsapp_usage (
  shop_id uuid primary key references public.business_shops(id) on delete cascade, period_start timestamptz not null default date_trunc('month',now()),
  conversations_used integer not null default 0 check(conversations_used>=0), updated_at timestamptz not null default now()
);

alter table public.shop_orders alter column user_id drop not null;
alter table public.shop_order_items add column if not exists unit_price_minor bigint;

-- Keep a single authoritative GHS wallet. Legacy decimal wallets are no longer mutated by new code.
insert into public.wallet_accounts(user_id,balance_minor,currency)
select id,round(greatest(balance,0)*100)::bigint,'GHS' from public.users
on conflict(user_id) do nothing;

-- Configuration must be present and valid; no runtime hardcoded fallbacks are permitted.
update public.platform_settings set entry_fee_minor=coalesce(entry_fee_minor,round(entry_fee_ghs*100)::bigint),
  campaign_min_quantity=coalesce(campaign_min_quantity,1), campaign_max_quantity=coalesce(campaign_max_quantity,100000),
  campaign_min_cost_cents=coalesce(campaign_min_cost_cents,10), campaign_max_cost_cents=coalesce(campaign_max_cost_cents,10000),
  campaign_platform_fee_bps=coalesce(campaign_platform_fee_bps,1000), task_session_ttl_seconds=coalesce(task_session_ttl_seconds,1800),
  task_heartbeat_interval_seconds=coalesce(task_heartbeat_interval_seconds,5), task_inactivity_timeout_seconds=coalesce(task_inactivity_timeout_seconds,30),
  config_version=coalesce(config_version,1) where id=true;
insert into public.fx_rates(base_currency,quote_currency,rate_numeric,effective_from,source)
select 'USD','GHS',160,now(),'initial-admin-seed'
where not exists(select 1 from public.fx_rates where base_currency='USD' and quote_currency='GHS');

create or replace function public.store_youtube_secret(p_user_id uuid,p_name text,p_ciphertext text) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare sid uuid;
begin
 if auth.uid() is not null and auth.uid()<>p_user_id then raise exception 'FORBIDDEN'; end if;
 insert into public.provider_secrets(owner_id,provider,secret_name,ciphertext) values(p_user_id,'youtube',p_name,p_ciphertext)
 on conflict(owner_id,provider,secret_name) do update set ciphertext=excluded.ciphertext,updated_at=now() returning id into sid;
 return sid;
end; $$;
create or replace function public.read_youtube_secret(p_secret_id uuid,p_user_id uuid) returns text
language plpgsql security definer set search_path=public,pg_temp as $$
declare value text;
begin
 if auth.uid() is not null and auth.uid()<>p_user_id then raise exception 'FORBIDDEN'; end if;
 select ciphertext into value from public.provider_secrets where id=p_secret_id and owner_id=p_user_id and provider='youtube';
 return value;
end; $$;
revoke all on function public.store_youtube_secret(uuid,text,text) from public,anon,authenticated;
revoke all on function public.read_youtube_secret(uuid,uuid) from public,anon,authenticated;
grant execute on function public.store_youtube_secret(uuid,text,text) to service_role;
grant execute on function public.read_youtube_secret(uuid,uuid) to service_role;

create or replace function public.check_shop_limits(p_shop_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.business_shops%rowtype; p public.plans%rowtype; count_products integer; limit_products integer;
begin
 select * into s from public.business_shops where id=p_shop_id for update; if not found then raise exception 'SHOP_NOT_FOUND'; end if;
 select * into p from public.plans where code=case when s.is_pro then 'pro' else 'creator' end and active=true limit 1;
 limit_products:=coalesce(p.product_limit,20); select count(*) into count_products from public.inventory_products where shop_id=p_shop_id;
 return jsonb_build_object('allowed',count_products<limit_products,'product_count',count_products,'product_limit',limit_products,'is_pro',s.is_pro);
end; $$;
revoke all on function public.check_shop_limits(uuid) from public,anon,authenticated;
grant execute on function public.check_shop_limits(uuid) to service_role,authenticated;

create or replace function public.record_fraud_strike(p_user_id uuid,p_reason text,p_evidence jsonb default '{}',p_task_id uuid default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare next_strikes integer;
begin
 insert into public.fraud_strikes(user_id,reason,evidence,related_task_id) values(p_user_id,p_reason,coalesce(p_evidence,'{}'),p_task_id);
 update public.users set strikes=least(3,strikes+1),is_banned=(strikes+1)>=3,blacklist_reason=case when (strikes+1)>=3 then p_reason else blacklist_reason end,updated_at=now() where id=p_user_id returning strikes into next_strikes;
 return jsonb_build_object('strikes',next_strikes,'banned',next_strikes>=3);
end; $$;
revoke all on function public.record_fraud_strike(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.record_fraud_strike(uuid,text,jsonb,uuid) to service_role;

create or replace function public.allocate_payment(p_payment_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare tx public.transactions%rowtype; result jsonb;
begin
 select * into tx from public.transactions where id=p_payment_id for update; if not found then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if tx.type='entry_fee' then result:=public.fulfill_entry_payment(tx.user_id,tx.paystack_ref,tx.amount_minor,jsonb_build_object('allocated_by','allocate_payment'));
 elsif tx.type='campaign_payment' then result:=public.fulfill_campaign_payment(tx.user_id,tx.paystack_ref,tx.amount_minor,tx.currency,(tx.metadata->>'campaign_id')::uuid,jsonb_build_object('allocated_by','allocate_payment'));
 else raise exception 'UNSUPPORTED_PAYMENT_TYPE'; end if;
 return result;
end; $$;
revoke all on function public.allocate_payment(uuid) from public,anon,authenticated;
grant execute on function public.allocate_payment(uuid) to service_role;

create or replace function public.debit_wallet_service(p_user_id uuid,p_amount_minor bigint,p_reason text,p_reference_id uuid default null,p_idempotency_key text default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare w public.wallet_accounts%rowtype; new_balance bigint; entry_id uuid;
begin
 if p_amount_minor<=0 then raise exception 'INVALID_AMOUNT'; end if;
 select * into w from public.wallet_accounts where user_id=p_user_id and currency='GHS' for update; if not found then raise exception 'WALLET_NOT_FOUND'; end if;
 if w.balance_minor<p_amount_minor then raise exception 'INSUFFICIENT_FUNDS'; end if;
 if p_idempotency_key is not null and exists(select 1 from public.wallet_entries where wallet_id=w.id and idempotency_key=p_idempotency_key) then return jsonb_build_object('success',true,'duplicate',true); end if;
 new_balance:=w.balance_minor-p_amount_minor;
 update public.wallet_accounts set balance_minor=new_balance,updated_at=now() where id=w.id;
 insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,reference_id,idempotency_key,metadata) values(w.id,-p_amount_minor,'0','service_debit','service',p_reference_id,p_idempotency_key,jsonb_build_object('reason',p_reason)) returning id into entry_id;
 update public.wallet_entries set balance_after_minor=new_balance where id=entry_id;
 return jsonb_build_object('success',true,'entry_id',entry_id,'balance_minor',new_balance);
end; $$;
revoke all on function public.debit_wallet_service(uuid,bigint,text,uuid,text) from public,anon,authenticated;
grant execute on function public.debit_wallet_service(uuid,bigint,text,uuid,text) to service_role;

-- Atomic server-side shop order creation. Browser totals and delivery fees are ignored.
create or replace function public.create_shop_order(p_shop_id uuid,p_buyer_name text,p_buyer_phone text,p_buyer_email text,p_delivery_address text,p_delivery_note text,p_payment_method text,p_delivery_fee numeric,p_items jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare item jsonb; product public.inventory_products%rowtype; shop public.business_shops%rowtype; order_id uuid; order_no text; subtotal_minor bigint:=0; delivery_minor bigint; total_minor bigint; qty integer; line_minor bigint; quote_id uuid; owner uuid;
begin
 if length(trim(coalesce(p_buyer_name,'')))<2 or length(regexp_replace(coalesce(p_buyer_phone,''),'[^0-9+]','','g'))<7 then raise exception 'CUSTOMER_DETAILS_REQUIRED'; end if;
 select * into shop from public.business_shops where id=p_shop_id and shop_status='approved' and is_published=true for update; if not found then raise exception 'SHOP_UNAVAILABLE'; end if;
 owner:=shop.user_id;
 if jsonb_typeof(coalesce(p_items,'[]'::jsonb))<>'array' or jsonb_array_length(p_items)=0 then raise exception 'CART_EMPTY'; end if;
 for item in select * from jsonb_array_elements(p_items) loop
   qty:=greatest(1,least(1000,floor((item->>'quantity')::numeric)::integer));
   select * into product from public.inventory_products where id=(item->>'product_id')::uuid and shop_id=p_shop_id and is_published=true for update;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   if product.quantity<qty then raise exception 'INSUFFICIENT_STOCK'; end if;
   line_minor:=round(coalesce(product.selling_price_minor,product.selling_price*100)::numeric)*qty; subtotal_minor:=subtotal_minor+line_minor;
 end loop;
 delivery_minor:=greatest(0,round(coalesce(shop.delivery_fee,0)*100)::bigint); total_minor:=subtotal_minor+delivery_minor;
 order_no:='VSB-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.shop_orders(shop_id,user_id,order_number,buyer_name,buyer_phone,buyer_email,delivery_address,delivery_note,subtotal,delivery_fee,total,currency,payment_method,payment_status,status,subtotal_minor,delivery_fee_minor,total_minor,idempotency_key)
 values(p_shop_id,auth.uid(),order_no,trim(p_buyer_name),trim(p_buyer_phone),nullif(trim(coalesce(p_buyer_email,'')),''),nullif(trim(coalesce(p_delivery_address,'')),''),nullif(trim(coalesce(p_delivery_note,'')),''),subtotal_minor/100.0,delivery_minor/100.0,total_minor/100.0,'GHS',coalesce(nullif(p_payment_method,''),'paystack'),'unpaid','pending',subtotal_minor,delivery_minor,total_minor,null)
 returning id into order_id;
 for item in select * from jsonb_array_elements(p_items) loop
   qty:=greatest(1,least(1000,floor((item->>'quantity')::numeric)::integer)); select * into product from public.inventory_products where id=(item->>'product_id')::uuid for update;
   line_minor:=round(coalesce(product.selling_price_minor,product.selling_price*100)::numeric);
   insert into public.shop_order_items(order_id,product_id,product_name,sku,quantity,unit_price,unit_price_minor,line_total) values(order_id,product.id,product.name,product.sku,qty,line_minor/100.0,line_minor,line_minor*qty/100.0);
   update public.inventory_products set quantity=quantity-qty,updated_at=now() where id=product.id;
   insert into public.stock_adjustments(product_id,user_id,delta_quantity,reason,reference_type,reference_id) values(product.id,coalesce(auth.uid(),owner),-qty,'order reservation','shop_order',order_id);
 end loop;
 insert into public.shop_order_events(order_id,status,note) values(order_id,'pending','Order created with server-calculated totals');
 if lower(coalesce(p_payment_method,''))='cod' then update public.shop_orders set payment_status='pending',status='processing',updated_at=now() where id=order_id; end if;
 return jsonb_build_object('id',order_id,'order_number',order_no,'subtotal_minor',subtotal_minor,'delivery_fee_minor',delivery_minor,'total_minor',total_minor,'currency','GHS','payment_status',case when lower(coalesce(p_payment_method,''))='cod' then 'pending' else 'unpaid' end);
end; $$;
revoke all on function public.create_shop_order(uuid,text,text,text,text,text,text,numeric,jsonb) from public,anon;
grant execute on function public.create_shop_order(uuid,text,text,text,text,text,text,numeric,jsonb) to authenticated,service_role;

create or replace function public.settle_escrow(p_order_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.shop_orders%rowtype; h public.shop_wallet_holds%rowtype; s public.seller_balances%rowtype; entry uuid; net_minor bigint; fee_minor bigint;
begin
 select * into o from public.shop_orders where id=p_order_id for update; if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if o.status not in ('delivered','processing','shipped') or o.payment_status not in ('paid','pending') then raise exception 'ORDER_NOT_SETTLEABLE'; end if;
 select * into h from public.shop_wallet_holds where order_id=o.id for update; if not found then raise exception 'ESCROW_NOT_FOUND'; end if;
 if h.status='released' then return jsonb_build_object('success',true,'already_settled',true); end if;
 fee_minor:=round(h.fee_amount*100); net_minor:=round(h.net_amount*100);
 select * into s from public.seller_balances where shop_id=o.shop_id for update; if not found then insert into public.seller_balances(shop_id) values(o.shop_id) returning * into s; end if;
 update public.seller_balances set pending_minor=greatest(0,pending_minor-fee_minor-net_minor),available_minor=available_minor+net_minor,updated_at=now() where id=s.id;
 insert into public.seller_ledger_entries(seller_balance_id,direction,amount_minor,entry_type,reference_type,reference_id,idempotency_key) values(s.id,'credit',net_minor,'order_settlement','shop_order',o.id,'settle:'||o.id);
 update public.shop_wallet_holds set status='released',released_at=now() where id=h.id;
 insert into public.shop_settlements(shop_id,order_id,gross_amount,platform_fee,net_amount,status,released_at) values(o.shop_id,o.id,h.gross_amount,h.fee_amount,h.net_amount,'released',now()) on conflict(order_id) do update set status='released',released_at=now();
 return jsonb_build_object('success',true,'order_id',o.id,'net_minor',net_minor);
end; $$;
revoke all on function public.settle_escrow(uuid) from public,anon,authenticated;
grant execute on function public.settle_escrow(uuid) to service_role;

-- RLS for new tables. Clients may only read their own records; mutations remain server-only.
alter table public.provider_secrets enable row level security;
alter table public.fraud_strikes enable row level security;
alter table public.device_registrations enable row level security;
alter table public.shop_quotes enable row level security;
alter table public.whatsapp_usage enable row level security;
create policy provider_secrets_owner_read on public.provider_secrets for select using(owner_id=auth.uid());
create policy fraud_strikes_owner_read on public.fraud_strikes for select using(user_id=auth.uid() or private.is_staff());
create policy device_registrations_owner_read on public.device_registrations for select using(user_id=auth.uid());
create policy shop_quotes_owner_read on public.shop_quotes for select using(exists(select 1 from public.business_shops s where s.id=shop_id and s.user_id=auth.uid()));
create policy whatsapp_usage_owner_read on public.whatsapp_usage for select using(exists(select 1 from public.business_shops s where s.id=shop_id and s.user_id=auth.uid()));

commit;
