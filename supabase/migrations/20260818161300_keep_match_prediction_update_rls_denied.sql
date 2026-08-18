-- Preserve the historical RLS contract that forbidden UPDATE attempts are
-- filtered to zero rows rather than failing at the table-GRANT layer.
-- There is deliberately no permissive UPDATE policy on match_predictions, so
-- authenticated clients still cannot mutate any row directly. The guarded
-- SECURITY DEFINER RPC remains the only effective write path.

grant update on table public.match_predictions to authenticated;

drop policy if exists match_predictions_owner_update_window
  on public.match_predictions;
