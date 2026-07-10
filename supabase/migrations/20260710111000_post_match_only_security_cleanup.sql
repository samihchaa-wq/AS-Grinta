begin;
revoke all on function public.match_prediction_participant_count(uuid) from public, anon;
grant execute on function public.match_prediction_participant_count(uuid) to authenticated;
drop function if exists public.record_substitution(uuid,text,integer,uuid,uuid) cascade;
commit;
