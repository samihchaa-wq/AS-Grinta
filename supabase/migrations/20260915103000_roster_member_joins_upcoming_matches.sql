begin;

-- ---------------------------------------------------------------------------
-- Un membre ajouté à l'effectif rejoint les matchs à venir déjà créés.
--
-- Constat du 15 septembre 2026. La liste des participants d'un match est
-- construite au moment où le match est configuré, à partir de l'effectif de
-- cet instant. Rien ne la complète ensuite. Un membre inscrit après coup reste
-- donc absent, en silence, de tous les matchs déjà créés : pas de demande de
-- disponibilité, pas de relance, pas de convocation, pas de composition. Seule
-- une reconfiguration manuelle du match par un administrateur le rattrapait.
--
-- Vu en production sur le coach arrivé dans l'effectif le 31 août : il
-- manquait sur les deux matchs configurés avant son arrivée, et le
-- planificateur d'ouverture des disponibilités ne pouvait pas le voir, faute
-- de ligne de participation à laquelle s'accrocher.
--
-- Correctif : l'effectif de la saison et les matchs à venir restent alignés
-- sans intervention. L'arrivée d'un membre et sa réactivation lui créent ses
-- lignes manquantes ; sa désactivation le sort de la rotation sans effacer
-- quoi que ce soit.
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
  if tg_op = 'INSERT' then
    if new.is_active then
      perform private.attach_season_player_to_upcoming_matches(new.id);
    end if;
    return new;
  end if;

  if new.is_active and not old.is_active then
    -- Retour dans l'effectif : les lignes manquantes sont créées, et celles
    -- que la désactivation avait sorties de la rotation y reviennent.
    perform private.attach_season_player_to_upcoming_matches(new.id);

    update public.match_sport_participants participant
    set is_eligible = not new.is_coach,
        updated_at = now()
    from public.matches match
    where participant.season_player_id = new.id
      and participant.match_id = match.id
      and match.status = 'a_venir'
      and participant.is_eligible is distinct from (not new.is_coach);
  elsif old.is_active and not new.is_active then
    -- Sortie de l'effectif : la ligne reste, pour ne rien perdre d'une
    -- réponse déjà donnée, mais le membre quitte la rotation.
    update public.match_sport_participants participant
    set is_eligible = false,
        updated_at = now()
    from public.matches match
    where participant.season_player_id = new.id
      and participant.match_id = match.id
      and match.status = 'a_venir'
      and participant.is_eligible;
  end if;

  return new;
end;
$function$;

comment on function private.sync_season_player_upcoming_matches() is
  'Keeps the season roster and the participant lists of upcoming matches aligned.';

drop trigger if exists trg_season_player_joins_upcoming_matches
  on public.season_players;

create trigger trg_season_player_joins_upcoming_matches
after insert or update of is_active on public.season_players
for each row
execute function private.sync_season_player_upcoming_matches();

-- ---------------------------------------------------------------------------
-- Rattrapage des matchs à venir déjà configurés.
--
-- Chaque membre actif de la saison reçoit la ligne qui lui manque, et tout
-- membre sorti de l'effectif quitte la rotation. Les deux opérations sont
-- idempotentes : sur une base déjà cohérente, elles ne touchent rien.
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

update public.match_sport_participants participant
set is_eligible = false,
    updated_at = now()
from public.matches match
where participant.match_id = match.id
  and match.status = 'a_venir'
  and participant.season_player_id is not null
  and participant.is_eligible
  and not exists (
    select 1
    from public.season_players player
    where player.id = participant.season_player_id
      and player.is_active
      and not player.is_coach
  );

commit;
