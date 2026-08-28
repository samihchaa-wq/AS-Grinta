begin;

-- Compte rendu de match : modèle de lecture.
--
-- Un seul appel alimente les deux onglets de l'écran « Compte rendu » :
--   * Effectif      -> `lineup`, au format exact de l'éditeur de composition ;
--   * Faits du match -> `goal_actions`, la chronologie des buts des deux camps.

-- ---------------------------------------------------------------------------
-- 1. Chronologie des buts, avec les noms affichables
-- ---------------------------------------------------------------------------

create or replace function private.match_sport_goal_actions_json(p_match_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', action.id,
        'ordinal', action.ordinal,
        'minute', action.minute,
        'team_side', action.team_side,
        'scorer_participant_id', action.scorer_participant_id,
        'scorer_name', case
          when scorer_guest.id is not null then
            btrim(scorer_guest.first_name) || ' (Invité)'
          else coalesce(
            nullif(btrim(scorer_profile.surnom), ''),
            nullif(btrim(scorer_profile.first_name), ''),
            nullif(btrim(scorer_player.first_name), '')
          )
        end,
        'assist_participant_id', action.assist_participant_id,
        'assist_kind', action.assist_kind,
        'assist_name', case
          when assist_guest.id is not null then
            btrim(assist_guest.first_name) || ' (Invité)'
          else coalesce(
            nullif(btrim(assist_profile.surnom), ''),
            nullif(btrim(assist_profile.first_name), ''),
            nullif(btrim(assist_player.first_name), '')
          )
        end,
        'is_own_goal', action.is_own_goal,
        'source', action.source,
        'source_live_event_id', action.source_live_event_id
      ) order by action.ordinal
    ),
    '[]'::jsonb
  )
  from public.match_sport_goal_actions action
  left join public.match_sport_participants scorer_p
    on scorer_p.id = action.scorer_participant_id
  left join public.season_players scorer_player
    on scorer_player.id = scorer_p.season_player_id
  left join public.profiles scorer_profile
    on scorer_profile.id = scorer_player.profile_id
  left join public.guest_players scorer_guest
    on scorer_guest.id = scorer_p.guest_player_id
  left join public.match_sport_participants assist_p
    on assist_p.id = action.assist_participant_id
  left join public.season_players assist_player
    on assist_player.id = assist_p.season_player_id
  left join public.profiles assist_profile
    on assist_profile.id = assist_player.profile_id
  left join public.guest_players assist_guest
    on assist_guest.id = assist_p.guest_player_id
  where action.match_id = p_match_id;
$function$;

alter function private.match_sport_goal_actions_json(uuid) owner to postgres;
revoke all on function private.match_sport_goal_actions_json(uuid) from public;
revoke all on function private.match_sport_goal_actions_json(uuid) from authenticated;

-- ---------------------------------------------------------------------------
-- 2. Effectif du compte rendu, au format de l'éditeur de composition
-- ---------------------------------------------------------------------------
--
-- Règles de reprise, dans l'ordre :
--   1. match déjà validé            -> la composition retenue à la validation ;
--   2. Live démarré                 -> la composition **du coup d'envoi**,
--                                      jamais celle d'après les changements ;
--   3. composition existante        -> telle quelle ;
--   4. aucune composition           -> terrain vide, tout le monde sur le banc.
--
-- Dans le cas 2, un joueur ajouté pendant le Live n'apparaît pas au coup
-- d'envoi : il est repris sur le banc plutôt que perdu.

