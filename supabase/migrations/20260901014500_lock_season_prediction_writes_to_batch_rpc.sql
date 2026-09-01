-- Force all authenticated season-prediction mutations through the guarded
-- save_my_season_predictions batch RPC. Read access remains unchanged.

revoke insert, update on table public.season_predictions from authenticated;

drop policy if exists season_predictions_owner_insert
on public.season_predictions;

drop policy if exists season_predictions_owner_update
on public.season_predictions;
