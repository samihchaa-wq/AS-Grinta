begin;

set local search_path = public, extensions, pg_catalog;
select no_plan();

select ok(
  private.is_known_non_player_archive_name('Philippe   Couzin'),
  'Philippe Couzin est identifié comme staff historique et non comme joueur'
);

select ok(
  private.resolve_historical_player_name('Philippe Couzin') is null,
  'le staff historique ne reçoit aucune identité canonique de joueur'
);

insert into public.opponents(id, name)
values ('ca600000-0000-0000-0000-000000000001', 'Adversaire test staff archive');

insert into public.historical_match_scores(
  id, opponent_id, match_date, score_as_grinta, score_adverse, is_home
)
values (
  'ca700000-0000-0000-0000-000000000001',
  'ca600000-0000-0000-0000-000000000001',
  date '2096-09-01', 1, 0, true
);

insert into public.historical_match_details(
  match_id, formation, field_players, bench_players, present_names, scorers, motm_names
)
values (
  'ca700000-0000-0000-0000-000000000001',
  'test',
  '[{"name":"Joueur Archive Test","is_gk":false,"x_pct":50,"y_pct":50}]'::jsonb,
  '[]'::jsonb,
  '["Joueur Archive Test","Philippe Couzin"]'::jsonb,
  '[]'::jsonb,
  '["Philippe Couzin"]'::jsonb
);

select ok(
  (
    select present_names @> '["Philippe Couzin"]'::jsonb
       and motm_names @> '["Philippe Couzin"]'::jsonb
    from public.historical_match_details
    where match_id = 'ca700000-0000-0000-0000-000000000001'::uuid
  ),
  'les JSON historiques d’origine conservent intégralement la mention du staff'
);

select is(
  (
    select count(*)
    from public.historical_match_players hmp
    where hmp.match_id = 'ca700000-0000-0000-0000-000000000001'::uuid
  ),
  1::bigint,
  'la projection normalisée du match ne contient que le vrai joueur'
);

select is(
  (
    select count(*)
    from public.historical_match_players hmp
    where hmp.match_id = 'ca700000-0000-0000-0000-000000000001'::uuid
      and private.is_known_non_player_archive_name(hmp.source_name)
  ),
  0::bigint,
  'Philippe Couzin est absent des joueurs normalisés du match'
);

select is(
  (
    select count(*)
    from public.historical_player_name_links link
    where link.normalized_name = private.normalize_player_name('Philippe Couzin')
  ),
  0::bigint,
  'aucun lien durable d’identité joueur n’est créé pour Philippe Couzin'
);

select * from finish();
rollback;
