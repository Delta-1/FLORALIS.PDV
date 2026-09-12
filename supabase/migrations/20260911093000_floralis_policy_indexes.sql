create index if not exists connected_devices_user_idx
  on public.connected_devices(user_id);

drop policy if exists memberships_admin_write on public.memberships;
create policy memberships_admin_insert on public.memberships for insert to authenticated
  with check (public.is_admin(business_id));
create policy memberships_admin_update on public.memberships for update to authenticated
  using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy memberships_admin_delete on public.memberships for delete to authenticated
  using (public.is_admin(business_id));

drop policy if exists products_admin_write on public.products;
create policy products_admin_insert on public.products for insert to authenticated
  with check (public.is_admin(business_id));
create policy products_admin_update on public.products for update to authenticated
  using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy products_admin_delete on public.products for delete to authenticated
  using (public.is_admin(business_id));

drop policy if exists settings_admin_write on public.business_settings;
create policy settings_admin_insert on public.business_settings for insert to authenticated
  with check (public.is_admin(business_id));
create policy settings_admin_update on public.business_settings for update to authenticated
  using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy settings_admin_delete on public.business_settings for delete to authenticated
  using (public.is_admin(business_id));

drop function if exists public.record_client_movement(uuid,uuid,public.ledger_kind,numeric,text);
