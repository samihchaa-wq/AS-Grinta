begin;

-- ---------------------------------------------------------------------------
-- Un membre ajouté à l'effectif rejoint les matchs à venir déjà programmés.
--
-- Constat du 15 septembre 2026. La liste des participants d'un match est
-- construite au moment où le match est configuré, à partir de l'effectif de
-- cet instant. Rien ne la complète ensuite. Un membre inscrit après coup reste
-- donc absent, en silence, de tous les matchs déjà programmés : pas de demande
-- de disponibilité, pas de relance, pas de convocation, pas de composition.
-- Seule une reconfiguration manuelle du match par un administrateur le
-- rattrapait.
--
-- Vu en production sur le coach arrivé dans l'effectif le 31 août : il
-- manquait sur les deux matchs configurés avant son arrivée, et le
-- planificateur d'ouverture des disponibilités ne pouvait pas le voir, faute
-- de ligne de participation à laquelle s'accrocher.
--
-- Correctif volontairement étroit : arriver dans l'effectif, ou y revenir,
-- crée les lignes manquantes sur les matchs à venir. Rien d'autre.
--
-- En particulier, sortir de l'effectif ne touche à aucune ligne existante.
-- Un membre désactivé reste dans l'instantané des matchs où il figurait déjà,
-- ce que le produit garantit aujourd'hui : un joueur désactivé après coup
-- reste finalisable sur son match. Retirer quelqu'un de la rotation reste le
-- geste explicite d'un administrateur qui resynchronise le match.
--
-- Les matchs passés ne sont jamais touchés : leur liste de participants reste
-- exactement telle qu'elle a été jouée et validée.
--
-- `is_eligible` garde le sens fixé le 15 septembre 2026 par
-- 20260915093000_coach_is_a_regular_member : « joueur de rotation ». Le coach
-- reçoit donc bien sa ligne de participation, à false, comme le fait déjà la
-- synchronisation manuelle d'un match.
-- ---------------------------------------------------------------------------

-- Un match n'a de liste de participants que lorsque le module sportif est
-- configuré pour lui, ce que matérialise sa ligne de workflow. Sans cette
-- garde, on créerait une liste d'un seul membre sur un match qui n'en a
-- jamais eu.
create or replace function private.attach_season_player_to_upcoming_matches(
  p_season_player_id uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_created integer := 0;
begin
  insert into public.match_sport_participants (
    match_id,
    season_player_id,
    is_eligible
  )
  select match.id, player.id, not player.is_coach
  from public.season_players player
  join public.matches match
    on match.season_id = player.season_id
   and match.status = 'a_venir'
  where player.id = p_season_player_id
    and player.is_active
    and exists (
      select 1
      from public.match_sport_workflows workflow
      where workflow.match_id = match.id
    )
  on conflict (match_id, season_player_id) do nothing;

  get diagnostics v_created = row_count;
  return v_created;
end;
$function$;

revoke execute on function private.attach_season_player_to_upcoming_matches(uuid)
  from public, anon, authenticated;

comment on function private.attach_season_player_to_upcoming_matches(uuid) is
  'Creates the missing participant rows of one active season player on every upcoming match of their season.';

create or replace function private.sync_season_player_upcoming_matches()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- Seule l'entrée dans l'effectif agit. La sortie ne touche rien : une ligne
  -- déjà créée, et la réponse qu'elle porte, appartiennent au match.
  if new.is_active and (tg_op = 'INSERT' or not old.is_active) then
    perform private.attach_season_player_to_upcoming_matches(new.id);
  end if;

  return new;
end;
$function$;

comment on function private.sync_season_player_upcoming_matches() is
  'Attaches a season player to the upcoming matches of their season when they join or rejoin the roster.';

drop trigger if exists trg_season_player_joins_upcoming_matches
  on public.season_players;

create trigger trg_season_player_joins_upcoming_matches
after insert or update of is_active on public.season_players
for each row
execute function private.sync_season_player_upcoming_matches();

-- ---------------------------------------------------------------------------
-- Rattrapage des matchs à venir déjà programmés.
--
-- Chaque membre actif de la saison reçoit la ligne qui lui manque. Aucune
-- ligne existante n'est modifiée. L'opération est idempotente : sur une base
-- déjà cohérente, elle ne crée rien.
-- ---------------------------------------------------------------------------

insert into public.match_sport_participants (
  match_id,
  season_player_id,
  is_eligible
)
select match.id, player.id, not player.is_coach
from public.matches match
join public.season_players player
  on player.season_id = match.season_id
 and player.is_active
where match.status = 'a_venir'
  and exists (
    select 1
    from public.match_sport_workflows workflow
    where workflow.match_id = match.id
  )
on conflict (match_id, season_player_id) do nothing;

commit;
