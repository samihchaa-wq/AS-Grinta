create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists surnom text;

alter table public.profiles
  drop constraint if exists profiles_role_check;

alter table public.profiles
  add constraint profiles_role_check
  check (role = any (array[
    'pronostiqueur'::text,
    'admin'::text,
    'moderateur'::text,
    'coach'::text
  ]));

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text not null,
  surnom text,
  is_goalkeeper boolean not null default false,
  is_active boolean not null default true,
  linked_profile_id uuid unique references public.profiles(id) on delete set null,
  claimed_at timestamptz,
  claim_token uuid unique,
  claim_expires_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint players_names_not_blank
    check (btrim(first_name) <> '' and btrim(last_name) <> '')
);

create index if not exists players_active_idx
  on public.players (is_active, first_name, last_name);
create index if not exists players_claim_token_idx
  on public.players (claim_token)
  where claim_token is not null;

alter table public.players enable row level security;

drop policy if exists authenticated_read_players on public.players;
create policy authenticated_read_players
on public.players for select
to authenticated
using (true);

drop policy if exists staff_insert_players on public.players;
create policy staff_insert_players
on public.players for insert
to authenticated
with check (public.is_match_staff());

drop policy if exists staff_update_players on public.players;
create policy staff_update_players
on public.players for update
to authenticated
using (public.is_match_staff())
with check (public.is_match_staff());

drop policy if exists staff_delete_players on public.players;
create policy staff_delete_players
on public.players for delete
to authenticated
using (public.is_match_staff());

insert into public.players (
  first_name,
  last_name,
  surnom,
  is_goalkeeper,
  is_active,
  linked_profile_id,
  claimed_at
)
select
  p.first_name,
  p.last_name,
  p.surnom,
  p.is_goalkeeper,
  p.status <> 'archived',
  p.id,
  p.created_at
from public.profiles p
where p.role = 'pronostiqueur'
  and not exists (
    select 1 from public.players pl where pl.linked_profile_id = p.id
  );

create or replace function public.claim_player_profile(claim uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_player public.players%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Vous devez être connecté.';
  end if;

  select * into selected_player
  from public.players
  where claim_token = claim
    and linked_profile_id is null
    and is_active = true
    and (claim_expires_at is null or claim_expires_at > now())
  for update;

  if not found then
    raise exception 'Ce lien est invalide, expiré ou déjà utilisé.';
  end if;

  update public.players
  set linked_profile_id = auth.uid(),
      claimed_at = now(),
      claim_token = null,
      claim_expires_at = null,
      updated_at = now()
  where id = selected_player.id;

  update public.profiles
  set first_name = selected_player.first_name,
      last_name = selected_player.last_name,
      surnom = selected_player.surnom,
      is_goalkeeper = selected_player.is_goalkeeper,
      role = 'pronostiqueur',
      updated_at = now()
  where id = auth.uid();

  return true;
end;
$$;

revoke all on function public.claim_player_profile(uuid) from public;
revoke all on function public.claim_player_profile(uuid) from anon;
grant execute on function public.claim_player_profile(uuid) to authenticated;

grant select, insert, update, delete on public.players to authenticated;
