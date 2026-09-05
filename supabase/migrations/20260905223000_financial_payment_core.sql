begin;

create table if not exists public.campaign_funds (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null unique,
  currency text not null default 'USD',
  funded_minor bigint not null default 0 check(funded_minor>=0),
  available_minor bigint not null default 0 check(available_minor>=0),
  reserved_minor bigint not null default 0 check(reserved_minor>=0),
  settled_minor bigint not null default 0 check(settled_minor>=0),
  refunded_minor bigint not null default 0 check(refunded_minor>=0),
  charged_back_minor bigint not null default 0 check(charged_back_minor>=0),
  status text not null default 'pending' check(status in ('pending','paid','escrowed','partially_settled','settled','refunded','charged_back')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.campaign_ledger_entries (
  id uuid primary key default gen_random_uuid(), campaign_fund_id uuid not null,
  direction text not null check(direction in ('credit','debit')), amount_minor bigint not null check(amount_minor>0),
  entry_type text not null, reference_type text, reference_id uuid, idempotency_key text unique, metadata jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(), transaction_id uuid, campaign_id uuid, amount_minor bigint not null check(amount_minor>0), currency text not null default 'GHS',
  provider text not null default 'paystack', provider_reference text, status text not null default 'pending' check(status in ('pending','processing','succeeded','failed','cancelled')), reason text,
  created_at timestamptz not null default now(), processed_at timestamptz
);
create table if not exists public.chargebacks (
  id uuid primary key default gen_random_uuid(), transaction_id uuid, campaign_id uuid, amount_minor bigint not null check(amount_minor>0), currency text not null default 'GHS',
  provider text not null default 'paystack', provider_reference text, status text not null default 'open' check(status in ('open','reviewing','resolved','reversed')), reason text,
  created_at timestamptz not null default now(), resolved_at timestamptz
);
create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(), campaign_id uuid, shop_id uuid, amount_minor bigint not null check(amount_minor>0), currency text not null default 'GHS',
  status text not null default 'pending' check(status in ('pending','processing','settled','failed','reversed')), reference text unique, created_at timestamptz not null default now(), settled_at timestamptz
);

alter table public.transactions add column if not exists amount_minor bigint;
alter table public.transactions add column if not exists provider text default 'paystack';
update public.transactions set amount_minor=round(amount*100)::bigint where amount_minor is null;
alter table public.wallet_accounts add column if not exists balance_minor bigint not null default 0;

-- Backfill the canonical wallet account from the legacy balance exactly once.
insert into public.wallet_accounts(user_id,balance_minor,currency)
select id,round(balance*100)::bigint,'GHS' from public.users
on conflict(user_id) do update set balance_minor=greatest(public.wallet_accounts.balance_minor,excluded.balance_minor),updated_at=now();

create or replace function private.credit_wallet_minor(p_user uuid,p_amount_minor bigint,p_type public.transaction_type,p_metadata jsonb default '{}') returns uuid
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare wid uuid; new_balance bigint; entry uuid;
begin
 if p_amount_minor<=0 then raise exception 'Amount must be positive'; end if;
 select id into wid from public.wallet_accounts where user_id=p_user and currency='GHS' for update;
 if wid is null then insert into public.wallet_accounts(user_id,currency,balance_minor) values(p_user,'GHS',0) returning id into wid; end if;
 select balance_minor into new_balance from public.wallet_accounts where id=wid for update; new_balance:=new_balance+p_amount_minor;
 update public.wallet_accounts set balance_minor=new_balance,updated_at=now() where id=wid;
 insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,metadata) values(wid,p_amount_minor,new_balance,p_type::text,'payment',coalesce(p_metadata,'{}')) returning id into entry;
 return entry;
end; $$;
revoke all on function private.credit_wallet_minor(uuid,bigint,public.transaction_type,jsonb) from public,anon,authenticated;

