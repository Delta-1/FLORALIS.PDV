-- Gestão segura de administradores e funcionários para instalações existentes.
alter table public.memberships
  add column if not exists permissions jsonb not null default '{"sales":true,"clients":true,"stock":false,"cash":false,"reports":false}'::jsonb,
  add column if not exists must_change_password boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table public.business_settings
  add column if not exists app_config jsonb not null default '{}'::jsonb;

create or replace function public.complete_password_change(p_business_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  update public.memberships
     set must_change_password=false,updated_at=now()
   where business_id=p_business_id and user_id=auth.uid() and active;
  return found;
end $$;

revoke all on function public.complete_password_change(uuid) from public;
grant execute on function public.complete_password_change(uuid) to authenticated;
