-- Registro seguro dos dispositivos que acessam a instalação exclusiva da FLORALES.
create table if not exists public.connected_devices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  terminal_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  user_name text not null,
  user_email text,
  device_type text not null default 'desktop' check (device_type in ('desktop','mobile','tablet','unknown')),
  platform text not null default 'PC' check (platform in ('PC','Android','iOS','Unknown')),
  browser text,
  user_agent text,
  channel text not null default 'ERP' check (channel in ('ERP','PDV')),
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  last_login timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,terminal_id)
);

create index if not exists connected_devices_business_seen_idx
  on public.connected_devices (business_id,last_seen desc);

alter table public.connected_devices enable row level security;

drop policy if exists connected_devices_admin_select on public.connected_devices;
create policy connected_devices_admin_select
  on public.connected_devices for select to authenticated
  using (public.is_admin(business_id));

create or replace function public.register_connected_device(
  p_business_id uuid,
  p_terminal_id text,
  p_device_type text,
  p_platform text,
  p_browser text default null,
  p_user_agent text default null,
  p_channel text default 'ERP',
  p_is_login boolean default false
)
returns public.connected_devices
language plpgsql
security definer
set search_path=public
as $$
declare
  member public.memberships%rowtype;
  registered public.connected_devices%rowtype;
begin
  select * into member
    from public.memberships
   where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if nullif(trim(p_terminal_id),'') is null then raise exception 'invalid terminal'; end if;

  insert into public.connected_devices (
    business_id,terminal_id,user_id,user_name,user_email,device_type,platform,
    browser,user_agent,channel,last_seen,last_login,updated_at
  ) values (
    p_business_id,left(trim(p_terminal_id),80),auth.uid(),member.display_name,member.email,
    case when p_device_type in ('desktop','mobile','tablet','unknown') then p_device_type else 'unknown' end,
    case when p_platform in ('PC','Android','iOS','Unknown') then p_platform else 'Unknown' end,
    nullif(left(trim(coalesce(p_browser,'')),80),''),nullif(left(coalesce(p_user_agent,''),500),''),
    case when p_channel='PDV' then 'PDV' else 'ERP' end,now(),now(),now()
  )
  on conflict (business_id,terminal_id) do update set
    user_id=excluded.user_id,
    user_name=excluded.user_name,
    user_email=excluded.user_email,
    device_type=excluded.device_type,
    platform=excluded.platform,
    browser=excluded.browser,
    user_agent=excluded.user_agent,
    channel=excluded.channel,
    last_seen=now(),
    last_login=case when p_is_login then now() else connected_devices.last_login end,
    updated_at=now()
  returning * into registered;

  return registered;
end $$;

revoke all on public.connected_devices from anon;
grant select on public.connected_devices to authenticated;
revoke all on function public.register_connected_device(uuid,text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.register_connected_device(uuid,text,text,text,text,text,text,boolean) to authenticated;
