-- Season predictions must have one authenticated mutation boundary.
-- The complete form RPC already validates and upserts the active roster in a
-- single transaction; remove table-level writes and direct private-function
-- execution so clients cannot bypass that atomic contract.

create or replace function public.save_my_season_predictions(
  p_season_id uuid,
  p_items jsonb
)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select private.save_my_season_predictions(p_season_id, p_items);
$function$;

comment on function public.save_my_season_predictions(uuid, jsonb) is
  'Unique authenticated write path for a complete season-prediction form.';

revoke insert, update, delete on table public.season_predictions
  from public, anon, authenticated;

revoke execute on function private.save_my_season_predictions(uuid, jsonb)
  from public, anon, authenticated;

revoke execute on function public.save_my_season_predictions(uuid, jsonb)
  from public, anon;
grant execute on function public.save_my_season_predictions(uuid, jsonb)
  to authenticated, service_role;
