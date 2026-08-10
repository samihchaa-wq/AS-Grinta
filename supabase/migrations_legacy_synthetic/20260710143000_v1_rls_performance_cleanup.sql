begin;

drop policy if exists match_predictions_owner_insert on public.match_predictions;
create policy match_predictions_owner_insert
on public.match_predictions for insert to authenticated
with check (
  profile_id = (select auth.uid())
  and exists (
    select 1 from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < (((m.match_date + coalesce(m.match_time,'00:00:00'::time)) at time zone 'Europe/Paris') - interval '5 minutes')
  )
);

drop policy if exists match_predictions_owner_update_window on public.match_predictions;
create policy match_predictions_owner_update_window
on public.match_predictions for update to authenticated
using (profile_id = (select auth.uid()))
with check (
  profile_id = (select auth.uid())
  and exists (
    select 1 from public.matches m
    where m.id = match_predictions.match_id
      and m.status = 'a_venir'
      and now() < (((m.match_date + coalesce(m.match_time,'00:00:00'::time)) at time zone 'Europe/Paris') - interval '5 minutes')
  )
);

drop policy if exists matches_admin_insert on public.matches;
create policy matches_staff_insert
on public.matches for insert to authenticated
with check (public.is_match_staff() and created_by = (select auth.uid()));

drop policy if exists players_staff_read on public.players;
drop policy if exists players_self_read on public.players;
create policy players_authorized_read
on public.players for select to authenticated
using (public.is_match_staff() or linked_profile_id = (select auth.uid()));

commit;
