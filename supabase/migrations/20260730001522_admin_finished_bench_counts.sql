-- Nombre de fois où chaque joueur convoqué à un match a déjà été noté
-- « remplaçant » (banc) dans un match déjà terminé. Sert à afficher un petit
-- repère dans l'écran de composition d'un match à venir, pour aider l'admin
-- à équilibrer le temps de jeu.
create or replace function private.get_finished_bench_counts(p_match_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  perform private.require_sports_management_enabled();
  if not private.is_admin() then
    raise exception 'Active administrator role required' using errcode = '42501';
  end if;

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
      )
    )
  ), '[]'::jsonb)
  into v_result
  from public.match_sport_participants current_participant
  where current_participant.match_id = p_match_id;

  return v_result;
end;
$function$;

create or replace function public.admin_get_finished_bench_counts(p_match_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $function$ select private.get_finished_bench_counts(p_match_id); $function$;

revoke execute on function private.get_finished_bench_counts(uuid) from public, anon;
revoke execute on function public.admin_get_finished_bench_counts(uuid) from public, anon;

grant execute on function private.get_finished_bench_counts(uuid) to authenticated, service_role;
grant execute on function public.admin_get_finished_bench_counts(uuid) to authenticated, service_role;
