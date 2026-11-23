-- ciao! Private Workspace — run in Supabase SQL Editor
create extension if not exists pgcrypto;
create table if not exists public.ciao_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Участник',
  created_at timestamptz not null default now()
);
create table if not exists public.ciao_workspace (
  id text primary key check (id = 'main'),
  payload jsonb not null default '{"projects":[],"current":null}'::jsonb,
  version bigint not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
insert into public.ciao_workspace(id) values ('main') on conflict do nothing;
alter table public.ciao_members enable row level security;
alter table public.ciao_workspace enable row level security;
revoke all on public.ciao_members from anon, authenticated;
revoke all on public.ciao_workspace from anon, authenticated;
grant select on public.ciao_members to authenticated;
grant select on public.ciao_workspace to authenticated;
create policy "members see members" on public.ciao_members for select to authenticated
using (exists (select 1 from public.ciao_members m where m.user_id = (select auth.uid())));
create policy "members read workspace" on public.ciao_workspace for select to authenticated
using (exists (select 1 from public.ciao_members m where m.user_id = (select auth.uid())));
create or replace function public.ciao_save(expected_version bigint, new_payload jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare next_version bigint;
begin
  if auth.uid() is null or not exists (select 1 from public.ciao_members where user_id = auth.uid()) then
    raise exception 'Access denied' using errcode='42501';
  end if;
  if jsonb_typeof(new_payload) <> 'object' or jsonb_typeof(new_payload->'projects') <> 'array' then
    raise exception 'Invalid payload';
  end if;
  if pg_column_size(new_payload) > 2000000 then
    raise exception 'Payload too large';
  end if;
  update public.ciao_workspace
  set payload=new_payload, version=version+1, updated_at=now(), updated_by=auth.uid()
  where id='main' and version=expected_version returning version into next_version;
  if next_version is null then raise exception 'VERSION_CONFLICT'; end if;
  return next_version;
end $$;
revoke all on function public.ciao_save(bigint,jsonb) from public, anon;
grant execute on function public.ciao_save(bigint,jsonb) to authenticated;
-- In Supabase: Database > Publications > supabase_realtime > add ciao_workspace.
-- After inviting the two users and obtaining their UUIDs, run separately:
-- insert into public.ciao_members(user_id, display_name) values
-- ('UUID_OF_KATYA', 'Катя'), ('UUID_OF_BOGDAN', 'Богдан');
