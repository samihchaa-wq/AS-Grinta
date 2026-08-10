-- Historical compatibility note:
-- production already contained several tables that were recorded later in the
-- migration history. A clean installation does not. Apply the intended read
-- policies to every table that exists at this point; later migrations install
-- the remaining definitive policies when those tables are created.

do $do$
declare
  item record;
begin
  for item in
    select *
    from (values
      ('profiles', 'authenticated_read_profiles'),
      ('seasons', 'authenticated_read_seasons'),
      ('season_players', 'authenticated_read_season_players'),
      ('opponents', 'authenticated_read_opponents'),
      ('matches', 'authenticated_read_matches'),
      ('match_participants', 'authenticated_read_match_participants'),
      ('live_sessions', 'authenticated_read_live_sessions'),
      ('live_positions', 'authenticated_read_live_positions'),
      ('goals', 'authenticated_read_goals'),
      ('substitutions', 'authenticated_read_substitutions'),
      ('match_motm', 'authenticated_read_match_motm'),
      ('match_odds', 'authenticated_read_match_odds'),
      ('season_predictions', 'authenticated_read_season_predictions'),
      ('formations', 'authenticated_read_formations')
    ) as policies(table_name, policy_name)
  loop
    if to_regclass(format('public.%I', item.table_name)) is not null then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        item.policy_name,
        item.table_name
      );
    end if;
  end loop;

  if to_regclass('public.match_predictions') is not null then
    execute $sql$
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
    $sql$;
  end if;
end
$do$;