create or replace function private.match_sport_report_lineup(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_has_finalization boolean;
  v_start_zones jsonb;
  v_start_entries jsonb;
  v_start_formation text;
  v_formation_code text;
  v_live_started boolean;
  v_has_placement boolean;
  v_result jsonb;
begin
  select exists (
    select 1
    from public.match_sport_finalizations finalization
    where finalization.match_id = p_match_id
  ) into v_has_finalization;

  select
    session.starting_lineup_snapshot,
    session.starting_lineup_entries,
    session.starting_formation_code,
    session.started_at is not null
  into v_start_zones, v_start_entries, v_start_formation, v_live_started
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  select composition.formation_code
  into v_formation_code
  from public.match_compositions composition
  where composition.match_id = p_match_id;

  select exists (
    select 1
    from public.match_composition_entries entry
    where entry.match_id = p_match_id
      and entry.zone in ('field', 'bench')
  ) into v_has_placement;

  with resolved as (
    select
      participant.id as participant_id,
      participant.season_player_id,
      participant.guest_player_id,
      participant.availability_status,
      participant.convocation_status,
      participant.selection_status,
      player.is_goalkeeper as player_goalkeeper,
      guest.is_goalkeeper as guest_goalkeeper,
      guest.id as guest_id,
      guest.first_name as guest_first_name,
      guest.last_name as guest_last_name,
      guest.photo_url as guest_photo,
      profile.surnom as profile_surnom,
      profile.first_name as profile_first_name,
      profile.photo_url as profile_photo,
      player.first_name as player_first_name,
      player.last_name as player_last_name,
      player.photo_url as player_photo,
      entry.zone::text as current_zone,
      entry.x as current_x,
      entry.y as current_y,
      entry.slot_label as current_slot,
      coalesce(entry.sort_order, 900) as current_sort,
      v_start_entries -> participant.id::text as start_entry,
      case
        when v_has_finalization then
          case
            -- Un joueur rattaché après la validation n'a encore aucun statut :
            -- il rejoint le banc plutôt que la liste des joueurs retirés.
            when participant.final_presence_status = 'pending' then 'bench'
            when participant.final_presence_status <> 'present' then 'not_selected'
            when participant.final_selection_status = 'starter' then 'field'
            else 'bench'
          end
        when coalesce(v_start_entries, '{}'::jsonb) ? participant.id::text then
          v_start_entries -> participant.id::text ->> 'zone'
        when coalesce(v_start_zones, '{}'::jsonb) ? participant.id::text then
          v_start_zones ->> participant.id::text
        when coalesce(v_live_started, false) then
          -- Joueur ajouté après le coup d'envoi : il fait partie de l'effectif
          -- du compte rendu, sur le banc.
          case
            when entry.zone in ('field', 'bench') then 'bench'
            else 'not_selected'
          end
        when v_has_placement then coalesce(entry.zone::text, 'not_selected')
        else 'bench'
      end as zone,
      case
        when v_has_finalization then 'finalization'
        when coalesce(v_start_entries, '{}'::jsonb) ? participant.id::text then 'kickoff'
        else 'composition'
      end as zone_source
    from public.match_sport_participants participant
    left join public.match_composition_entries entry
      on entry.match_id = p_match_id
     and entry.participant_id = participant.id
    left join public.season_players player
      on player.id = participant.season_player_id
    left join public.profiles profile
      on profile.id = player.profile_id
    left join public.guest_players guest
      on guest.id = participant.guest_player_id
    where participant.match_id = p_match_id
      and (
        participant.is_eligible
        or participant.final_presence_status <> 'pending'
      )
  )
  select jsonb_build_object(
    'match_id', p_match_id,
    'formation_code', case
      when v_has_finalization then coalesce(v_formation_code, v_start_formation)
      else coalesce(v_start_formation, v_formation_code)
    end,
    'status', 'draft',
    'version', 0,
    'has_unpublished_changes', true,
    'squad_size_exception_approved', false,
    'entries', coalesce(
      jsonb_agg(
        jsonb_build_object(
          'participant_id', resolved.participant_id,
          'season_player_id', resolved.season_player_id,
          'guest_player_id', resolved.guest_player_id,
          'is_guest', resolved.guest_id is not null,
          'display_name', case
            when resolved.guest_id is not null then
              btrim(concat_ws(' ', resolved.guest_first_name, resolved.guest_last_name))
                || ' (Invité)'
            else coalesce(
              nullif(btrim(resolved.profile_surnom), ''),
              nullif(btrim(resolved.profile_first_name), ''),
              nullif(btrim(resolved.player_first_name), ''),
              btrim(concat_ws(' ', resolved.player_first_name, resolved.player_last_name))
            )
          end,
          'photo_url', coalesce(
            resolved.profile_photo, resolved.player_photo, resolved.guest_photo
          ),
          'is_goalkeeper', coalesce(
            resolved.player_goalkeeper, resolved.guest_goalkeeper, false
          ),
          'zone', resolved.zone,
          'x', case
            when resolved.zone <> 'field' then null
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'x')::double precision, resolved.current_x)
            else resolved.current_x
          end,
          'y', case
            when resolved.zone <> 'field' then null
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'y')::double precision, resolved.current_y)
            else resolved.current_y
          end,
          'slot_label', case
            when resolved.zone_source = 'kickoff'
              then coalesce(resolved.start_entry ->> 'slot_label', resolved.current_slot)
            else resolved.current_slot
          end,
          'sort_order', case
            when resolved.zone_source = 'kickoff'
              then coalesce((resolved.start_entry ->> 'sort_order')::integer, resolved.current_sort)
            else resolved.current_sort
          end,
          'availability_status', resolved.availability_status,
          'convocation_status', resolved.convocation_status,
          'selection_status', resolved.selection_status
        ) order by
          case resolved.zone
            when 'field' then 1
            when 'bench' then 2
            else 3
          end,
          resolved.current_sort,
          lower(coalesce(
            resolved.profile_surnom, resolved.profile_first_name,
            resolved.player_first_name, resolved.guest_first_name
          )),
          resolved.participant_id
      ),
      '[]'::jsonb
    )
  )
  into v_result
  from resolved;

  return v_result;
