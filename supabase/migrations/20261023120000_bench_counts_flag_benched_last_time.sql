begin;

-- « Simuler la compo » : savoir qui a commencé remplaçant la dernière fois
-- qu'il a joué.
--
-- La simulation titularise en priorité ces joueurs : c'est leur tour de
-- commencer. L'écran Compo colore aussi leur compteur banc en bleu. Le
-- compteur banc cumulé, seul transmis jusqu'ici, ne le dit pas : à un
-- remplacement chacun, presque tout l'effectif est à égalité.
--
-- Chaque ligne gagne donc 'benched_last_time' : vrai si, au dernier match de
-- la saison où le participant (même joueur de l'effectif, ou même invité) a
-- joué avant celui-ci, il était remplaçant. Peu importe que ce match soit le
-- dernier de l'équipe : un joueur absent depuis garde son tour. Seuls
-- comptent les matchs terminés ou archivés où il figure sur la feuille,
-- titulaire ou remplaçant : un match entre nous n'a pas de feuille, un match
-- annulé n'est pas joué. Un joueur qui n'a pas encore joué de la saison
-- n'est pas signalé.
--
-- 'finished_bench_count' est inchangé, et un ancien client ignore
-- simplement la nouvelle clé. Le corps reprend sa dernière définition en
-- production (20260809232339_audit_priority_reliability_fixes.sql). Les
-- droits existants sont conservés par CREATE OR REPLACE.

create or replace function private.get_finished_bench_counts(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
  v_season_id uuid;
  v_kickoff_at timestamptz;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select target_match.season_id, target_match.kickoff_at
  into v_season_id, v_kickoff_at
  from public.matches target_match
  where target_match.id = p_match_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'participant_id', current_participant.id,
      'finished_bench_count', (
        select count(*)
        from public.match_sport_participants hist
        join public.matches hist_match on hist_match.id = hist.match_id
        where hist_match.status in ('termine', 'archive')
          and hist.match_id <> p_match_id
          and hist.final_selection_status = 'substitute'
          and (
            (current_participant.season_player_id is not null
              and hist.season_player_id = current_participant.season_player_id)
            or (current_participant.guest_player_id is not null
              and hist.guest_player_id = current_participant.guest_player_id)
          )
      ),
      'benched_last_time', coalesce((
        select previous.final_selection_status = 'substitute'
        from public.match_sport_participants previous
        join public.matches previous_match
          on previous_match.id = previous.match_id
        where previous_match.season_id = v_season_id
          and previous_match.id <> p_match_id
          and previous_match.kickoff_at < v_kickoff_at
          and previous_match.status in ('termine', 'archive')
          and previous.final_selection_status in ('starter', 'substitute')
          and (
            (current_participant.season_player_id is not null
              and previous.season_player_id = current_participant.season_player_id)
            or (current_participant.guest_player_id is not null
              and previous.guest_player_id = current_participant.guest_player_id)
          )
        order by previous_match.kickoff_at desc, previous_match.id desc
        limit 1
      ), false)
    )
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_participants current_participant
  where current_participant.match_id = p_match_id;

  return v_result;
end;
$function$;

commit;
