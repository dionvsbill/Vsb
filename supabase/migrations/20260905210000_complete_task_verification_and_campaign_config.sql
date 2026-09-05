-- VSBILL production task verification and campaign configuration foundation.
-- Applied to the connected Supabase project before committing this migration.

create table if not exists public.fx_rates (
  id uuid primary key default gen_random_uuid(),
  base_currency text not null,
  quote_currency text not null,
  rate_numeric numeric(20,8) not null check (rate_numeric > 0),
  effective_from timestamptz not null default now(),
  effective_to timestamptz,
  source text not null default 'admin',
  created_at timestamptz not null default now()
);
create index if not exists fx_rates_pair_effective_idx on public.fx_rates(base_currency, quote_currency, effective_from desc);
insert into public.fx_rates(base_currency,quote_currency,rate_numeric,effective_from,source)
select 'USD','GHS',160,now(),'initial'
where not exists(select 1 from public.fx_rates where base_currency='USD' and quote_currency='GHS' and effective_to is null);

alter table public.idempotency_keys enable row level security;

create or replace function public.verify_discovery_task(
  p_task_id uuid,
  p_session_id uuid,
  p_worker_id uuid,
  p_nonce_hash text,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  t public.watch_tasks%rowtype;
  s public.task_sessions%rowtype;
  w public.wallet_accounts%rowtype;
  existing jsonb;
  reward_minor bigint;
  fx numeric;
  ghs_minor bigint;
  new_balance bigint;
  completion_count integer;
begin
  if p_idempotency_key is null or length(p_idempotency_key) < 16 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
  select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update;
  if existing is not null then return existing; end if;
  insert into public.idempotency_keys(scope,key,locked_at) values('task_verify',p_idempotency_key,now()) on conflict(scope,key) do nothing;
  select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update;
  if existing is not null then return existing; end if;

  select * into s from public.task_sessions where id=p_session_id for update;
  if not found or s.worker_id<>p_worker_id or s.task_id<>p_task_id then raise exception 'SESSION_NOT_FOUND'; end if;
  if s.nonce_hash<>p_nonce_hash then raise exception 'INVALID_SESSION_NONCE'; end if;
  if s.expires_at<now() then raise exception 'SESSION_EXPIRED'; end if;
  select * into t from public.watch_tasks where id=p_task_id for update;
  if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
  if t.status='completed' then raise exception 'TASK_ALREADY_COMPLETED'; end if;
  if t.status not in ('watching','verifying','assigned') then raise exception 'TASK_NOT_VERIFIABLE'; end if;
  if s.playback_seconds < greatest(1,coalesce((select duration_seconds from public.campaigns where id=t.campaign_id),0)) then raise exception 'INSUFFICIENT_PLAYBACK'; end if;
  if s.visibility_failures>0 or s.seek_events>0 then raise exception 'ABNORMAL_PLAYBACK'; end if;
  if not exists(select 1 from public.campaigns c where c.id=t.campaign_id and c.status in ('approved','active') and c.policy_review_status='approved') then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;

  reward_minor:=greatest(0,round(coalesce(t.earning_amount,0)*100)::bigint);
  select rate_numeric into fx from public.fx_rates where base_currency='USD' and quote_currency='GHS' and effective_from<=now() and (effective_to is null or effective_to>now()) order by effective_from desc limit 1;
  if fx is null then raise exception 'FX_RATE_UNAVAILABLE'; end if;
  ghs_minor:=round(reward_minor*fx)::bigint;

  select * into w from public.wallet_accounts where user_id=p_worker_id and currency='GHS' for update;
  if not found then insert into public.wallet_accounts(user_id,currency,balance_minor) values(p_worker_id,'GHS',0) returning * into w; end if;
  new_balance:=w.balance_minor+ghs_minor;
  update public.wallet_accounts set balance_minor=new_balance,updated_at=now() where id=w.id;
  insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,reference_id,idempotency_key,metadata)
  values(w.id,ghs_minor,new_balance,'task_earning','watch_task',t.id,'task_verify:'||p_idempotency_key,jsonb_build_object('source_currency','USD','source_amount_minor',reward_minor,'fx_rate',fx));

  update public.watch_tasks set status='completed',watch_end=now(),watch_duration_verified=s.playback_seconds,watch_percent_verified=100,completed_at=now(),evidence=jsonb_build_object('session_id',s.id,'playback_seconds',s.playback_seconds,'visibility_failures',s.visibility_failures,'seek_events',s.seek_events,'fx_rate',fx) where id=t.id;
  update public.task_sessions set status='completed',updated_at=now() where id=s.id;
  update public.campaigns set completed_count=completed_count+1,status=case when completed_count+1>=quantity then 'completed'::campaign_status else status end,updated_at=now() where id=t.campaign_id returning completed_count into completion_count;

  update public.idempotency_keys set response_status=200,response_body=jsonb_build_object('success',true,'task_id',t.id,'reward_minor',ghs_minor,'currency','GHS','balance_minor',new_balance,'campaign_completed_count',completion_count) where scope='task_verify' and key=p_idempotency_key;
  return (select response_body from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key);
end;
$$;
revoke all on function public.verify_discovery_task(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.verify_discovery_task(uuid,uuid,uuid,text,text) to service_role;
