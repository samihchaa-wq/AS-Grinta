begin;

-- « Simuler la compo » : savoir qui était remplaçant au dernier match.
--
-- La simulation titularise en priorité les joueurs qui ont commencé le
-- dernier match sur le banc. C'est la rotation que l'équipe pratique
-- réellement : sur chaque match de la saison 2026-2027, tous les remplaçants
-- du match précédent encore convoqués ont été titulaires. Le compteur banc
-- cumulé, seul transmis jusqu'ici, ne le dit pas : à un remplacement chacun,
-- presque tout l'effectif est à égalité.
--
-- Chaque ligne gagne donc 'benched_last_match' : vrai si le participant
-- (même joueur de l'effectif, ou même invité) était remplaçant au dernier
-- match de la même saison joué avant celui-ci. Seul compte un match terminé
-- ou archivé qui a une vraie feuille titulaires / remplaçants : un match
-- entre nous n'en a pas, un match annulé n'est pas joué. Le premier match
-- de la saison n'a donc pas de précédent, et personne n'y est signalé.
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
  v_previous_match_id uuid;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

  select previous_match.id
  into v_previous_match_id
  from public.matches target_match
  join public.matches previous_match
    on previous_match.season_id = target_match.season_id
   and previous_match.id <> target_match.id
   and previous_match.kickoff_at < target_match.kickoff_at
   and previous_match.status in ('termine', 'archive')
  where target_match.id = p_match_id
    and exists (
      select 1
      from public.match_sport_participants lineup
      where lineup.match_id = previous_match.id
        and lineup.final_selection_status in ('starter', 'substitute')
    )
  order by previous_match.kickoff_at desc, previous_match.id desc
  limit 1;

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
      'benched_last_match', exists (
        select 1
        from public.match_sport_participants previous
        where previous.match_id = v_previous_match_id
          and previous.final_selection_status = 'substitute'
          and (
            (current_participant.season_player_id is not null
              and previous.season_player_id = current_participant.season_player_id)
            or (current_participant.guest_player_id is not null
              and previous.guest_player_id = current_participant.guest_player_id)
          )
      )
    )
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_participants current_participant
  where current_participant.match_id = p_match_id;

  return v_result;
end;
$function$;

commit;
