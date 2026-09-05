begin;

alter table public.watch_tasks add column if not exists earning_amount_minor bigint;
alter table public.watch_tasks add column if not exists updated_at timestamptz not null default now();
alter table public.campaigns add column if not exists updated_at timestamptz not null default now();

update public.task_sessions set status='verified', updated_at=now() where status='completed';

drop function if exists public.start_discovery_task(uuid,uuid,text,text,integer);
drop function if exists public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean);
drop function if exists public.verify_discovery_task(uuid,uuid,uuid,text,text);

create function public.start_discovery_task(p_campaign_id uuid,p_worker_id uuid,p_device_fingerprint text,p_nonce_hash text,p_session_ttl_seconds integer default 1800) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.campaigns%rowtype; t public.watch_tasks%rowtype; s public.task_sessions%rowtype; ttl integer; reward_minor bigint;
begin
 if p_campaign_id is null or p_worker_id is null or length(coalesce(p_nonce_hash,''))<32 then raise exception 'INVALID_TASK_SESSION'; end if;
 ttl:=greatest(60,least(coalesce(p_session_ttl_seconds,1800),7200));
 select * into c from public.campaigns where id=p_campaign_id for update;
 if not found then raise exception 'CAMPAIGN_NOT_FOUND'; end if;
 if c.user_id=p_worker_id then raise exception 'CAMPAIGN_OWNER'; end if;
 if c.status not in ('approved','active') then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;
 if coalesce(c.policy_review_status,'pending')<>'approved' then raise exception 'POLICY_NOT_APPROVED'; end if;
 if c.completed_count>=c.quantity then raise exception 'CAMPAIGN_COMPLETE'; end if;
 if not(coalesce(c.task_types,ARRAY[]::text[]) <@ ARRAY['discovery','feedback']::text[]) then raise exception 'NON_COMPLIANT_TASK'; end if;
 if exists(select 1 from public.watch_tasks where campaign_id=p_campaign_id and worker_id=p_worker_id) then raise exception 'ALREADY_ATTEMPTED'; end if;
 if exists(select 1 from public.watch_tasks where campaign_id=p_campaign_id and device_fingerprint=p_device_fingerprint and status in ('assigned','watching','verifying')) then raise exception 'DEVICE_ALREADY_ASSIGNED'; end if;
 reward_minor:=coalesce(c.cost_per_task_minor,round(coalesce(c.cost_per_task,0)*100)::bigint); if reward_minor<=0 then raise exception 'INVALID_REWARD'; end if;
 insert into public.watch_tasks(campaign_id,worker_id,status,watch_start,device_fingerprint,fingerprint,earning_amount,earning_amount_minor,evidence) values(p_campaign_id,p_worker_id,'assigned',now(),p_device_fingerprint,p_device_fingerprint,reward_minor::numeric/100,reward_minor,'{}') returning * into t;
 insert into public.task_sessions(task_id,worker_id,campaign_id,nonce_hash,started_at,expires_at,last_heartbeat_at,status,evidence) values(t.id,p_worker_id,p_campaign_id,p_nonce_hash,now(),now()+make_interval(secs=>ttl),now(),'active',jsonb_build_object('device_fingerprint',p_device_fingerprint)) returning * into s;
 update public.watch_tasks set status='watching',updated_at=now() where id=t.id;
 return jsonb_build_object('task_id',t.id,'session_id',s.id,'expires_at',s.expires_at,'reward_minor',reward_minor,'currency','USD','video',jsonb_build_object('id',c.youtube_video_id,'title',c.youtube_video_title,'thumbnail',c.thumbnail,'duration_seconds',c.duration_seconds));
end; $$;

create function public.record_task_heartbeat(p_session_id uuid,p_client_time_seconds numeric,p_visibility_state text,p_playback_rate numeric,p_seek_detected boolean,p_mouse_activity boolean) returns jsonb
language plpgsql security definer set search_path=public as $$
declare s public.task_sessions%rowtype; hidden_add integer:=0; seek_add integer:=0; current_playback numeric;
begin
 select * into s from public.task_sessions where id=p_session_id for update;
 if not found then raise exception 'SESSION_NOT_FOUND'; end if;
 if s.expires_at<=now() then update public.task_sessions set status='expired',updated_at=now() where id=s.id; update public.watch_tasks set status='expired',updated_at=now() where id=s.task_id and status in ('assigned','watching','verifying'); raise exception 'SESSION_EXPIRED'; end if;
 if s.status not in ('active','submitted') then raise exception 'SESSION_NOT_ACTIVE'; end if;
 if p_visibility_state<>'visible' then hidden_add:=1; end if;
 if coalesce(p_seek_detected,false) then seek_add:=1; end if;
 insert into public.task_heartbeats(session_id,client_time_seconds,visibility_state,playback_rate,seek_detected,mouse_activity) values(s.id,greatest(0,p_client_time_seconds),p_visibility_state,p_playback_rate,coalesce(p_seek_detected,false),coalesce(p_mouse_activity,false));
 current_playback:=greatest(s.playback_seconds,greatest(0,p_client_time_seconds));
 update public.task_sessions set playback_seconds=current_playback,visibility_failures=visibility_failures+hidden_add,seek_events=seek_events+seek_add,last_heartbeat_at=now(),evidence=jsonb_set(jsonb_set(evidence,'{last_visibility}',to_jsonb(p_visibility_state),true),'{last_mouse_activity}',to_jsonb(coalesce(p_mouse_activity,false)),true),updated_at=now() where id=s.id;
 return jsonb_build_object('accepted',true,'session_id',s.id,'playback_seconds',current_playback,'visibility_failures',s.visibility_failures+hidden_add,'seek_events',s.seek_events+seek_add,'expires_at',s.expires_at);
