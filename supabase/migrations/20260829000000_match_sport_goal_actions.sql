begin;

-- Compte rendu de match : les buts deviennent des faits durables.
--
-- Jusqu'ici, la validation d'un match ne conservait que des compteurs par
-- joueur (`final_goals`, `final_assists`). Le lien exact « ce but-là, marqué
-- par X, servi par Y, à la minute Z » n'existait que dans le journal du Live,
-- qui peut être supprimé sans toucher aux statistiques.
--
-- Cette migration installe la table permanente `match_sport_goal_actions` :
-- un fait sportif par but, des deux côtés, indépendant du journal Live. Les
-- compteurs agrégés restent, mais ils sont désormais **dérivés côté serveur**
-- à partir de ces faits, jamais saisis par le client.

-- ---------------------------------------------------------------------------
-- 1. Table des faits du match
-- ---------------------------------------------------------------------------

create table if not exists public.match_sport_goal_actions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  ordinal integer not null,
  minute smallint,
  team_side text not null,
  scorer_participant_id uuid,
  assist_participant_id uuid,
  assist_kind text not null default 'unknown',
  is_own_goal boolean not null default false,
  source text not null default 'manual',
  source_live_event_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid,
  updated_at timestamptz not null default now(),
  updated_by uuid,
  constraint match_sport_goal_actions_ordinal_check
    check (ordinal >= 0 and ordinal <= 199),
  -- La minute est facultative (« minute inconnue ») ; renseignée, elle est un
  -- entier de 0 à 90. Les arrêts de jeu ne sont pas modélisés dans cette
  -- version : 45+2 se saisit comme 45.
  constraint match_sport_goal_actions_minute_check
    check (minute is null or (minute >= 0 and minute <= 90)),
  constraint match_sport_goal_actions_team_side_check
    check (team_side in ('as_grinta', 'opponent')),
  constraint match_sport_goal_actions_source_check
    check (source in ('live', 'manual', 'legacy')),
  -- Trois états distincts pour la passe décisive : un joueur, « aucune passe »
  -- ou « non attribuée ». Sans cela, un but sans passe et un but dont on a
  -- oublié le passeur seraient indiscernables.
  constraint match_sport_goal_actions_assist_kind_check
    check (assist_kind in ('player', 'none', 'unknown')),
  constraint match_sport_goal_actions_assist_kind_consistency_check
    check ((assist_kind = 'player') = (assist_participant_id is not null)),
  -- Ni un but adverse ni un contre-son-camp ne peut porter une passe décisive.
  constraint match_sport_goal_actions_assist_kind_scope_check
    check (
      (team_side = 'as_grinta' and not is_own_goal)
      or assist_kind = 'none'
    ),
  -- Un joueur ne peut jamais être son propre passeur.
  constraint match_sport_goal_actions_assist_distinct_check
    check (
      assist_participant_id is null
      or assist_participant_id is distinct from scorer_participant_id
    ),
  -- Une passe décisive suppose un buteur identifié.
  constraint match_sport_goal_actions_assist_requires_scorer_check
    check (assist_participant_id is null or scorer_participant_id is not null),
  -- Un but adverse ne crédite jamais un joueur d'AS Grinta.
  constraint match_sport_goal_actions_opponent_check
    check (
      team_side <> 'opponent'
      or (scorer_participant_id is null and assist_participant_id is null)
    ),
  -- Un contre-son-camp (CSC adverse comme CSC AS Grinta) ne crédite ni buteur
  -- ni passeur.
  constraint match_sport_goal_actions_own_goal_check
    check (
      not is_own_goal
      or (scorer_participant_id is null and assist_participant_id is null)
    ),
  -- Buteur et passeur appartiennent obligatoirement au même match.
  constraint match_sport_goal_actions_scorer_match_fkey
    foreign key (scorer_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  constraint match_sport_goal_actions_assist_match_fkey
    foreign key (assist_participant_id, match_id)
    references public.match_sport_participants(id, match_id) on delete restrict,
  -- Le journal Live reste supprimable sans emporter le fait sportif.
  constraint match_sport_goal_actions_live_event_fkey
    foreign key (source_live_event_id)
    references public.match_live_events(id) on delete set null
);

comment on table public.match_sport_goal_actions is
  'Faits sportifs définitifs du compte rendu : un but par ligne, des deux côtés, indépendant du journal Live.';