end;
$function$;

alter function private.match_sport_report_lineup(uuid) owner to postgres;
revoke all on function private.match_sport_report_lineup(uuid) from public;
revoke all on function private.match_sport_report_lineup(uuid) from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Les faits du match entrent dans l'instantané versionné
-- ---------------------------------------------------------------------------
--
-- Même corps qu'en 20260827160100, avec `goal_actions` en plus : chaque version
-- archivée du compte rendu conserve donc la liste exacte des buts.

create or replace function private.match_sport_finalization_snapshot(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  with latest_publication as (
    select publication.version, publication.snapshot
    from public.match_composition_publications publication
    where publication.match_id = p_match_id
    order by publication.version desc
    limit 1
  ), planned_entries as (
    select
      (entry ->> 'participant_id')::uuid as participant_id,
      entry ->> 'zone' as planned_zone
    from latest_publication publication,
      lateral jsonb_array_elements(
        coalesce(publication.snapshot -> 'entries', '[]'::jsonb)
      ) entry
  )
  select jsonb_build_object(
    'match_id', match.id,
    'opponent_name', opponent.name,
    'is_home', match.location = 'domicile',
    'kickoff_at', match.kickoff_at,
    'match_status', match.status,
    'is_validated', finalization.match_id is not null,
    'version', coalesce(finalization.version, 0),
    'score_as_grinta', coalesce(finalization.score_as_grinta, match.score_as_grinta, 0),
    'score_adverse', coalesce(finalization.score_adverse, match.score_adverse, 0),
    'composition_version', coalesce(finalization.composition_version, workflow.composition_version, 0),
    'presence_state', workflow.presence_state,
    'vote_state', workflow.vote_state,
    'validated_at', finalization.validated_at,
    'corrected_at', finalization.corrected_at,
    'goal_actions', private.match_sport_goal_actions_json(p_match_id),
    'participants', coalesce(jsonb_agg(
      jsonb_build_object(
        'participant_id', participant.id,
        'season_player_id', participant.season_player_id,
        'guest_player_id', participant.guest_player_id,
        'is_guest', participant.guest_player_id is not null,
        'display_name', case
          when guest.id is not null then
            btrim(concat_ws(' ', guest.first_name, guest.last_name)) || ' (Invité)'
          else coalesce(
            nullif(btrim(profile.surnom), ''), nullif(btrim(profile.first_name), ''),
            nullif(btrim(player.first_name), ''),
            btrim(concat_ws(' ', player.first_name, player.last_name))
          )
        end,
        'photo_url', coalesce(profile.photo_url, player.photo_url, guest.photo_url),
        'is_goalkeeper', coalesce(player.is_goalkeeper, guest.is_goalkeeper, false),
        'planned_zone', coalesce(planned.planned_zone, case participant.selection_status
          when 'starter' then 'field'
          when 'substitute' then 'bench'
          when 'not_selected' then 'not_selected'
          else 'available'
        end),
        'present', case
          when finalization.match_id is not null then participant.final_presence_status = 'present'
          else coalesce(planned.planned_zone in ('field', 'bench'), false)
        end,
        'final_presence_status', participant.final_presence_status,
        'final_selection_status', case
          when finalization.match_id is not null then participant.final_selection_status
          when planned.planned_zone = 'field' then 'starter'::public.sport_selection_status
          when planned.planned_zone = 'bench' then 'substitute'::public.sport_selection_status
          else 'not_selected'::public.sport_selection_status
        end,
        'goals', participant.final_goals,
        'assists', participant.final_assists,
        'clean_sheet', participant.final_clean_sheet,
        'is_motm', exists (
          select 1
          from public.match_sport_motm_results result
          where result.match_id = p_match_id
            and result.participant_id = participant.id
            and result.is_winner
            and result.finalization_version = (
              select max(latest.finalization_version)
              from public.match_sport_motm_results latest
              where latest.match_id = p_match_id
            )
        )
      ) order by
        case coalesce(planned.planned_zone, '')
          when 'field' then 1
          when 'bench' then 2
          else 3
        end,
        lower(coalesce(profile.surnom, profile.first_name, player.first_name, guest.first_name)),
        participant.id
    ) filter (
      where participant.id is not null
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    ), '[]'::jsonb)
  ) into v_result
  from public.matches match
  join public.opponents opponent on opponent.id = match.opponent_id
  join public.match_sport_workflows workflow on workflow.match_id = match.id
  left join public.match_sport_finalizations finalization on finalization.match_id = match.id
  left join public.match_sport_participants participant on participant.match_id = match.id
  left join public.season_players player on player.id = participant.season_player_id
  left join public.profiles profile on profile.id = player.profile_id
  left join public.guest_players guest on guest.id = participant.guest_player_id
  left join planned_entries planned on planned.participant_id = participant.id
  where match.id = p_match_id
  group by match.id, opponent.name, workflow.match_id, finalization.match_id;

  return v_result;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Modèle de lecture complet du compte rendu
-- ---------------------------------------------------------------------------

create or replace function private.get_match_sport_report(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_base jsonb;
  v_live_state text;
  v_live_exported boolean;
  v_live_finished boolean;
  v_status text;
  v_closes_at timestamptz;
  v_is_validated boolean;
  v_season_id uuid;
  v_roster jsonb;
  v_guests jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() and not private.is_match_coach_or_admin(p_match_id) then
    raise exception 'Coach or administrator role required' using errcode = '42501';
  end if;

  select match.status::text, match.season_id
  into v_status, v_season_id
  from public.matches match
  where match.id = p_match_id;

  if not found then
    raise exception 'Match introuvable.' using errcode = 'P0002';
  end if;

  v_base := private.match_sport_finalization_snapshot(p_match_id);
  if v_base is null then
    raise exception 'Sport match workflow not found' using errcode = 'P0002';
  end if;

  v_is_validated := coalesce((v_base ->> 'is_validated')::boolean, false);
  v_closes_at := private.match_postgame_correction_closes_at(p_match_id);

  select session.state::text, session.exported, session.state = 'finished'
  into v_live_state, v_live_exported, v_live_finished
  from public.match_live_sessions session
  where session.match_id = p_match_id;

  -- Joueurs qu'on peut encore ajouter à l'effectif du compte rendu : ceux du
  -- roster sans participation ouverte, et les invités réutilisables.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'season_player_id', candidate.season_player_id,
      'display_name', candidate.display_name,
      'photo_url', candidate.photo_url,
      'is_goalkeeper', candidate.is_goalkeeper,
      'is_guest', false
    ) order by lower(candidate.display_name), candidate.season_player_id
  ), '[]'::jsonb)
  into v_roster
  from (
    select
      player.id as season_player_id,
      coalesce(
        nullif(btrim(profile.surnom), ''),
        nullif(btrim(profile.first_name), ''),
        nullif(btrim(player.first_name), ''),
        btrim(concat_ws(' ', player.first_name, player.last_name)),
        'Joueur'
      ) as display_name,
      coalesce(profile.photo_url, player.photo_url) as photo_url,
      player.is_goalkeeper
    from public.season_players player
    left join public.profiles profile on profile.id = player.profile_id
    where player.season_id = v_season_id
      and player.is_active
      and (player.profile_id is null or profile.status = 'active')
      and not exists (
        select 1
        from public.match_sport_participants participant
        where participant.match_id = p_match_id
          and participant.season_player_id = player.id
          and (
            participant.is_eligible
            or participant.final_presence_status <> 'pending'
          )
      )
  ) candidate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'guest_player_id', guest.id,
      'display_name', btrim(concat_ws(' ', guest.first_name, guest.last_name)),
      'photo_url', guest.photo_url,
      'is_goalkeeper', guest.is_goalkeeper,
      'is_guest', true
    ) order by lower(guest.first_name), guest.id
  ), '[]'::jsonb)
  into v_guests
  from public.guest_players guest
  where guest.is_reusable
    and guest.archived_at is null
    and not exists (
      select 1
      from public.match_sport_participants participant
      where participant.match_id = p_match_id
        and participant.guest_player_id = guest.id
        and (
          participant.is_eligible
          or participant.final_presence_status <> 'pending'
        )
    );

  return v_base || jsonb_build_object(
    'lineup', private.match_sport_report_lineup(p_match_id),
    'is_correction', v_is_validated,
    'correction_closes_at', v_closes_at,
    'is_editable', v_status <> 'archive'
      and (
        not v_is_validated
        or v_closes_at is null
        or now() < v_closes_at
      ),
    'live_state', v_live_state,
    'live_exported', coalesce(v_live_exported, false),
    'live_finished', coalesce(v_live_finished, false),
    'add_player_options', jsonb_build_object(
      'roster', v_roster,
      'guests', v_guests
    )
  );