end; $$;

create function public.verify_discovery_task(p_task_id uuid,p_session_id uuid,p_worker_id uuid,p_nonce_hash text,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare t public.watch_tasks%rowtype; s public.task_sessions%rowtype; c public.campaigns%rowtype; w public.wallet_accounts%rowtype; existing jsonb; reward_minor bigint; fx numeric; ghs_minor bigint; new_balance bigint; count_after integer;
begin
 if length(coalesce(p_idempotency_key,''))<16 then raise exception 'INVALID_IDEMPOTENCY_KEY'; end if;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 insert into public.idempotency_keys(scope,key,locked_at) values('task_verify',p_idempotency_key,now()) on conflict(scope,key) do nothing;
 select response_body into existing from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key for update; if existing is not null then return existing; end if;
 select * into s from public.task_sessions where id=p_session_id for update;
 if not found or s.worker_id<>p_worker_id or s.task_id<>p_task_id then raise exception 'SESSION_NOT_FOUND'; end if;
 if s.nonce_hash<>p_nonce_hash then raise exception 'INVALID_SESSION_NONCE'; end if;
 if s.expires_at<=now() then raise exception 'SESSION_EXPIRED'; end if;
 if s.status not in ('active','submitted') then raise exception 'SESSION_NOT_VERIFIABLE'; end if;
 select * into t from public.watch_tasks where id=p_task_id for update;
 if not found or t.worker_id<>p_worker_id then raise exception 'TASK_NOT_FOUND'; end if;
 if t.status='completed' then raise exception 'TASK_ALREADY_COMPLETED'; end if;
 if t.status not in ('assigned','watching','verifying') then raise exception 'TASK_NOT_VERIFIABLE'; end if;
 select * into c from public.campaigns where id=t.campaign_id for update;
 if not found or c.status not in ('approved','active') or coalesce(c.policy_review_status,'pending')<>'approved' then raise exception 'CAMPAIGN_UNAVAILABLE'; end if;
 if c.completed_count>=c.quantity then raise exception 'CAMPAIGN_COMPLETE'; end if;
 if s.playback_seconds<greatest(1,coalesce(c.duration_seconds,0)) then raise exception 'INSUFFICIENT_PLAYBACK'; end if;
 if s.visibility_failures>0 or s.seek_events>0 then raise exception 'ABNORMAL_PLAYBACK'; end if;
 reward_minor:=coalesce(t.earning_amount_minor,round(coalesce(t.earning_amount,0)*100)::bigint); if reward_minor<=0 then raise exception 'INVALID_REWARD'; end if;
 select rate_numeric into fx from public.fx_rates where base_currency='USD' and quote_currency='GHS' and effective_from<=now() and (effective_to is null or effective_to>now()) order by effective_from desc limit 1; if fx is null then raise exception 'FX_RATE_UNAVAILABLE'; end if;
 ghs_minor:=round(reward_minor*fx)::bigint;
 select * into w from public.wallet_accounts where user_id=p_worker_id and currency='GHS' for update;
 if not found then insert into public.wallet_accounts(user_id,currency,balance_minor) values(p_worker_id,'GHS',0) returning * into w; end if;
 new_balance:=w.balance_minor+ghs_minor;
 update public.wallet_accounts set balance_minor=new_balance,updated_at=now() where id=w.id;
 insert into public.wallet_entries(wallet_id,amount_minor,balance_after_minor,entry_type,reference_type,reference_id,idempotency_key,metadata) values(w.id,ghs_minor,new_balance,'task_earning','watch_task',t.id,'task_verify:'||p_idempotency_key,jsonb_build_object('source_amount_minor',reward_minor,'source_currency','USD','fx_rate',fx));
 update public.watch_tasks set status='completed',watch_end=now(),watch_duration_verified=s.playback_seconds,watch_percent_verified=least(100,(s.playback_seconds/greatest(1,c.duration_seconds))*100),completed_at=now(),evidence=jsonb_build_object('session_id',s.id,'playback_seconds',s.playback_seconds,'visibility_failures',s.visibility_failures,'seek_events',s.seek_events,'fx_rate',fx),updated_at=now() where id=t.id;
 update public.task_sessions set status='verified',updated_at=now() where id=s.id;
 count_after:=c.completed_count+1; update public.campaigns set completed_count=count_after,status=case when count_after>=c.quantity then 'completed'::campaign_status else status end,updated_at=now() where id=c.id;
 update public.idempotency_keys set response_status=200,response_body=jsonb_build_object('success',true,'task_id',t.id,'reward_minor',ghs_minor,'currency','GHS','balance_minor',new_balance,'campaign_completed_count',count_after) where scope='task_verify' and key=p_idempotency_key;
 return (select response_body from public.idempotency_keys where scope='task_verify' and key=p_idempotency_key);
end; $$;

revoke all on function public.start_discovery_task(uuid,uuid,text,text,integer) from public,anon,authenticated;
revoke all on function public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean) from public,anon,authenticated;
revoke all on function public.verify_discovery_task(uuid,uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.start_discovery_task(uuid,uuid,text,text,integer) to service_role;
grant execute on function public.record_task_heartbeat(uuid,numeric,text,numeric,boolean,boolean) to service_role;
grant execute on function public.verify_discovery_task(uuid,uuid,uuid,text,text) to service_role;
commit;
