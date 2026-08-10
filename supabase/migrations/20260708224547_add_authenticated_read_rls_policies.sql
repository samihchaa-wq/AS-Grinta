create policy "authenticated_read_profiles"
on public.profiles for select
to authenticated
using (true);

create policy "authenticated_read_seasons"
on public.seasons for select
to authenticated
using (true);

create policy "authenticated_read_season_players"
on public.season_players for select
to authenticated
using (true);

create policy "authenticated_read_opponents"
on public.opponents for select
to authenticated
using (true);

create policy "authenticated_read_matches"
on public.matches for select
to authenticated
using (true);

create policy "authenticated_read_match_participants"
on public.match_participants for select
to authenticated
using (true);

-- This production migration was originally applied after some of these tables
-- already existed outside the recorded migration history. During a clean replay,
-- create the legacy read policies only for relations that exist at this point.
do $$
declare
  relation_name text;
  policy_name text;
begin
  for relation_name, policy_name in
    select *
    from (values
      ('live_sessions', 'authenticated_read_live_sessions'),
      ('live_positions', 'authenticated_read_live_positions'),
      ('goals', 'authenticated_read_goals'),
      ('substitutions', 'authenticated_read_substitutions'),
      ('match_motm', 'authenticated_read_match_motm'),
      ('match_odds', 'authenticated_read_match_odds'),
      ('season_predictions', 'authenticated_read_season_predictions'),
      ('formations', 'authenticated_read_formations')
    ) as legacy_policy(relation_name, policy_name)
  loop
    if to_regclass(format('public.%I', relation_name)) is not null then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        policy_name,
        relation_name
      );
    end if;
  end loop;
end;
$$;

do $$
begin
  if to_regclass('public.match_predictions') is not null then
    execute $policy$
      create policy "read_own_or_revealed_match_predictions"
      on public.match_predictions for select
      to authenticated
      using (
        profile_id = (select auth.uid())
        or exists (
          select 1
          from public.matches m
          where m.id = match_predictions.match_id
            and m.status in ('termine', 'archive')
        )
      )
    $policy$;
  end if;
end;
$$;
