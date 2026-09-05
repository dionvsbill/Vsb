begin;

-- Server-time-bounded playback evidence. Client playback time is only a signal;
-- accepted progress can never advance faster than elapsed server time times the
-- permitted playback rate.
alter table public.task_sessions add column if not exists server_playback_seconds numeric(12,3) not null default 0;
alter table public.task_sessions add column if not exists heartbeat_count integer not null default 0;
alter table public.task_sessions add column if not exists last_heartbeat_id uuid;
alter table public.task_sessions add column if not exists submitted_at timestamptz;
alter table public.task_sessions add column if not exists verification_attempts integer not null default 0;

create index if not exists task_heartbeats_session_created_idx on public.task_heartbeats(session_id,created_at);

-- Replace the heartbeat implementation with a server-time bounded state transition.
drop function if exists public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean);
create function public.record_task_heartbeat(
  p_session_id uuid,
  p_client_time_seconds numeric,
  p_visibility_state text,
  p_playback_rate numeric,
  p_seek_detected boolean,
  p_mouse_activity boolean
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  s public.task_sessions%rowtype;
  hb_id uuid;
  now_ts timestamptz := clock_timestamp();
  elapsed numeric;
  allowed_rate numeric;
  server_increment numeric;
  next_server_playback numeric;
  hidden_add integer := case when p_visibility_state <> 'visible' then 1 else 0 end;
  seek_add integer := case when coalesce(p_seek_detected,false) then 1 else 0 end;
  client_value numeric := greatest(0,coalesce(p_client_time_seconds,0));
  rate_value numeric := greatest(0.25,least(coalesce(p_playback_rate,1),1.5));
begin
  select * into s from public.task_sessions where id=p_session_id for update;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;
  if s.expires_at<=now_ts then
    update public.task_sessions set status='expired',updated_at=now_ts where id=s.id;
    update public.watch_tasks set status='expired',updated_at=now_ts where id=s.task_id and status in ('assigned','watching','verifying');
    raise exception 'SESSION_EXPIRED';
  end if;
  if s.status not in ('active','submitted') then raise exception 'SESSION_NOT_ACTIVE'; end if;
  if s.last_heartbeat_at is not null and now_ts-s.last_heartbeat_at < interval '3 seconds' then
    raise exception 'HEARTBEAT_TOO_FREQUENT';
  end if;

  elapsed := greatest(0,extract(epoch from (now_ts-coalesce(s.last_heartbeat_at,s.started_at))));
  allowed_rate := case when rate_value <= 1.25 then rate_value else 1.25 end;
  server_increment := least(30,elapsed*allowed_rate);
  next_server_playback := least(
    greatest(s.server_playback_seconds,s.playback_seconds)+server_increment,
    greatest(s.server_playback_seconds,s.playback_seconds)+30
  );
  -- Never let a browser jump the authoritative progress forward. The client value
  -- is retained only as evidence and is capped by the server's elapsed-time budget.
  next_server_playback := least(next_server_playback, greatest(s.server_playback_seconds,s.playback_seconds)+server_increment);

  insert into public.task_heartbeats(session_id,client_time_seconds,visibility_state,playback_rate,seek_detected,mouse_activity)
  values(s.id,client_value,p_visibility_state,rate_value,coalesce(p_seek_detected,false),coalesce(p_mouse_activity,false))
  returning id into hb_id;

  update public.task_sessions
  set server_playback_seconds=next_server_playback,
      playback_seconds=next_server_playback,
      visibility_failures=visibility_failures+hidden_add,
      seek_events=seek_events+seek_add,
      last_heartbeat_at=now_ts,
      last_heartbeat_id=hb_id,
      heartbeat_count=heartbeat_count+1,
      evidence=jsonb_build_object(
        'last_visibility',p_visibility_state,
        'last_mouse_activity',coalesce(p_mouse_activity,false),
        'last_client_time_seconds',client_value,
        'last_playback_rate',rate_value,
        'last_server_increment',server_increment,
        'last_heartbeat_id',hb_id,
        'server_now',now_ts
      ),
      updated_at=now_ts
  where id=s.id;

  update public.watch_tasks set status='watching',updated_at=now_ts where id=s.task_id and status='assigned';
  return jsonb_build_object('accepted',true,'heartbeat_id',hb_id,'session_id',s.id,'server_playback_seconds',next_server_playback,'expires_at',s.expires_at,'heartbeat_count',s.heartbeat_count+1);
end; $$;

-- A separate submission step makes verification auditable and gives operators a
-- recovery point before money is credited.
drop function if exists public.submit_discovery_task(uuid,uuid,uuid,text);
create function public.submit_discovery_task(
  p_task_id uuid,
  p_session_id uuid,
  p_worker_id uuid,
  p_nonce_hash text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s public.task_sessions%rowtype; t public.watch_tasks%rowtype; c public.campaigns%rowtype; now_ts timestamptz:=clock_timestamp(); required_seconds numeric;
begin
  select * into s from public.task_sessions where id=p_session_id for update;
  if not found or s.task_id<>p_task_id or s.worker_id<>p_worker_id then raise exception 'SESSION_NOT_FOUND'; end if;
  if s.nonce_hash<>p_nonce_hash then raise exception 'INVALID_SESSION_NONCE'; end if;
  if s.status<>'active' then raise exception 'SESSION_NOT_SUBMITTABLE'; end if;
  if s.expires_at<=now_ts then update public.task_sessions set status='expired',updated_at=now_ts where id=s.id; raise exception 'SESSION_EXPIRED'; end if;
  if s.last_heartbeat_at is null or now_ts-s.last_heartbeat_at>interval '15 seconds' then raise exception 'STALE_PLAYBACK_EVIDENCE'; end if;
  select * into t from public.watch_tasks where id=p_task_id for update;
  if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
  if t.status not in ('assigned','watching','verifying') then raise exception 'TASK_NOT_SUBMITTABLE'; end if;
  select * into c from public.campaigns where id=t.campaign_id for update;
  if not found or c.status not in ('approved','active') or coalesce(c.policy_review_status,'pending')<>'approved' then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;
  required_seconds:=greatest(1,coalesce(c.duration_seconds,0))*greatest(0.01,least(coalesce(c.required_watch_percent,100),100))/100;
  if s.server_playback_seconds<required_seconds then raise exception 'INSUFFICIENT_PLAYBACK'; end if;
  if s.visibility_failures>0 or s.seek_events>0 then raise exception 'ABNORMAL_PLAYBACK'; end if;
  update public.task_sessions set status='submitted',submitted_at=now_ts,updated_at=now_ts,evidence=jsonb_set(evidence,'{submitted}',jsonb_build_object('at',now_ts,'last_heartbeat_id',last_heartbeat_id),true) where id=s.id;
  update public.watch_tasks set status='verifying',watch_duration_verified=s.server_playback_seconds,updated_at=now_ts where id=t.id;
  return jsonb_build_object('submitted',true,'task_id',t.id,'session_id',s.id,'server_playback_seconds',s.server_playback_seconds);
end; $$;

-- Verification now requires the submitted state and server-bounded evidence.
drop function if exists public.verify_discovery_task(uuid,uuid,uuid,text,text);
create function public.verify_discovery_task(p_task_id uuid,p_session_id uuid,p_worker_id uuid,p_nonce_hash text,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.watch_tasks%rowtype; s public.task_sessions%rowtype; c public.campaigns%rowtype; w public.wallet_accounts%rowtype; existing jsonb; reward_minor bigint; fx numeric; ghs_minor bigint; new_balance bigint; count_after integer; required_seconds numeric; now_ts timestamptz:=clock_timestamp();
begin
 if length(coalesce(p_idempotency_key,''))<16 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 insert into public.idempotency_keys(scope,key,locked_at) values('task_verify',p_idempotency_key,now_ts) on conflict(scope,key) do nothing;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 select * into s from public.task_sessions where id=p_session_id for update;
 if not found or s.worker_id<>p_worker_id or s.task_id<>p_task_id then raise exception 'SESSION_NOT_FOUND'; end if;
 if s.nonce_hash<>p_nonce_hash then raise exception 'INVALID_SESSION_NONCE'; end if;
 if s.status<>'submitted' then raise exception 'TASK_MUST_BE_SUBMITTED'; end if;
 if s.expires_at<=now_ts then update public.task_sessions set status='expired',updated_at=now_ts where id=s.id; raise exception 'SESSION_EXPIRED'; end if;
 if s.last_heartbeat_at is null or now_ts-s.last_heartbeat_at>interval '15 seconds' then raise exception 'STALE_PLAYBACK_EVIDENCE'; end if;
 select * into t from public.watch_tasks where id=p_task_id for update;
 if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
 if t.status='completed' then raise exception 'TASK_ALREADY_COMPLETED'; end if;
 if t.status<>'verifying' then raise exception 'TASK_NOT_VERIFIABLE'; end if;
 select * into c from public.campaigns where id=t.campaign_id for update;
 if not found or c.status not in ('approved','active') or coalesce(c.policy_review_status,'pending')<>'approved' then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;
 if c.completed_count>=c.quantity then raise exception 'CAMPAIGN_COMPLETE'; end if;
 required_seconds:=greatest(1,coalesce(c.duration_seconds,0))*greatest(0.01,least(coalesce(c.required_watch_percent,100),100))/100;
 if s.server_playback_seconds<required_seconds then raise exception 'INSUFFICIENT_PLAYBACK'; end if;
 if s.visibility_failures>0 or s.seek_events>0 then raise exception 'ABNORMAL_PLAYBACK'; end if;
 if s.heartbeat_count<2 then raise exception 'INSUFFICIENT_HEARTBEATS'; end if;
 reward_minor:=coalesce(t.earning_amount_minor,round(coalesce(t.earning_amount,0)*100)::bigint); if reward_minor<=0 then raise exception 'INVALID_REWARD'; end if;
 select rate_numeric into fx from public.fx_rates where base_currency='USD' and quote_currency='GHS' and effective_from<=now_ts and (effective_to is null or effective_to>now_ts) order by effective_from desc limit 1;
 if fx is null then raise exception 'FX_RATE_UNAVAILABLE'; end if;
 ghs_minor:=round(reward_minor*fx)::bigint;
 select * into w from public.wallet_accounts where user_id=p_worker_id and currency='GHS' for update;
 if not found then insert into public.wallet_accounts(user_id,currency,balance_minor) values(p_worker_id,'GHS',0) returning * into w; end if;
 new_balance:=w.balance_minor+ghs_minor;
 update public.wallet_accounts set balance_minor=new_balance,updated_at=now_ts where id=w.id;
 insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,reference_id,idempotency_key,metadata)
 values(w.id,ghs_minor,new_balance,'task_earning','watch_task',t.id,'task_verify:'||p_idempotency_key,jsonb_build_object('source_amount_minor',reward_minor,'source_currency','USD','fx_rate',fx,'session_id',s.id,'last_heartbeat_id',s.last_heartbeat_id));
 update public.watch_tasks set status='completed',watch_end=now_ts,watch_duration_verified=s.server_playback_seconds,watch_percent_verified=least(100,(s.server_playback_seconds/greatest(1,c.duration_seconds))*100),completed_at=now_ts,evidence=jsonb_build_object('session_id',s.id,'server_playback_seconds',s.server_playback_seconds,'heartbeat_count',s.heartbeat_count,'last_heartbeat_id',s.last_heartbeat_id,'visibility_failures',s.visibility_failures,'seek_events',s.seek_events,'fx_rate',fx),updated_at=now_ts where id=t.id;
 update public.task_sessions set status='verified',updated_at=now_ts,verification_attempts=verification_attempts+1 where id=s.id;
 count_after:=c.completed_count+1;
 update public.campaigns set completed_count=count_after,status=case when count_after>=c.quantity then 'completed'::campaign_status else status end,updated_at=now_ts where id=c.id;
 update public.idempotency_keys set response_status=200,response_body=jsonb_build_object('success',true,'task_id',t.id,'reward_minor',ghs_minor,'currency','GHS','balance_minor',new_balance,'campaign_completed_count',count_after) where scope='task_verify' and key=p_idempotency_key;
 return (select response_body from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key);
end; $$;

revoke all on function public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean) from public,anon,authenticated;
revoke all on function public.submit_discovery_task(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.verify_discovery_task(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean) to service_role;
grant execute on function public.submit_discovery_task(uuid,uuid,uuid,text) to service_role;
grant execute on function public.verify_discovery_task(uuid,uuid,uuid,text,text) to service_role;

commit;