drop function if exists public.fulfill_entry_payment(uuid,text,numeric,jsonb);
create function public.fulfill_entry_payment(p_user uuid,p_ref text,p_amount_minor bigint,p_metadata jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare tx public.transactions%rowtype; referrer uuid; ref_minor bigint; cashback_minor bigint; setting_ref numeric; setting_cash numeric; result jsonb;
begin
 select * into tx from public.transactions where paystack_ref=p_ref for update;
 if not found or tx.user_id<>p_user or tx.type<>'entry_fee' then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if tx.amount_minor is null or tx.amount_minor<>p_amount_minor then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
 if tx.status='success' then return jsonb_build_object('success',true,'already_processed',true,'transaction_id',tx.id); end if;
 if tx.status<>'pending' then raise exception 'PAYMENT_NOT_PENDING'; end if;
 update public.transactions set status='success',metadata=coalesce(tx.metadata,'{}')||coalesce(p_metadata,'{}'),updated_at=now() where id=tx.id;
 update public.users set is_paid=true,entry_fee_paid_at=now(),entry_fee_expires_at=null,deactivated_at=null where id=p_user;
 select referred_by into referrer from public.users where id=p_user;
 if referrer is not null then
   select referral_percent,cashback_percent into setting_ref,setting_cash from public.platform_settings where id=true;
   ref_minor:=round(p_amount_minor*coalesce(setting_ref,0)/100)::bigint; cashback_minor:=round(p_amount_minor*coalesce(setting_cash,0)/100)::bigint;
   insert into public.referrals(referrer_id,referred_id,entry_fee_amount,commission_earned,cashback_amount) values(referrer,p_user,p_amount_minor/100.0,ref_minor/100.0,cashback_minor/100.0) on conflict(referred_id) do nothing;
   if ref_minor>0 then perform private.credit_wallet_minor(referrer,ref_minor,'referral_earning',jsonb_build_object('referred_user',p_user,'paystack_ref',p_ref)); end if;
   if cashback_minor>0 then perform private.credit_wallet_minor(p_user,cashback_minor,'referral_earning',jsonb_build_object('type','entry_cashback','paystack_ref',p_ref)); end if;
 end if;
 result:=jsonb_build_object('success',true,'transaction_id',tx.id,'amount_minor',p_amount_minor,'currency',tx.currency);
 return result;
end; $$;
revoke all on function public.fulfill_entry_payment(uuid,text,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.fulfill_entry_payment(uuid,text,bigint,jsonb) to service_role;

drop function if exists public.fulfill_campaign_payment(uuid,text,bigint,text,uuid,jsonb);
create function public.fulfill_campaign_payment(p_user uuid,p_ref text,p_amount_minor bigint,p_currency text,p_campaign_id uuid,p_metadata jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare tx public.transactions%rowtype; c public.campaigns%rowtype; fund public.campaign_funds%rowtype; existing jsonb;
begin
 select * into tx from public.transactions where paystack_ref=p_ref for update; if not found or tx.user_id<>p_user or tx.type<>'campaign_payment' then raise exception 'PAYMENT_NOT_FOUND'; end if;
 if tx.amount_minor is null or tx.amount_minor<>p_amount_minor or tx.currency<>p_currency then raise exception 'PAYMENT_AMOUNT_MISMATCH'; end if;
 select * into c from public.campaigns where id=p_campaign_id and user_id=p_user for update; if not found then raise exception 'CAMPAIGN_NOT_FOUND'; end if;
 if tx.status='success' then return jsonb_build_object('success',true,'already_processed',true,'transaction_id',tx.id); end if;
 if tx.status<>'pending' then raise exception 'PAYMENT_NOT_PENDING'; end if;
 update public.transactions set status='success',metadata=coalesce(tx.metadata,'{}')||coalesce(p_metadata,'{}'),updated_at=now() where id=tx.id;
 insert into public.campaign_funds(campaign_id,currency,funded_minor,available_minor,status) values(c.id,p_currency,p_amount_minor,p_amount_minor,'escrowed') on conflict(campaign_id) do update set funded_minor=campaign_funds.funded_minor+excluded.funded_minor,available_minor=campaign_funds.available_minor+excluded.available_minor,status='escrowed',updated_at=now() returning * into fund;
 insert into public.campaign_ledger_entries(campaign_fund_id,direction,amount_minor,entry_type,reference_type,reference_id,idempotency_key,metadata) values(fund.id,'credit',p_amount_minor,'campaign_payment','transaction',tx.id,'campaign_payment:'||p_ref,coalesce(p_metadata,'{}')) on conflict(idempotency_key) do nothing;
 update public.campaigns set status='pending_approval',updated_at=now() where id=c.id;
 return jsonb_build_object('success',true,'transaction_id',tx.id,'campaign_id',c.id,'escrowed_minor',p_amount_minor,'currency',p_currency);
end; $$;
revoke all on function public.fulfill_campaign_payment(uuid,text,bigint,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.fulfill_campaign_payment(uuid,text,bigint,text,uuid,jsonb) to service_role;

drop function if exists public.process_paystack_charge_success(text,text,uuid,text,text,bigint,text,text,uuid,jsonb);
create function public.process_paystack_charge_success(p_event_id text,p_event_type text,p_user_id uuid,p_reference text,p_payment_type text,p_amount_minor bigint,p_currency text,p_provider_transaction_id text,p_campaign_id uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp as $$
declare ev public.webhook_events%rowtype; result jsonb;
begin
 if nullif(trim(p_event_id),'') is null then raise exception 'PAYSTACK_EVENT_ID_REQUIRED'; end if;
 insert into public.webhook_events(provider,event_type,event_id,signature_valid,payload,processing_status) values('paystack',p_event_type,p_event_id,true,coalesce(p_payload,'{}'),'processing') on conflict(provider,event_id) do nothing;
 select * into ev from public.webhook_events where provider='paystack' and event_id=p_event_id for update;
 if ev.processing_status='processed' then return jsonb_build_object('success',true,'duplicate',true); end if;
 if ev.processing_status='failed' and ev.error_message is not null then update public.webhook_events set processing_status='processing',error_message=null where id=ev.id; end if;
 begin
   if p_payment_type='entry_fee' then result:=public.fulfill_entry_payment(p_user_id,p_reference,p_amount_minor,jsonb_build_object('provider_transaction_id',p_provider_transaction_id,'webhook_event_id',ev.id,'channel','paystack'));
   elsif p_payment_type='campaign_payment' then if p_campaign_id is null then raise exception 'CAMPAIGN_REFERENCE_REQUIRED'; end if; result:=public.fulfill_campaign_payment(p_user_id,p_reference,p_amount_minor,p_currency,p_campaign_id,jsonb_build_object('provider_transaction_id',p_provider_transaction_id,'webhook_event_id',ev.id,'channel','paystack'));
   else raise exception 'UNSUPPORTED_PAYMENT_TYPE'; end if;
   update public.webhook_events set processing_status='processed',processed_at=now(),error_message=null where id=ev.id;
   return result||jsonb_build_object('webhook_event_id',ev.id);
 exception when others then
   update public.webhook_events set processing_status='failed',error_message=sqlerrm where id=ev.id;
   raise;
 end;
end; $$;
revoke all on function public.process_paystack_charge_success(text,text,uuid,text,text,bigint,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.process_paystack_charge_success(text,text,uuid,text,text,bigint,text,text,uuid,jsonb) to service_role;

commit;
