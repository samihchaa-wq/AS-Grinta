begin;

drop trigger if exists trg_create_match_odds on public.matches;
drop function if exists public.create_match_odds_after_insert();
drop function if exists public.compute_match_odds(uuid);

drop trigger if exists trg_seed_predictions_for_active_profile on public.profiles;
create trigger trg_seed_predictions_for_active_profile
after insert or update of status, role on public.profiles
for each row execute function public.seed_predictions_for_active_profile();

commit;
