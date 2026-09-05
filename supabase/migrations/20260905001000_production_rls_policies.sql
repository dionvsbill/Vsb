begin;

-- Baseline RLS policy layer. This runs immediately after the ordered schema baseline,
-- before additive business migrations, so a clean database is usable without relying
-- on migrations that previously lived outside the repository.

create policy users_self_select on public.users for select to authenticated using ((id=auth.uid()) or private.is_staff());
create policy users_self_update on public.users for update to authenticated using ((id=auth.uid()) or private.is_staff()) with check ((id=auth.uid()) or private.is_staff());

create policy settings_read on public.platform_settings for select to authenticated using (true);
create policy settings_superadmin_update on public.platform_settings for update to authenticated using (private.is_superadmin()) with check (private.is_superadmin());

create policy campaigns_owner_insert on public.campaigns for insert to authenticated with check ((user_id=auth.uid()) and exists(select 1 from public.users u where u.id=auth.uid() and u.is_paid=true and u.is_banned=false));
create policy campaigns_owner_update on public.campaigns for update to authenticated using ((user_id=auth.uid()) or private.is_staff()) with check ((user_id=auth.uid()) or private.is_staff());
create policy campaigns_public_approved on public.campaigns for select to authenticated using ((status in ('approved','active','completed')) or (user_id=auth.uid()) or private.is_staff());

create policy referrals_self_select on public.referrals for select to authenticated using ((referrer_id=auth.uid()) or (referred_id=auth.uid()) or private.is_staff());
create policy transactions_self_select on public.transactions for select to authenticated using ((user_id=auth.uid()) or private.is_staff());
create policy wallet_ledger_owner_select on public.wallet_ledger for select to authenticated using (user_id=auth.uid());
create policy wallets_owner_select on public.wallets for select to authenticated using (user_id=auth.uid());
create policy wallet_accounts_owner_select on public.wallet_accounts for select to authenticated using (user_id=auth.uid());
create policy wallet_entries_owner_select on public.wallet_entries for select to authenticated using (exists(select 1 from public.wallet_accounts w where w.id=wallet_entries.wallet_id and w.user_id=auth.uid()));

create policy watch_tasks_worker_select on public.watch_tasks for select to authenticated using ((worker_id=auth.uid()) or exists(select 1 from public.campaigns c where c.id=watch_tasks.campaign_id and c.user_id=auth.uid()) or private.is_staff());
create policy task_sessions_owner_select on public.task_sessions for select to authenticated using (worker_id=auth.uid());
create policy task_heartbeats_owner_select on public.task_heartbeats for select to authenticated using (exists(select 1 from public.task_sessions s where s.id=task_heartbeats.session_id and s.worker_id=auth.uid()));

create policy violations_staff_select on public.violations for select to authenticated using ((user_id=auth.uid()) or private.is_staff());
create policy violations_staff_insert on public.violations for insert to authenticated with check (private.is_staff());
create policy violation_logs_staff_select on public.violation_logs for select to authenticated using ((user_id=auth.uid()) or private.is_staff());
create policy payouts_owner_select on public.payouts for select to authenticated using ((user_id=auth.uid()) or private.is_staff());
create policy payouts_staff_manage on public.payouts for update to authenticated using (private.is_staff()) with check (private.is_staff());
create policy payout_methods_owner_all on public.payout_methods for all to authenticated using ((user_id=auth.uid()) or private.is_staff()) with check ((user_id=auth.uid()) or private.is_staff());
create policy support_owner_insert on public.support_tickets for insert to authenticated with check (user_id=auth.uid());
create policy support_owner_select on public.support_tickets for select to authenticated using ((user_id=auth.uid()) or private.is_staff());
create policy data_rights_owner_all on public.data_rights_requests for all to authenticated using ((user_id=auth.uid()) or private.is_staff()) with check ((user_id=auth.uid()) or private.is_staff());
create policy audit_staff_insert on public.audit_logs for insert to authenticated with check (private.is_staff());
create policy audit_staff_select on public.audit_logs for select to authenticated using (private.is_staff());
create policy audit_events_service_only on public.audit_events for all to authenticated using (false) with check (false);

create policy business_shops_owner_insert on public.business_shops for insert to authenticated with check (user_id=auth.uid());
create policy business_shops_owner_select on public.business_shops for select to authenticated using (user_id=auth.uid());
create policy business_shops_owner_update on public.business_shops for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy inventory_owner_insert on public.inventory_products for insert to authenticated with check (user_id=auth.uid());
create policy inventory_owner_select on public.inventory_products for select to authenticated using (user_id=auth.uid());
create policy inventory_owner_update on public.inventory_products for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy inventory_owner_delete on public.inventory_products for delete to authenticated using (user_id=auth.uid());
create policy shop_customers_owner_select on public.shop_customers for select to authenticated using (exists(select 1 from public.business_shops s where s.id=shop_customers.shop_id and s.user_id=auth.uid()));
create policy shop_orders_owner_select on public.shop_orders for select to authenticated using (exists(select 1 from public.business_shops s where s.id=shop_orders.shop_id and s.user_id=auth.uid()));
create policy shop_order_items_owner_select on public.shop_order_items for select to authenticated using (exists(select 1 from public.shop_orders o join public.business_shops s on s.id=o.shop_id where o.id=shop_order_items.order_id and s.user_id=auth.uid()));
create policy shop_order_events_owner_select on public.shop_order_events for select to authenticated using (exists(select 1 from public.shop_orders o join public.business_shops s on s.id=o.shop_id where o.id=shop_order_events.order_id and s.user_id=auth.uid()));
create policy shop_settlements_owner_select on public.shop_settlements for select to authenticated using (exists(select 1 from public.business_shops s where s.id=shop_settlements.shop_id and s.user_id=auth.uid()));
create policy shop_subscription_owner_select on public.shop_subscriptions for select to authenticated using (user_id=auth.uid());
create policy whatsapp_connections_owner_select on public.whatsapp_connections for select to authenticated using (exists(select 1 from public.business_shops s where s.id=whatsapp_connections.shop_id and s.user_id=auth.uid()));
create policy whatsapp_conversations_owner_select on public.whatsapp_conversations for select to authenticated using (exists(select 1 from public.business_shops s where s.id=whatsapp_conversations.shop_id and s.user_id=auth.uid()));
create policy whatsapp_messages_owner_select on public.whatsapp_messages_shop for select to authenticated using (exists(select 1 from public.whatsapp_conversations c join public.business_shops s on s.id=c.shop_id where c.id=whatsapp_messages_shop.conversation_id and s.user_id=auth.uid()));
create policy whatsapp_flows_owner_all on public.whatsapp_flows for all to authenticated using (exists(select 1 from public.business_shops s where s.id=whatsapp_flows.shop_id and s.user_id=auth.uid())) with check (exists(select 1 from public.business_shops s where s.id=whatsapp_flows.shop_id and s.user_id=auth.uid()));
create policy whatsapp_shop_flows_owner_all on public.whatsapp_shop_flows for all to authenticated using (exists(select 1 from public.business_shops s where s.id=whatsapp_shop_flows.shop_id and s.user_id=auth.uid())) with check (exists(select 1 from public.business_shops s where s.id=whatsapp_shop_flows.shop_id and s.user_id=auth.uid()));
create policy jforce_clicks_owner_select on public.jforce_clicks for select to authenticated using (exists(select 1 from public.business_shops s where s.id=jforce_clicks.shop_id and s.user_id=auth.uid()));

-- These tables contain provider/server state and have no direct client policy.
-- RLS remains enabled and server routes use the secret-key client.

commit;