comment on column public.match_sport_goal_actions.ordinal is
  'Ordre stable choisi par l''administrateur. Les minutes inconnues gardent ainsi une place fixe.';
comment on column public.match_sport_goal_actions.is_own_goal is
  'But contre son camp : côté as_grinta il s''agit d''un CSC adverse, côté opponent d''un CSC AS Grinta.';

-- Ordre stable et unique dans un match.
create unique index if not exists match_sport_goal_actions_match_ordinal_idx
  on public.match_sport_goal_actions (match_id, ordinal);

-- Index de couverture : sans eux, retirer un participant balaye la table.
create index if not exists match_sport_goal_actions_scorer_idx
  on public.match_sport_goal_actions (scorer_participant_id, match_id);
create index if not exists match_sport_goal_actions_assist_idx
  on public.match_sport_goal_actions (assist_participant_id, match_id);
create index if not exists match_sport_goal_actions_live_event_idx
  on public.match_sport_goal_actions (source_live_event_id);

alter table public.match_sport_goal_actions enable row level security;

-- Lecture pour les profils actifs, comme le journal Live. Aucune écriture
-- directe : tout passe par les fonctions SECURITY DEFINER ci-dessous.
drop policy if exists "active_authenticated_profile_only"
  on public.match_sport_goal_actions;
create policy "active_authenticated_profile_only"
  on public.match_sport_goal_actions
  as restrictive to authenticated
  using ((select private.is_active_profile()))
  with check ((select private.is_active_profile()));

drop policy if exists "match_sport_goal_actions_active_profile_select"
  on public.match_sport_goal_actions;
create policy "match_sport_goal_actions_active_profile_select"
  on public.match_sport_goal_actions
  for select to authenticated
  using (
    (select private.is_feature_enabled('sports_management'))
    and (select private.is_active_profile())
  );

revoke all on table public.match_sport_goal_actions from public;
grant select on table public.match_sport_goal_actions to authenticated;
grant all on table public.match_sport_goal_actions to service_role;

-- ---------------------------------------------------------------------------
-- 2. Composition de départ complète, capturée au coup d'envoi
-- ---------------------------------------------------------------------------
--
-- `starting_lineup_snapshot` ne retient que la zone (terrain/banc). Le compte
-- rendu doit rejouer le **placement** exact d'avant le coup d'envoi, pas la
-- disposition d'après les remplacements : on capture donc aussi x/y et le
-- dispositif, sans toucher au chemin de démarrage existant.

alter table public.match_live_sessions
  add column if not exists starting_lineup_entries jsonb;
alter table public.match_live_sessions
  add column if not exists starting_formation_code text;

comment on column public.match_live_sessions.starting_lineup_entries is
  'Placement exact (zone, x, y) de chaque joueur au coup d''envoi. Sert au compte rendu.';

create or replace function private.capture_live_starting_lineup()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.state = 'running' and old.state = 'not_started'
     and new.starting_lineup_entries is null then
    select coalesce(
      jsonb_object_agg(
        entry.participant_id::text,
        jsonb_build_object(
          'zone', entry.zone,
          'x', entry.x,
          'y', entry.y,
          'slot_label', entry.slot_label,
          'sort_order', entry.sort_order
        )
      ),
      '{}'::jsonb
    )
    into new.starting_lineup_entries
    from public.match_composition_entries entry
    where entry.match_id = new.match_id
      and entry.zone in ('field', 'bench');

    select composition.formation_code
    into new.starting_formation_code
    from public.match_compositions composition
    where composition.match_id = new.match_id;
  end if;

  -- Une relance du suivi efface la composition de départ, comme elle efface
  -- déjà `starting_lineup_snapshot`.
  if new.state = 'not_started' and old.state is distinct from 'not_started' then
    new.starting_lineup_entries := null;
    new.starting_formation_code := null;
  end if;

  return new;
end;
$function$;

alter function private.capture_live_starting_lineup() owner to postgres;
-- Fonction de déclencheur : elle n'est jamais appelée depuis le client, et le
-- plancher ACL du projet refuse une fonction private mutatrice exécutable par
-- `authenticated` sans façade publique.
revoke all on function private.capture_live_starting_lineup() from public;
revoke all on function private.capture_live_starting_lineup() from authenticated;

drop trigger if exists capture_live_starting_lineup
  on public.match_live_sessions;
create trigger capture_live_starting_lineup
  before update on public.match_live_sessions
  for each row execute function private.capture_live_starting_lineup();

commit;