end;
$function$;

alter function private.get_match_sport_report(uuid) owner to postgres;
revoke all on function private.get_match_sport_report(uuid) from public;
-- La façade publique s'exécute avec les droits de l'appelant : il lui faut
-- donc le droit d'exécuter la fonction interne, qui porte elle-même le
-- contrôle d'accès.
grant execute on function private.get_match_sport_report(uuid) to authenticated;
grant execute on function private.get_match_sport_report(uuid) to service_role;

create or replace function public.admin_get_match_sport_report(p_match_id uuid)
returns jsonb
language sql
stable
set search_path to ''
as $function$ select private.get_match_sport_report(p_match_id); $function$;

alter function public.admin_get_match_sport_report(uuid) owner to postgres;
revoke all on function public.admin_get_match_sport_report(uuid) from public;
grant execute on function public.admin_get_match_sport_report(uuid) to authenticated;
grant execute on function public.admin_get_match_sport_report(uuid) to service_role;

comment on function public.admin_get_match_sport_report(uuid) is
  'Compte rendu de match : effectif rejouable, faits du match et fenêtre de correction, en un seul appel.';

commit;

begin;

-- ---------------------------------------------------------------------------
-- 5. Lecture publique des faits du match
-- ---------------------------------------------------------------------------
--
-- La fiche du match affiche « Faits du match ». Tant que les buts définitifs
-- n'existaient que dans le journal du Live, corriger le compte rendu laissait
-- ce bloc afficher l'ancienne version. Il lit désormais les faits durables :
-- une correction se voit tout de suite, et un match sans Live en a aussi.

