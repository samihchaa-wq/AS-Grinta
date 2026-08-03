-- Schéma minimal de production requis pour tester le durcissement des
-- compositions des matchs « entre nous ». La migration historique complète
-- redéfinit aussi d'anciennes fonctions métier ; la rejouer en fin de baseline
-- CI écraserait des correctifs plus récents. On reproduit donc uniquement les
-- deux tables et leurs policies antérieures au durcissement.

create table public.match_internal_compositions (
  match_id uuid primary key
    references public.matches(id) on delete cascade,
  team1_name text not null default 'Équipe 1',
  team2_name text not null default 'Équipe 2',
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table public.match_internal_compositions enable row level security;

create policy active_authenticated_profile_only
  on public.match_internal_compositions
  as restrictive
  for all
  to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

create policy match_internal_compositions_select
  on public.match_internal_compositions for select
  to authenticated
  using (true);

create policy match_internal_compositions_write
  on public.match_internal_compositions for all
  to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());

create table public.match_internal_composition_entries (
  match_id uuid not null
    references public.match_internal_compositions(match_id) on delete cascade,
  participant_id uuid not null,
  team_no smallint,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (match_id, participant_id),
  constraint match_internal_composition_entries_team_no_check
    check (team_no is null or team_no in (1, 2)),
  constraint match_internal_composition_entries_participant_fkey
    foreign key (participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete cascade
);

alter table public.match_internal_composition_entries enable row level security;

create policy active_authenticated_profile_only
  on public.match_internal_composition_entries
  as restrictive
  for all
  to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

create policy match_internal_composition_entries_select
  on public.match_internal_composition_entries for select
  to authenticated
  using (true);

create policy match_internal_composition_entries_write
  on public.match_internal_composition_entries for all
  to authenticated
  using (public.is_match_staff())
  with check (public.is_match_staff());
