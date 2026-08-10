-- Sépare les joueurs métier des comptes de connexion.
-- Cette migration est volontairement non destructive : l'application actuelle
-- continue d'utiliser profiles/season_players pendant la transition.

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  first_name text not null,
  last_name text not null,
  display_name text generated always as (
    trim(concat_ws(' ', first_name, last_name))
  ) stored,
  is_goalkeeper boolean not null default false,
  linked_profile_id uuid unique references public.profiles(id) on delete set null,
  claim_token uuid unique,
  claim_expires_at timestamptz,
  claimed_at timestamptz,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint players_name_not_empty check (
    length(trim(first_name)) > 0 and length(trim(last_name)) > 0
  )
);

create unique index if not exists players_unique_active_name_idx
on public.players (lower(trim(first_name)), lower(trim(last_name)))
where archived_at is null;

create index if not exists players_linked_profile_idx
on public.players(linked_profile_id);

create index if not exists players_claim_token_idx
on public.players(claim_token)
where claim_token is not null;

-- Backfill des joueurs existants sans créer de doublons.
insert into public.players (
  first_name,
  last_name,
  is_goalkeeper,
  linked_profile_id,
  claimed_at,
  is_active,
  archived_at,
  created_at,
  updated_at
)
select
  p.first_name,
  p.last_name,
  p.is_goalkeeper,
  p.id,
  now(),
  coalesce(p.is_active, true),
  p.archived_at,
  p.created_at,
  p.updated_at
from public.profiles p
where p.role = 'pronostiqueur'
  and not exists (
    select 1
    from public.players pl
    where pl.linked_profile_id = p.id
  );

-- Lien de transition entre l'effectif saisonnier actuel et le nouveau registre.
alter table public.season_players
  add column if not exists roster_player_id uuid references public.players(id) on delete restrict;

update public.season_players sp
set roster_player_id = pl.id
from public.players pl
where sp.roster_player_id is null
  and pl.linked_profile_id = sp.player_id;

create index if not exists season_players_roster_player_idx
on public.season_players(roster_player_id);

-- Génère ou renouvelle un lien de prise de possession pour un joueur non lié.
create or replace function public.generate_player_claim_token(
  target_player_id uuid,
  valid_for interval default interval '14 days'
)
returns table(token uuid, expires_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  generated_token uuid := gen_random_uuid();
  generated_expiry timestamptz := now() + valid_for;
begin
  if not exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('admin', 'moderateur')
      and coalesce(is_active, true) = true
  ) then
    raise exception 'Accès refusé';
  end if;

  update public.players
  set claim_token = generated_token,
      claim_expires_at = generated_expiry,
      updated_at = now()
  where id = target_player_id
    and linked_profile_id is null
    and archived_at is null;

  if not found then
    raise exception 'Joueur introuvable, archivé ou déjà lié à un compte';
  end if;

  return query select generated_token, generated_expiry;
end;
$$;

-- Lie le compte connecté au joueur visé par le lien.
-- Le prénom et le nom restent ceux du registre players et ne sont pas modifiés.
create or replace function public.claim_player_profile(claim uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_player public.players%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Connexion requise';
  end if;

  select *
  into target_player
  from public.players
  where claim_token = claim
    and linked_profile_id is null
    and archived_at is null
    and claim_expires_at > now()
  for update;

  if not found then
    raise exception 'Lien invalide ou expiré';
  end if;

  if exists (
    select 1 from public.players where linked_profile_id = auth.uid()
  ) then
    raise exception 'Ce compte est déjà lié à un joueur';
  end if;

  update public.players
  set linked_profile_id = auth.uid(),
      claim_token = null,
      claim_expires_at = null,
      claimed_at = now(),
      updated_at = now()
  where id = target_player.id;

  update public.profiles
  set first_name = target_player.first_name,
      last_name = target_player.last_name,
      is_goalkeeper = target_player.is_goalkeeper,
      role = 'pronostiqueur',
      updated_at = now()
  where id = auth.uid();

  return target_player.id;
end;
$$;

grant execute on function public.generate_player_claim_token(uuid, interval) to authenticated;
grant execute on function public.claim_player_profile(uuid) to authenticated;

alter table public.players enable row level security;

create policy "authenticated users can read active players"
on public.players
for select
to authenticated
using (archived_at is null);

create policy "admins and moderators can manage players"
on public.players
for all
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role in ('admin', 'moderateur')
      and coalesce(p.is_active, true) = true
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role in ('admin', 'moderateur')
      and coalesce(p.is_active, true) = true
  )
);
