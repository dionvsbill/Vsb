begin;

-- The application-level task state machine is text-based so legacy enum values
-- cannot leak into production behavior.
alter table public.watch_tasks alter column status drop default;
alter table public.watch_tasks alter column status type text using status::text;
alter table public.watch_tasks add constraint watch_tasks_state_check check(status in ('assigned','watching','submitted','verified','paid','expired','abandoned','rejected','revoked','reversed'));
alter table public.watch_tasks alter column status set default 'assigned';
alter table public.watch_tasks add column if not exists reward_paid_at timestamptz;
alter table public.watch_tasks add column if not exists reward_entry_id uuid;

-- Verification is evidence-only. It never mints wallet balance.
drop function if exists public.verify_discovery_task(uuid,uuid,uuid,text,text);
create function public.verify_discovery_task(p_task_id uuid,p_session_id uuid,p_worker_id uuid,p_nonce_hash text,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.watch_tasks%rowtype; s public.task_sessions%rowtype; c public.campaigns%rowtype; existing jsonb; required_seconds numeric; now_ts timestamptz:=clock_timestamp();
begin
 if length(coalesce(p_idempotency_key,''))<16 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 insert into public.idempotency_keys(scope,key,locked_at) values('task_verify',p_idempotency_key,now_ts) on conflict(scope,key) do nothing;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 select * into s from public.task_sessions where id=p_session_id for update;
 if not found or s.worker_id<>p_worker_id or s.task_id<>p_task_id then raise exception 'SESSION_NOT_FOUND'; end if;
 if s.nonce_hash<>p_nonce_hash then raise exception 'INVALID_SESSION_NONCE'; end if;
 if s.status<>'submitted' then raise exception 'TASK_MUST_BE_SUBMITTED'; end if;
 if s.expires_at<=now_ts then update public.task_sessions set status='expired',updated_at=now_ts where id=s.id; update public.watch_tasks set status='expired',updated_at=now_ts where id=s.task_id; raise exception 'SESSION_EXPIRED'; end if;
 if s.last_heartbeat_at is null or now_ts-s.last_heartbeat_at>interval '15 seconds' then raise exception 'STALE_PLAYBACK_EVIDENCE'; end if;
 select * into t from public.watch_tasks where id=p_task_id for update;
 if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
 if t.status='paid' then raise exception 'TASK_ALREADY_PAID'; end if;
 if t.status<>'submitted' then raise exception 'TASK_NOT_VERIFIABLE'; end if;
 select * into c from public.campaigns where id=t.campaign_id for update;
 if not found or c.status not in ('approved','active') or coalesce(c.policy_review_status,'pending')<>'approved' then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;
 required_seconds:=greatest(1,coalesce(c.duration_seconds,0))*greatest(0.01,least(coalesce(c.required_watch_percent,100),100))/100;
 if s.server_playback_seconds<required_seconds then raise exception 'INSUFFICIENT_PLAYBACK'; end if;
 if s.visibility_failures>0 or s.seek_events>0 then raise exception 'ABNORMAL_PLAYBACK'; end if;
 if s.heartbeat_count<2 then raise exception 'INSUFFICIENT_HEARTBEATS'; end if;
 update public.watch_tasks set status='verified',watch_end=now_ts,watch_duration_verified=s.server_playback_seconds,watch_percent_verified=least(100,(s.server_playback_seconds/greatest(1,c.duration_seconds))*100),evidence=jsonb_build_object('session_id',s.id,'server_playback_seconds',s.server_playback_seconds,'heartbeat_count',s.heartbeat_count,'last_heartbeat_id',s.last_heartbeat_id,'visibility_failures',s.visibility_failures,'seek_events',s.seek_events),updated_at=now_ts where id=t.id;
 update public.task_sessions set status='verified',updated_at=now_ts,verification_attempts=verification_attempts+1 where id=s.id;
 update public.idempotency_keys set response_status=200,response_body=jsonb_build_object('verified',true,'task_id',t.id,'session_id',s.id,'reward_minor',coalesce(t.earning_amount_minor,round(coalesce(t.earning_amount,0)*100)::bigint),'currency','USD','state','verified') where scope='task_verify' and key=p_idempotency_key;
 return (select response_body from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key);
end; $$;

-- Reward settlement is a separate, idempotent ledger operation.
drop function if exists public.pay_discovery_task(uuid,uuid,text);
create function public.pay_discovery_task(p_task_id uuid,p_worker_id uuid,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.watch_tasks%rowtype; c public.campaigns%rowtype; w public.wallet_accounts%rowtype; fx numeric; reward_minor bigint; ghs_minor bigint; new_balance bigint; count_after integer; entry uuid; existing jsonb; now_ts timestamptz:=clock_timestamp();
begin
 if length(coalesce(p_idempotency_key,''))<16 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
 select response_body into existing from public.idempotency_keys where scope='task_pay' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 insert into public.idempotency_keys(scope,key,locked_at) values('task_pay',p_idempotency_key,now_ts) on conflict(scope,key) do nothing;
 select response_body into existing from public.idempotency_keys where scope='task_pay' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 select * into t from public.watch_tasks where id=p_task_id for update;
 if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
 if t.status='paid' then return jsonb_build_object('success',true,'already_paid',true,'task_id',t.id); end if;
 if t.status<>'verified' then raise exception 'TASK_NOT_READY_FOR_PAYMENT'; end if;
 select * into c from public.campaigns where id=t.campaign_id for update; if not found then raise exception 'CAMPAIGN_NOT_FOUND'; end if;
 reward_minor:=coalesce(t.earning_amount_minor,round(coalesce(t.earning_amount,0)*100)::bigint); if reward_minor<=0 then raise exception 'INVALID_REWARD'; end if;
 select rate_numeric into fx from public.fx_rates where base_currency='USD' and quote_currency='GHS' and effective_from<=now_ts and (effective_to is null or effective_to>now_ts) order by effective_from desc limit 1; if fx is null then raise exception 'FX_RATE_UNAVAILABLE'; end if;
 ghs_minor:=round(reward_minor*fx)::bigint;
 select * into w from public.wallet_accounts where user_id=p_worker_id and currency='GHS' for update; if not found then insert into public.wallet_accounts(user_id,currency,balance_minor) values(p_worker_id,'GHS',0) returning * into w; end if;
 new_balance:=w.balance_minor+ghs_minor; update public.wallet_accounts set balance_minor=new_balance,updated_at=now_ts where id=w.id;
 insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,reference_id,idempotency_key,metadata) values(w.id,ghs_minor,new_balance,'task_earning','watch_task',t.id,'task_pay:'||p_idempotency_key,jsonb_build_object('source_amount_minor',reward_minor,'source_currency','USD','fx_rate',fx,'task_id',t.id)) returning id into entry;
 update public.watch_tasks set status='paid',reward_paid_at=now_ts,reward_entry_id=entry,updated_at=now_ts where id=t.id;
 count_after:=c.completed_count+1; update public.campaigns set completed_count=count_after,status=case when count_after>=c.quantity then 'completed'::campaign_status else status end,updated_at=now_ts where id=c.id;
 update public.idempotency_keys set response_status=200,response_body=jsonb_build_object('success',true,'task_id',t.id,'reward_minor',ghs_minor,'currency','GHS','balance_minor',new_balance,'state','paid','campaign_completed_count',count_after) where scope='task_pay' and key=p_idempotency_key;
 return (select response_body from public.idempotency_keys where scope='task_pay' and key=p_idempotency_key);
end; $$;

revoke all on function public.verify_discovery_task(uuid,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.pay_discovery_task(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.verify_discovery_task(uuid,uuid,uuid,text,text) to service_role;
grant execute on function public.pay_discovery_task(uuid,uuid,text) to service_role;

commit;