create or replace function private.get_match_sport_goal_actions(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  perform private.require_sports_management_enabled();
  if not private.is_active_profile() then
    raise exception 'Active profile required' using errcode = '42501';
  end if;

  -- Les faits ne sont publics qu'une fois le compte rendu validé.
  if not exists (
    select 1
    from public.match_sport_finalizations finalization
    where finalization.match_id = p_match_id
  ) then
    return '[]'::jsonb;
  end if;

  return private.match_sport_goal_actions_json(p_match_id);
end;
$function$;

alter function private.get_match_sport_goal_actions(uuid) owner to postgres;
revoke all on function private.get_match_sport_goal_actions(uuid) from public;
grant execute on function private.get_match_sport_goal_actions(uuid) to authenticated;
grant execute on function private.get_match_sport_goal_actions(uuid) to service_role;

create or replace function public.get_match_sport_goal_actions(p_match_id uuid)
returns jsonb
language sql
stable
set search_path to ''
as $function$ select private.get_match_sport_goal_actions(p_match_id); $function$;

alter function public.get_match_sport_goal_actions(uuid) owner to postgres;
revoke all on function public.get_match_sport_goal_actions(uuid) from public;
grant execute on function public.get_match_sport_goal_actions(uuid) to authenticated;
grant execute on function public.get_match_sport_goal_actions(uuid) to service_role;

comment on function public.get_match_sport_goal_actions(uuid) is
  'Buts définitifs du compte rendu, pour le bloc « Faits du match » de la fiche.';

commit;
